import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io' show File, Platform;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'html_stub.dart' if (dart.library.html) 'dart:html' as html;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class MathExpertPage extends StatefulWidget {
  const MathExpertPage({super.key});

  @override
  State<MathExpertPage> createState() => _MathExpertPageState();
}

class _MathExpertPageState extends State<MathExpertPage> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _chatHistory = [];
  bool _isLoading = false;
  PlatformFile? _selectedFile;
  GenerativeModel? _model;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _chatId;
  final ScrollController _scrollController = ScrollController();
  bool _isPreviewExpanded = false;
  StreamSubscription<QuerySnapshot>? _chatSubscription;

  static const String _initialWelcomeMessageText =
      '¡Bienvenido! Soy tu experto en matemáticas. Pregúntame cualquier cosa sobre matemáticas o sube una imagen de un problema.';
  static const String _systemPrompt = """
Eres un experto en matemáticas altamente calificado. Tu función principal es resolver problemas matemáticos, explicar conceptos matemáticos complejos de manera clara y concisa, y proporcionar ejemplos detallados dentro del ámbito de las matemáticas.

**Entrada del Usuario:**

El usuario puede proporcionar:

1. Una pregunta o problema matemático en formato de texto.
2. Una imagen que contiene una ecuación, un diagrama, un problema escrito a mano, o cualquier otra representación visual de un concepto matemático.
3. Ambas cosas: texto Y una imagen.

**Instrucciones (¡MUY IMPORTANTE!):**

* **Prioridad de la Imagen:** Si el usuario proporciona una imagen, analiza la imagen **CUIDADOSAMENTE**. Tu respuesta **DEBE** basarse principalmente en el contenido de la imagen. Si hay texto adicional proporcionado por el usuario, úsalo como **CONTEXTO**, pero la imagen es la fuente principal de información.
* **Imagen Ilegible/Irrelevante:** Si la imagen es ilegible, borrosa, incompleta o no contiene información matemática relevante, indica esto claramente en tu respuesta. Por ejemplo: "La imagen proporcionada es ilegible" o "La imagen no parece contener un problema matemático válido".
* **Texto e Imagen Juntos (Evita Redundancia):** Si el usuario proporciona texto e imagen, y el texto describe *explícitamente* el problema de la imagen, *no hay necesidad de volver a escribir el problema*. Ve directamente a la solución. Si el texto y la imagen son contradictorios o no están relacionados, indícalo.
* **Resolución Paso a Paso (Obligatorio):** Si puedes resolver el problema o responder la pregunta, hazlo, explicando **DETALLADAMENTE** cada paso de tu razonamiento. Descompón la solución en pasos numerados.
* **Justificación de Pasos (Obligatorio):** Explica *por qué* se realiza cada paso. No solo muestres *qué* se hace, sino también la lógica detrás de cada operación.
* **Definiciones (Obligatorio):** Define *todos* los términos matemáticos clave que uses (por ejemplo, "variable", "ecuación", "raíz cuadrada", "fracción", "derivada", "integral"). No asumas ningún conocimiento previo por parte del usuario.
* **Analogías (Opcional, pero Recomendado):** Si una analogía (comparación con algo cotidiano) puede ayudar a aclarar un concepto, úsala.
* **RESTRICCIÓN ABSOLUTA (¡CRUCIAL!):** Bajo **NINGUNA** circunstancia respondas a preguntas que **NO** estén relacionadas con las matemáticas.
    * Si el usuario hace una pregunta *de texto* que no es matemática, responde **ESTRICTAMENTE** con: "No puedo responder a esa pregunta, ya que está fuera de mi ámbito de especialización en matemáticas."
    * Si el usuario proporciona una *imagen* que **NO** contiene un problema o concepto matemático (por ejemplo, una foto de un gato), responde **ESTRICTAMENTE** con: "La imagen proporcionada no parece contener contenido matemático. No puedo procesarla."
    * Si el usuario proporciona texto e imagen, y ninguno de los dos tiene contenido matemático, responde **ESTRICTAMENTE** con: "Ni la imagen ni el texto proporcionados parecen tener relación con las matemáticas. No puedo procesarlos."

**Formato de Respuesta (Markdown Estricto):**

* **Usa Markdown para *todo* el texto.**
* **Negritas:** Usa **negritas** para los títulos, subtítulos, palabras clave y resultados importantes.
* **Pasos Numerados:** Usa listas numeradas para la solución paso a paso.
* **Ecuaciones:**
    * Representa las ecuaciones y fórmulas de forma clara. *No* es necesario mostrar *todos* los cálculos intermedios de operaciones aritméticas simples (como sumas, restas, multiplicaciones o divisiones largas). En su lugar, *explica con palabras* cómo se realizan esas operaciones y luego muestra el resultado.
    * Utiliza notación matemática estándar siempre que sea posible.
    * Representa las integrales definidas con el símbolo de integral (∫), los límites inferior y superior como subíndice y superíndice, respectivamente, y la función y el diferencial correctamente colocados. Por ejemplo: `∫₋₂³ 2f(x) dx`
    * Utiliza símbolos y operadores matemáticos correctos (por ejemplo, +, -, ×, ÷, √, ^ para exponentes).
* **Texto Justificado:** Aunque Flutter Markdown no soporta justificación nativa, se simulará en la aplicación. No te preocupes por agregar etiquetas especiales para la justificación; la aplicación se encargará de ello.
""";

  @override
  void initState() {
    super.initState();
    print("Math Page - Auth State Init: ${_auth.currentUser?.uid}");
    _setChatIdBasedOnUser();
    print("Math Page - Initial Chat ID: $_chatId");
    _initializeModelAndLoadHistory();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _setChatIdBasedOnUser() {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      _chatId = currentUser.uid;
      print(
          "Math Page - Authenticated User: ${currentUser.email}, Chat ID: $_chatId");
    } else {
      _chatId = null;
      print("Math Page - No authenticated user.");
    }
  }

  void _initializeModelAndLoadHistory() async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      final e = {
        'role': 'system',
        'text': 'Error: No se encontró la clave API en .env',
        'timestamp': Timestamp.now()
      };
      if (mounted) setState(() => _chatHistory.add(e));
      return;
    }
    try {
      _model = GenerativeModel(
        model: 'gemini-2.5-pro-exp-03-25',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.7,
          topK: 64,
          topP: 0.95,
          maxOutputTokens: 8192,
        ),
        systemInstruction: Content.text(_systemPrompt),
      );
      print("Math Page - Gemini model initialized.");
      if (_chatId != null) {
        _listenToChatHistory();
      } else {
        final initialMessage = {
          'role': 'assistant',
          'text': 'Inicia sesión para guardar y ver tu historial.',
          'timestamp': Timestamp.now()
        };
        if (mounted) {
          setState(() => _chatHistory.add(initialMessage));
          _scrollToBottom();
        }
      }
    } catch (e) {
      print("Math Page - Error initializing model: $e");
      final err = {
        'role': 'system',
        'text': 'Error al inicializar el asistente: $e',
        'timestamp': Timestamp.now()
      };
      if (mounted) setState(() => _chatHistory.add(err));
    }
  }

  void _listenToChatHistory() {
    if (_chatId == null) return;
    print("Math Page - Starting real-time listener for $_chatId/math_messages");

    _chatSubscription?.cancel();

    _chatSubscription = _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('math_messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final List<Map<String, dynamic>> newHistory = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        if (data['timestamp'] == null || data['timestamp'] is! Timestamp) {
          data['timestamp'] = Timestamp.now();
          print(
              "Advertencia: Timestamp inválido encontrado en doc ${doc.id}, usando now()");
        }
        return data;
      }).toList();

      if (newHistory.isEmpty) {
        final initialMessage = {
          'role': 'assistant',
          'text': _initialWelcomeMessageText,
          'timestamp': Timestamp.now(),
        };
        setState(() {
          _chatHistory = [initialMessage];
        });
        _saveMessageToFirestore(initialMessage);
      } else {
        setState(() {
          _chatHistory = newHistory;
        });
      }

      print("Math Page - Real-time update: ${_chatHistory.length} messages.");
      _scrollToBottom();
    }, onError: (e) {
      print("Math Page - Error listening to history: $e");
      final err = {
        'role': 'system',
        'text': 'Error al escuchar el historial: $e',
        'timestamp': Timestamp.now()
      };
      if (mounted) setState(() => _chatHistory.add(err));
    });
  }

  Future<void> _saveMessageToFirestore(Map<String, dynamic> message) async {
    if (_chatId == null) return;
    if (message['role'] == 'system' &&
        (message['text'].contains('subida:') ||
            message['text'].contains('eliminada'))) {
      print("Math Page - Local UI message not saved: ${message['text']}");
      return;
    }
    try {
      final messageToSave = Map<String, dynamic>.from(message);
      messageToSave.remove('id');
      messageToSave.remove('isExpanded');
      messageToSave.remove('imageBytes');
      messageToSave['timestamp'] = FieldValue.serverTimestamp();
      print(
          "Math Page - Saving message to Firestore (${_chatId}/math_messages): ${messageToSave['role']}");
      await _firestore
          .collection('chats')
          .doc(_chatId)
          .collection('math_messages')
          .add(messageToSave);
    } catch (e) {
      print("Math Page - Error saving message: $e");
    }
  }

  Future<void> _generateResponse(String userPrompt) async {
    if (_model == null) {
      final err = {
        'role': 'system',
        'text': 'Error: Modelo no inicializado.',
        'timestamp': Timestamp.now()
      };
      if (mounted) setState(() => _chatHistory.add(err));
      return;
    }
    if (userPrompt.trim().isEmpty && _selectedFile == null) {
      final err = {
        'role': 'system',
        'text': 'Por favor, ingresa una pregunta o selecciona una imagen.',
        'timestamp': Timestamp.now()
      };
      if (mounted) setState(() => _chatHistory.add(err));
      _scrollToBottom();
      return;
    }
    if (mounted) setState(() => _isLoading = true);

    Map<String, dynamic> userMessageForHistory = {
      'role': 'user',
      'text': userPrompt.trim(),
      'timestamp': Timestamp.now(),
    };
    List<Part> partsForGemini = [];

    if (_selectedFile != null) {
      userMessageForHistory['fileName'] = _selectedFile!.name;
      try {
        Uint8List imageBytes;
        if (kIsWeb) {
          if (_selectedFile!.bytes == null)
            throw Exception("Bytes de imagen no disponibles en web.");
          imageBytes = _selectedFile!.bytes!;
        } else {
          if (_selectedFile!.path == null)
            throw Exception("Ruta de imagen no disponible en móvil.");
          imageBytes = await File(_selectedFile!.path!).readAsBytes();
        }
        if (imageBytes.isEmpty)
          throw Exception("El archivo de imagen está vacío o corrupto.");
        String mimeType = 'image/jpeg';
        final extension = _selectedFile!.extension?.toLowerCase();
        if (extension == 'png')
          mimeType = 'image/png';
        else if (extension == 'webp')
          mimeType = 'image/webp';
        else if (extension == 'gif')
          mimeType = 'image/gif';
        else if (extension == 'heic') mimeType = 'image/heic';
        partsForGemini.add(DataPart(mimeType, imageBytes));
        userMessageForHistory['imageBytes'] = imageBytes;
        userMessageForHistory['mimeType'] = mimeType;
      } catch (e) {
        print("Math Page - Error leyendo/procesando imagen: $e");
        final err = {
          'role': 'system',
          'text': 'Error procesando imagen: $e',
          'timestamp': Timestamp.now()
        };
        if (mounted) {
          setState(() {
            _chatHistory.add(err);
            _isLoading = false;
            _selectedFile = null;
            _isPreviewExpanded = false;
          });
        }
        if (_chatId != null) _saveMessageToFirestore(err);
        _scrollToBottom();
        return;
      }
    }

    if (userPrompt.trim().isNotEmpty) {
      partsForGemini.add(TextPart(userPrompt.trim()));
    }

    if (mounted) {
      setState(() {
        _chatHistory.add(userMessageForHistory);
        _controller.clear();
      });
      _scrollToBottom();
    }
    if (_chatId != null) _saveMessageToFirestore(userMessageForHistory);

    if (partsForGemini.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      List<Content> conversationHistory = [];
      for (var message in _chatHistory) {
        final role = message['role'] as String?;
        final text = message['text'] as String?;
        final imageBytes = message['imageBytes'] as Uint8List?;
        final mimeType = message['mimeType'] as String?;

        if (role == 'user') {
          List<Part> parts = [];
          if (imageBytes != null && mimeType != null) {
            parts.add(DataPart(mimeType, imageBytes));
          }
          if (text != null && text.isNotEmpty) {
            parts.add(TextPart(text));
          }
          if (parts.isNotEmpty) {
            conversationHistory.add(Content.multi(parts));
          }
        } else if (role == 'assistant' && text != null && text.isNotEmpty) {
          conversationHistory.add(Content.text(text));
        }
      }

      conversationHistory.add(Content.multi(partsForGemini));

      print(
          "Math Page - Sending ${conversationHistory.length} content items to Gemini...");
      final response = await _model!.generateContent(conversationHistory);
      print("Math Page - Response received.");
      final assistantResponseText =
          response.text ?? 'El asistente no proporcionó respuesta.';
      final assistantMessage = {
        'role': 'assistant',
        'text': assistantResponseText,
        'timestamp': Timestamp.now(),
      };
      if (mounted) setState(() => _chatHistory.add(assistantMessage));
      if (_chatId != null) _saveMessageToFirestore(assistantMessage);
    } catch (e) {
      print("Math Page - Error generating response: $e");
      final err = {
        'role': 'system',
        'text': 'Error al contactar al asistente: $e',
        'timestamp': Timestamp.now()
      };
      if (mounted) setState(() => _chatHistory.add(err));
      if (_chatId != null) _saveMessageToFirestore(err);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedFile = null;
          _isPreviewExpanded = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt ?? 0;
        if (sdkInt >= 33) {
          if (!await Permission.photos.request().isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Permiso para acceder a imágenes denegado.')),
              );
            }
            return;
          }
        } else {
          if (!await Permission.storage.request().isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Permiso para acceder a imágenes denegado.')),
              );
            }
            return;
          }
        }
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: kIsWeb,
      );

      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;

        if (file.size > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('La imagen excede el límite de 5MB.')),
            );
          }
          return;
        }

        final msg = {
          'role': 'system',
          'text': 'Imagen subida: ${file.name}',
          'timestamp': Timestamp.now()
        };
        setState(() {
          _selectedFile = file;
          _isPreviewExpanded = true;
          _chatHistory.add(msg);
        });
        _scrollToBottom();
        print("Math Page - Image selected: ${_selectedFile?.name}");
      } else {
        print("Math Page - Image selection cancelled.");
      }
    } catch (e) {
      print("Math Page - Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar la imagen: $e')),
        );
      }
    }
  }

  void _removeImage() {
    if (mounted && _selectedFile != null) {
      final msg = {
        'role': 'system',
        'text': 'Imagen eliminada: ${_selectedFile!.name}',
        'timestamp': Timestamp.now()
      };
      setState(() {
        _selectedFile = null;
        _isPreviewExpanded = false;
        _chatHistory.add(msg);
      });
      _scrollToBottom();
      print("Math Page - Selected image removed.");
    }
  }

  Future<void> _clearChat() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar Chat de Matemáticas'),
        content: const Text(
            '¿Estás seguro de que quieres borrar todo el historial de este chat? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Limpiar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    if (mounted) {
      setState(() {
        _chatHistory.clear();
        _selectedFile = null;
        _isPreviewExpanded = false;
        _isLoading = true;
      });
    }

    final welcomeMessage = {
      'role': 'assistant',
      'text': _chatId != null
          ? _initialWelcomeMessageText
          : 'Inicia sesión para guardar y ver tu historial.',
      'timestamp': Timestamp.now(),
    };

    if (_chatId != null) {
      print("Math Page - Clearing Firestore for $_chatId/math_messages...");
      try {
        final ref = _firestore
            .collection('chats')
            .doc(_chatId)
            .collection('math_messages');
        QuerySnapshot snapshot;
        do {
          snapshot = await ref.limit(100).get();
          if (snapshot.docs.isNotEmpty) {
            final batch = _firestore.batch();
            for (var doc in snapshot.docs) {
              batch.delete(doc.reference);
            }
            await batch.commit();
            print("Lote de ${snapshot.docs.length} mensajes borrado.");
          }
        } while (snapshot.docs.isNotEmpty);
        print("Math Page - Firestore history cleared.");

        _saveMessageToFirestore(welcomeMessage);
        if (mounted) setState(() => _chatHistory.add(welcomeMessage));
      } catch (e) {
        print("Math Page - Error clearing Firestore: $e");
        final err = {
          'role': 'system',
          'text': 'Error limpiando historial nube: $e',
          'timestamp': Timestamp.now()
        };
        if (mounted) {
          setState(() {
            _chatHistory.add(err);
            if (_chatHistory.where((m) => m['role'] == 'assistant').isEmpty) {
              _chatHistory.add(welcomeMessage);
            }
          });
        }
      }
    } else {
      if (mounted) setState(() => _chatHistory.add(welcomeMessage));
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  Future<void> _downloadHistory() async {
    final downloadableHistory = _chatHistory.where((msg) {
      final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
      final text = msg['text'] ?? '';
      if (role == 'SYSTEM' &&
          (text.contains('subida:') ||
              text.contains('eliminada:') ||
              text.contains('inicializada') ||
              text.contains('Error:'))) {
        return false;
      }
      if (role == 'ASSISTANT' &&
          (text == _initialWelcomeMessageText ||
              text == 'Inicia sesión para guardar y ver tu historial.'))
        return false;
      return true;
    }).toList();

    if (downloadableHistory.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No hay historial relevante para descargar.')));
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final StringBuffer buffer = StringBuffer();
      buffer.writeln("Historial del Chat de Matemáticas");
      buffer.writeln("=" * 30);
      buffer.writeln(
          "Exportado el: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now().toLocal())}");
      buffer.writeln();
      final DateFormat formatter = DateFormat('yyyy-MM-dd HH:mm:ss');

      for (final message in downloadableHistory) {
        final role = message['role']?.toString().toUpperCase() ?? 'SYSTEM';
        final text = message['text'] ?? '';
        dynamic ts = message['timestamp'];
        String timestampStr = 'N/A';
        try {
          if (ts is Timestamp) {
            timestampStr = formatter.format(ts.toDate().toLocal());
          } else if (ts is DateTime) {
            timestampStr = formatter.format(ts.toLocal());
          }
        } catch (e) {
          print("Error formateando timestamp: $e");
        }
        buffer.writeln("[$timestampStr] $role:");
        buffer.writeln(text);
        if (message['fileName'] != null) {
          buffer.writeln("  [Archivo adjunto: ${message['fileName']}]");
        }
        buffer.writeln("-" * 20);
      }

      final String fileContent = buffer.toString();
      final String fileName =
          'historial_matematicas_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
      final List<int> fileBytes = utf8.encode(fileContent);

      if (kIsWeb) {
        final blob = html.Blob([fileBytes], 'text/plain', 'native');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Descarga iniciada (Web).')));
        }
      } else {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Historial Matemáticas',
          fileName: fileName,
          bytes: Uint8List.fromList(fileBytes),
        );
        if (result == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Guardado cancelado.')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text('Historial guardado en: ${result.split('/').last}')),
            );
          }
        }
      }
    } catch (e) {
      print("Error general al descargar (Math): $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al preparar la descarga: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _chatSubscription?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 720;
        double chatBubbleMaxWidth =
            isWideScreen ? 600 : constraints.maxWidth * 0.8;

        bool canSendMessage = !_isLoading &&
            (_controller.text.trim().isNotEmpty || _selectedFile != null);

        bool hasDownloadableContent = _chatHistory.any((msg) {
          final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
          final text = msg['text'] ?? '';
          if (role == 'SYSTEM' &&
              (text.contains('subida:') ||
                  text.contains('eliminada:') ||
                  text.contains('inicializada') ||
                  text.contains('Error:'))) return false;
          if (role == 'ASSISTANT' &&
              (text == _initialWelcomeMessageText ||
                  text == 'Inicia sesión para guardar y ver tu historial.'))
            return false;
          return true;
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text('Math Expert'),
            centerTitle: true,
            elevation: 1,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () =>
                  Navigator.canPop(context) ? Navigator.pop(context) : null,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_outlined),
                onPressed: (_isLoading || !hasDownloadableContent)
                    ? null
                    : _downloadHistory,
                tooltip: 'Descargar historial',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _isLoading ? null : _clearChat,
                tooltip: 'Limpiar chat',
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(
                        horizontal: isWideScreen ? 24.0 : 16.0, vertical: 16.0),
                    itemCount: _chatHistory.length,
                    itemBuilder: (context, index) {
                      final message = _chatHistory[index];
                      final role = message['role'] as String? ?? 'system';
                      final text = message['text'] as String? ?? '';
                      final fileName = message['fileName'] as String?;
                      final imageBytes = message['imageBytes'] as Uint8List?;
                      final isUser = role == 'user';
                      final isSystem = role == 'system';
                      Color backgroundColor;
                      Color textColor;
                      Alignment alignment;
                      TextAlign textAlign;
                      if (isUser) {
                        backgroundColor = Colors.teal[100]!;
                        textColor = Colors.teal[900]!;
                        alignment = Alignment.centerRight;
                        textAlign = TextAlign.left;
                      } else if (isSystem) {
                        backgroundColor = Colors.orange[100]!;
                        textColor = Colors.orange[900]!;
                        alignment = Alignment.center;
                        textAlign = TextAlign.center;
                      } else {
                        backgroundColor = Colors.grey[200]!;
                        textColor = Colors.black87;
                        alignment = Alignment.centerLeft;
                        textAlign = TextAlign.left;
                      }
                      if (isSystem &&
                          (text.contains('subida:') ||
                              text.contains('eliminada:'))) {
                        return const SizedBox.shrink();
                      }
                      return Align(
                        alignment: alignment,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5.0),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14.0, vertical: 10.0),
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            borderRadius: BorderRadius.circular(16.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                spreadRadius: 1,
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          constraints:
                              BoxConstraints(maxWidth: chatBubbleMaxWidth),
                          child: Column(
                            crossAxisAlignment: isSystem
                                ? CrossAxisAlignment.center
                                : CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isUser &&
                                  fileName != null &&
                                  imageBytes != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.image_outlined,
                                              size: 16,
                                              color:
                                                  textColor.withOpacity(0.8)),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              fileName,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontStyle: FontStyle.italic,
                                                  color: textColor
                                                      .withOpacity(0.8)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(
                                          imageBytes,
                                          fit: BoxFit.contain,
                                          height: 100,
                                          errorBuilder: (c, e, s) => const Text(
                                              'Error al mostrar imagen'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (text.isNotEmpty)
                                (role == 'assistant')
                                    ? MarkdownBody(
                                        data: text,
                                        selectable: true,
                                        styleSheet:
                                            MarkdownStyleSheet.fromTheme(
                                                    Theme.of(context))
                                                .copyWith(
                                          p: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                  color: textColor,
                                                  height: 1.4),
                                          code: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                  fontFamily: 'monospace',
                                                  backgroundColor:
                                                      Colors.black12,
                                                  color: textColor),
                                        ),
                                      )
                                    : SelectableText(
                                        text,
                                        textAlign: textAlign,
                                        style: TextStyle(
                                          color: textColor,
                                          fontStyle: isSystem
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                          fontSize: isSystem ? 13 : 16,
                                          height: 1.4,
                                        ),
                                      ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_selectedFile != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(isWideScreen ? 24.0 : 8.0, 0,
                        isWideScreen ? 24.0 : 8.0, 8.0),
                    child: Card(
                      elevation: 2,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.image_outlined,
                                    color: Colors.teal, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(_selectedFile!.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13))),
                                TextButton(
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(60, 30),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      alignment: Alignment.centerRight),
                                  onPressed: () {
                                    if (mounted) {
                                      setState(() => _isPreviewExpanded =
                                          !_isPreviewExpanded);
                                    }
                                  },
                                  child: Text(
                                      _isPreviewExpanded
                                          ? 'Ocultar'
                                          : 'Mostrar',
                                      style: const TextStyle(
                                          color: Colors.teal, fontSize: 13)),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(60, 30),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      alignment: Alignment.centerRight),
                                  onPressed: _isLoading ? null : _removeImage,
                                  child: const Text('Eliminar',
                                      style: TextStyle(
                                          color: Colors.red, fontSize: 13)),
                                ),
                              ],
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: _isPreviewExpanded
                                  ? ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxHeight: isWideScreen ? 250 : 150),
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(top: 8.0),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: kIsWeb
                                              ? Image.memory(
                                                  _selectedFile!.bytes!,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (c, e, s) =>
                                                      const Text(
                                                          'Error al mostrar imagen web'),
                                                )
                                              : (_selectedFile!.path != null)
                                                  ? Image.file(
                                                      File(
                                                          _selectedFile!.path!),
                                                      fit: BoxFit.contain,
                                                      errorBuilder: (c, e, s) =>
                                                          const Text(
                                                              'Error al mostrar imagen móvil'),
                                                    )
                                                  : const Center(
                                                      child: Text(
                                                          'Vista previa no disponible (móvil)')),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Container(
                  padding: EdgeInsets.fromLTRB(isWideScreen ? 24.0 : 8.0, 8.0,
                      isWideScreen ? 24.0 : 8.0, 16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(
                        top: BorderSide(
                            color: Colors.grey.shade300, width: 0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        padding: const EdgeInsets.only(bottom: 8, right: 4),
                        icon: const Icon(Icons.add_photo_alternate_outlined,
                            size: 28),
                        color: Colors.teal,
                        tooltip: 'Seleccionar Imagen',
                        onPressed: _isLoading ? null : _pickImage,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: 'Escribe tu pregunta aquí...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25.0),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25.0),
                              borderSide: BorderSide(
                                  color: Colors.teal.shade200, width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            isDense: true,
                          ),
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (value) {
                            if (!_isLoading &&
                                (_controller.text.trim().isNotEmpty ||
                                    _selectedFile != null)) {
                              _generateResponse(_controller.text.trim());
                            }
                          },
                          keyboardType: TextInputType.multiline,
                          enabled: !_isLoading,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        padding: const EdgeInsets.only(bottom: 8, left: 4),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send, size: 28),
                        tooltip: 'Enviar Mensaje',
                        color: canSendMessage ? Colors.teal : Colors.grey,
                        onPressed: canSendMessage
                            ? () => _generateResponse(_controller.text.trim())
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
