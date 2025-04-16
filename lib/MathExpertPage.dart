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

class _MathExpertPageState extends State<MathExpertPage> with WidgetsBindingObserver {
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
  Map<String, dynamic>? _pendingUserMessage;
  bool _initialScrollExecuted = false;
  int _previousMessageCount = 0;
  final _textFieldValue = ValueNotifier<String>(''); // Para el ValueListenableBuilder

  static const String _initialWelcomeMessageText =
      '¡Bienvenido! Soy tu experto en matemáticas. Pregúntame cualquier cosa sobre matemáticas o sube una imagen de un problema.';
  static const String _loginPromptMessageText =
      'Inicia sesión para guardar y ver tu historial.';
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
    _initializeModel();
    _textFieldValue.value = _controller.text;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {
          print("Math Page - App resumed, forcing UI redraw.");
        });
      }
    }
  }

  void _setChatIdBasedOnUser() {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      _chatId = currentUser.uid;
      print("Math Page - Authenticated User: ${currentUser.email}, Chat ID: $_chatId");
    } else {
      _chatId = null;
      print("Math Page - No authenticated user.");
    }
  }

  void _initializeModel() async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: No se encontró la clave API en .env')),
        );
      }
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
    } catch (e) {
      print("Math Page - Error initializing model: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al inicializar el asistente: $e')),
        );
      }
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _getChatStream() {
    if (_chatId == null) return null;
    return _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('math_messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Future<void> _saveMessageToFirestore(Map<String, dynamic> message) async {
    if (_chatId == null) return;
    if (message['role'] == 'system' &&
        (message['text'].contains('subida:') || message['text'].contains('eliminada'))) {
      print("Math Page - Local UI message not saved: ${message['text']}");
      return;
    }
    try {
      final messageToSave = Map<String, dynamic>.from(message);
      messageToSave.remove('id');
      messageToSave.remove('isExpanded');
      messageToSave.remove('imageBytes');
      messageToSave['timestamp'] = FieldValue.serverTimestamp();
      print("Math Page - Saving message to Firestore: ${messageToSave['role']}");
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Modelo no inicializado.')),
        );
      }
      return;
    }
    if (userPrompt.trim().isEmpty && _selectedFile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, ingresa una pregunta o selecciona una imagen.')),
        );
      }
      _scrollToBottom(jump: false);
      return;
    }

    setState(() => _isLoading = true);

    Map<String, dynamic> userMessageForHistory = {
      'role': 'user',
      'text': userPrompt.trim(),
      'timestamp': DateTime.now(),
    };
    List<Part> currentParts = []; // Partes para el mensaje actual

    Uint8List? imageBytesForHistory;
    String? mimeTypeForHistory;

    // Procesar la imagen si existe
    if (_selectedFile != null) {
      userMessageForHistory['fileName'] = _selectedFile!.name;
      try {
        Uint8List imageBytes;
        if (kIsWeb) {
          if (_selectedFile!.bytes == null) throw Exception("Bytes de imagen no disponibles en web.");
          imageBytes = _selectedFile!.bytes!;
        } else {
          if (_selectedFile!.path == null) throw Exception("Ruta de imagen no disponible en móvil.");
          imageBytes = await File(_selectedFile!.path!).readAsBytes();
        }
        if (imageBytes.isEmpty) throw Exception("El archivo de imagen está vacío o corrupto.");

        String mimeType = 'image/jpeg';
        final extension = _selectedFile!.extension?.toLowerCase();
        if (extension == 'png') mimeType = 'image/png';
        else if (extension == 'webp') mimeType = 'image/webp';
        else if (extension == 'gif') mimeType = 'image/gif';
        else if (extension == 'heic') {
          mimeType = 'image/heic';
          print("Math Page - Warning: HEIC format may not be fully supported by Gemini.");
        }

        currentParts.add(DataPart(mimeType, imageBytes));
        imageBytesForHistory = imageBytes;
        mimeTypeForHistory = mimeType;
        print("Math Page - Image prepared: ${_selectedFile!.name}, MIME: $mimeType, Bytes: ${imageBytes.length}");
      } catch (e) {
        print("Math Page - Error procesando imagen: $e");
        final err = {
          'role': 'system',
          'text': 'Error procesando imagen: $e',
          'timestamp': DateTime.now(),
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
        _scrollToBottom(jump: false);
        return;
      }
    }

    // Añadir texto si existe
    if (userPrompt.trim().isNotEmpty) {
      currentParts.add(TextPart(userPrompt.trim()));
    }

    // Guardar imagen en el historial si existe
    if (imageBytesForHistory != null) {
      userMessageForHistory['imageBytes'] = imageBytesForHistory;
      userMessageForHistory['mimeType'] = mimeTypeForHistory;
    }

    // Actualizar historial local
    setState(() {
      _chatHistory.add(userMessageForHistory);
      _pendingUserMessage = null;
      _controller.clear();
      _textFieldValue.value = '';
    });
    _scrollToBottom(jump: false);

    // Guardar mensaje en Firestore
    if (_chatId != null) {
      final messageToSave = Map<String, dynamic>.from(userMessageForHistory);
      messageToSave.remove('imageBytes');
      messageToSave.remove('mimeType');
      await _saveMessageToFirestore(messageToSave);
    }

    if (currentParts.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Construir historial previo (sin el mensaje actual)
      List<Content> conversationHistoryForGemini = _chatHistory
          .where((msg) => msg['role'] == 'user' || msg['role'] == 'assistant')
          .take(_chatHistory.length - 1) // Excluir el mensaje actual
          .map((msg) {
        List<Part> parts = [];
        if (msg['text'] != null && (msg['text'] as String).trim().isNotEmpty) {
          parts.add(TextPart(msg['text']));
        }
        if (msg['role'] == 'user' && msg['imageBytes'] != null && msg['mimeType'] != null) {
          parts.add(DataPart(msg['mimeType'], msg['imageBytes']));
        }
        final role = msg['role'] == 'assistant' ? 'model' : 'user';
        return Content(role, parts.isNotEmpty ? parts : [TextPart('')]);
      }).toList();

      // Añadir el mensaje actual explícitamente
      conversationHistoryForGemini.add(Content('user', currentParts));

      print("Math Page - Sending content to Gemini: ${conversationHistoryForGemini.length} items, Current parts: ${currentParts.length}");
      final response = await _model!.generateContent(conversationHistoryForGemini);

      print("Math Page - Response received: ${response.text}");
      final assistantMessage = {
        'role': 'assistant',
        'text': response.text ?? 'El asistente no proporcionó respuesta.',
        'timestamp': DateTime.now(),
      };

      setState(() {
        _chatHistory.add(assistantMessage);
      });
      _scrollToBottom(jump: false);

      if (_chatId != null) await _saveMessageToFirestore(assistantMessage);
    } catch (e) {
      print("Math Page - Error generating response: $e");
      String errorMessage = 'Error al contactar al asistente: $e';
      if (e.toString().contains('image')) {
        errorMessage = 'Error: La imagen no pudo ser procesada por el asistente. Intenta con otro formato (JPEG, PNG).';
      }
      final err = {
        'role': 'system',
        'text': errorMessage,
        'timestamp': DateTime.now(),
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
        _scrollToBottom(jump: false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      bool permissionGranted = false;
      if (!kIsWeb && Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        print("Android SDK: $sdkInt");
        if (sdkInt >= 33) {
          permissionGranted = await Permission.photos.request().isGranted;
          print("Photos Permission Granted (SDK >= 33): $permissionGranted");
        } else {
          permissionGranted = await Permission.storage.request().isGranted;
          print("Storage Permission Granted (SDK < 33): $permissionGranted");
        }
      } else {
        permissionGranted = true; // Web no necesita permisos explícitos
      }

      if (!permissionGranted) {
        print("Permiso denegado por el usuario.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso para acceder a imágenes denegado.')),
          );
        }
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true, // Asegurar que los bytes estén disponibles en todas las plataformas
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        // Verificar tamaño
        if (file.size > 5 * 1024 * 1024) { // Límite de 5MB
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('La imagen excede el límite de 5MB.')),
            );
          }
          return;
        }

        // Validar que los bytes estén disponibles
        Uint8List? imageBytes = file.bytes;
        if (!kIsWeb && file.path != null && (imageBytes == null || imageBytes.isEmpty)) {
          imageBytes = await File(file.path!).readAsBytes();
        }

        if (imageBytes == null || imageBytes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: No se pudieron leer los datos de la imagen.')),
            );
          }
          print("Math Page - Error: Image bytes are null or empty.");
          return;
        }

        if (mounted) {
          setState(() {
            _selectedFile = file;
            _isPreviewExpanded = true;
            _chatHistory.add({
              'role': 'system',
              'text': 'Imagen subida: ${file.name}',
              'timestamp': DateTime.now(),
            });
          });
          _scrollToBottom(jump: false);
          print("Math Page - Image selected: ${file.name}, Bytes: ${imageBytes.length}");
        }
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
      setState(() {
        _chatHistory.add({
          'role': 'system',
          'text': 'Imagen eliminada: ${_selectedFile!.name}',
          'timestamp': DateTime.now(),
        });
        _selectedFile = null;
        _isPreviewExpanded = false;
      });
      _scrollToBottom(jump: false);
      print("Math Page - Selected image removed.");
    }
  }

  Future<void> _clearChat() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar Chat de Matemáticas'),
        content: const Text('¿Estás seguro de que quieres borrar todo el historial de este chat? Esta acción no se puede deshacer.'),
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

    if (mounted) setState(() => _isLoading = true);

    final welcomeMessage = {
      'role': 'assistant',
      'text': _chatId != null ? _initialWelcomeMessageText : _loginPromptMessageText,
      'timestamp': DateTime.now(),
    };

    if (_chatId != null) {
      print("Math Page - Clearing Firestore for $_chatId/math_messages...");
      try {
        final ref = _firestore.collection('chats').doc(_chatId).collection('math_messages');
        QuerySnapshot snapshot;
        int deletedCount = 0;
        do {
          snapshot = await ref.limit(100).get();
          if (snapshot.docs.isNotEmpty) {
            final batch = _firestore.batch();
            for (var doc in snapshot.docs) {
              batch.delete(doc.reference);
            }
            await batch.commit();
            deletedCount += snapshot.docs.length;
            print("Lote de ${snapshot.docs.length} mensajes borrado (total: $deletedCount).");
          }
        } while (snapshot.docs.isNotEmpty);

        print("Math Page - Firestore history cleared.");
        await _saveMessageToFirestore(welcomeMessage);

        if (mounted) {
          setState(() {
            _chatHistory = [welcomeMessage];
            _isLoading = false;
            _initialScrollExecuted = false;
          });
        }
        _scrollToBottom(jump: true);
      } catch (e) {
        print("Math Page - Error clearing Firestore: $e");
        final err = {
          'role': 'system',
          'text': 'Error limpiando historial nube: $e',
          'timestamp': DateTime.now(),
        };
        if (mounted) {
          setState(() {
            _chatHistory = [err, welcomeMessage];
            _isLoading = false;
          });
        }
        _scrollToBottom(jump: true);
      }
    } else {
      if (mounted) {
        setState(() {
          _chatHistory = [welcomeMessage];
          _isLoading = false;
        });
      }
      _scrollToBottom(jump: true);
    }
  }

  Future<void> _downloadHistory() async {
    final downloadableHistory = _chatHistory.where((msg) {
      final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
      final text = msg['text'] ?? '';
      if (role == 'SYSTEM' && (text.contains('subida:') || text.contains('eliminada:') || text.contains('Error:'))) {
        return false;
      }
      if (role == 'ASSISTANT' && (text == _initialWelcomeMessageText || text == _loginPromptMessageText)) {
        return false;
      }
      return true;
    }).toList();

    final hasUserMessages = _chatHistory.any((msg) =>
    msg['role'] == 'user' &&
        (msg['text']?.toString().trim().isNotEmpty == true || msg['fileName'] != null));

    if (!kIsWeb && Platform.isAndroid && !hasUserMessages) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay preguntas enviadas para descargar.')),
        );
      }
      return;
    }

    if (downloadableHistory.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay historial relevante para descargar.')),
        );
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final StringBuffer buffer = StringBuffer();
      buffer.writeln("Historial del Chat de Matemáticas");
      buffer.writeln("=" * 30);
      buffer.writeln("Exportado el: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now().toLocal())}");
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
          } else {
            timestampStr = formatter.format(DateTime.now().toLocal());
          }
        } catch (e) {
          print("Error formateando timestamp para descarga: $e");
          timestampStr = formatter.format(DateTime.now().toLocal());
        }

        buffer.writeln("[$timestampStr] $role:");
        buffer.writeln(text);
        if (message['fileName'] != null) {
          buffer.writeln("  [Archivo adjunto: ${message['fileName']}]");
        }
        buffer.writeln("-" * 20);
      }

      final String fileContent = buffer.toString();
      final String fileName = 'historial_matematicas_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
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
            const SnackBar(content: Text('Descarga iniciada (Web).')),
          );
        }
      } else {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Historial Matemáticas',
          fileName: fileName,
          bytes: Uint8List.fromList(fileBytes),
        );

        if (outputFile == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Guardado cancelado.')),
            );
          }
        } else {
          if (mounted) {
            final savedFileName = outputFile.split(Platform.pathSeparator).last;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Historial guardado como: $savedFileName')),
            );
          }
        }
      }
    } catch (e) {
      print("Error general al descargar (Math): $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al preparar la descarga: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _textFieldValue.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scrollToBottom({required bool jump}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        if (jump) {
          _scrollController.jumpTo(maxExtent);
        } else {
          _scrollController.animateTo(
            maxExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } else {
        Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom(jump: jump));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 720;
        double chatBubbleMaxWidth = isWideScreen ? 600 : constraints.maxWidth * 0.85;
        bool hasDownloadableContent = !_isLoading && _chatHistory.any((msg) {
          final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
          final text = msg['text'] ?? '';
          if (role == 'SYSTEM' && (text.contains('subida:') || text.contains('eliminada:') || text.contains('Error:'))) return false;
          if (role == 'ASSISTANT' && (text == _initialWelcomeMessageText || text == _loginPromptMessageText)) return false;
          return true;
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text('Math Expert'),
            centerTitle: true,
            elevation: 1,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.canPop(context) ? Navigator.pop(context) : null,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_outlined),
                onPressed: hasDownloadableContent ? _downloadHistory : null,
                tooltip: 'Descargar historial',
                color: hasDownloadableContent ? null : Colors.grey,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _isLoading ? null : _clearChat,
                tooltip: 'Limpiar chat',
                color: _isLoading ? Colors.grey : null,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _getChatStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting && _chatId != null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        print("Math Page - StreamBuilder Error: ${snapshot.error}");
                        return Center(child: Text('Error al cargar mensajes: ${snapshot.error}'));
                      }
                      if (_chatId == null) {
                        if (_chatHistory.isEmpty) {
                          _chatHistory.add({
                            'role': 'assistant',
                            'text': _loginPromptMessageText,
                            'timestamp': DateTime.now(),
                          });
                        }
                      }

                      final List<Map<String, dynamic>> messagesFromStream;
                      if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                        messagesFromStream = snapshot.data!.docs.map((doc) {
                          final data = doc.data();
                          data['id'] = doc.id;
                          if (data['timestamp'] is Timestamp) {
                            data['timestamp'] = (data['timestamp'] as Timestamp).toDate();
                          } else if (data['timestamp'] is! DateTime) {
                            data['timestamp'] = DateTime.now();
                          }
                          return data;
                        }).toList();
                        _chatHistory = messagesFromStream;
                      } else {
                        messagesFromStream = [];
                        if (_chatHistory.isEmpty && _chatId != null) {
                          _chatHistory.add({
                            'role': 'assistant',
                            'text': _initialWelcomeMessageText,
                            'timestamp': DateTime.now(),
                          });
                        }
                      }

                      final allMessages = [..._chatHistory];
                      if (_pendingUserMessage != null) {
                        allMessages.add(_pendingUserMessage!);
                        allMessages.sort((a, b) {
                          DateTime aTime = a['timestamp'] is Timestamp ? (a['timestamp'] as Timestamp).toDate() : a['timestamp'] as DateTime;
                          DateTime bTime = b['timestamp'] is Timestamp ? (b['timestamp'] as Timestamp).toDate() : b['timestamp'] as DateTime;
                          return aTime.compareTo(bTime);
                        });
                      }

                      final currentMessageCount = allMessages.length;
                      if (currentMessageCount > 0 && !_initialScrollExecuted) {
                        print("Math Page - Initial load ($currentMessageCount messages).");
                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: true));
                        _initialScrollExecuted = true;
                      } else if (currentMessageCount > _previousMessageCount && _initialScrollExecuted) {
                        print("Math Page - New message ($currentMessageCount > $_previousMessageCount).");
                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: false));
                      }
                      _previousMessageCount = currentMessageCount;

                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: ListView.builder(
                          key: ValueKey(allMessages.length),
                          controller: _scrollController,
                          padding: EdgeInsets.symmetric(horizontal: isWideScreen ? 24.0 : 16.0, vertical: 16.0),
                          itemCount: allMessages.length,
                          itemBuilder: (context, index) {
                            final message = allMessages[index];
                            final role = message['role'] as String? ?? 'system';
                            final text = message['text'] as String? ?? '';
                            final fileName = message['fileName'] as String?;
                            final imageBytes = message['imageBytes'] as Uint8List?;
                            final isUser = role == 'user';
                            final isSystem = role == 'system';

                            final key = ValueKey(message['id'] ?? message['timestamp'].toString());

                            Color backgroundColor;
                            Color textColor;
                            Alignment alignment;
                            TextAlign textAlign;
                            CrossAxisAlignment crossAxisAlignment;

                            if (isUser) {
                              backgroundColor = Colors.teal[100]!;
                              textColor = Colors.teal[900]!;
                              alignment = Alignment.centerRight;
                              textAlign = TextAlign.left;
                              crossAxisAlignment = CrossAxisAlignment.start;
                            } else if (isSystem) {
                              backgroundColor = Colors.orange[100]!;
                              textColor = Colors.orange[900]!;
                              alignment = Alignment.center;
                              textAlign = TextAlign.center;
                              crossAxisAlignment = CrossAxisAlignment.center;
                            } else {
                              backgroundColor = Colors.grey[200]!;
                              textColor = Colors.black87;
                              alignment = Alignment.centerLeft;
                              textAlign = TextAlign.left;
                              crossAxisAlignment = CrossAxisAlignment.start;
                            }

                            if (isSystem && (text.contains('subida:') || text.contains('eliminada:'))) {
                              return const SizedBox.shrink();
                            }

                            return Align(
                              key: key,
                              alignment: alignment,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 5.0),
                                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
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
                                constraints: BoxConstraints(maxWidth: chatBubbleMaxWidth),
                                child: Column(
                                  crossAxisAlignment: crossAxisAlignment,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isUser && fileName != null && imageBytes != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.image_outlined, size: 16, color: textColor.withOpacity(0.8)),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    fileName,
                                                    style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: textColor.withOpacity(0.8)),
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
                                                errorBuilder: (c, e, s) => const Text('Error al mostrar imagen'),
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
                                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                          p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor, height: 1.4),
                                          code: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', backgroundColor: Colors.black12, color: textColor),
                                        ),
                                      )
                                          : SelectableText(
                                        text,
                                        textAlign: textAlign,
                                        style: TextStyle(
                                          color: textColor,
                                          fontStyle: isSystem ? FontStyle.italic : FontStyle.normal,
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
                      );
                    },
                  ),
                ),
                if (_selectedFile != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(isWideScreen ? 24.0 : 8.0, 0, isWideScreen ? 24.0 : 8.0, 8.0),
                    child: Card(
                      elevation: 2,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.image_outlined, color: Colors.teal, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_selectedFile!.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                                TextButton(
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: () => setState(() => _isPreviewExpanded = !_isPreviewExpanded),
                                  child: Text(_isPreviewExpanded ? 'Ocultar' : 'Mostrar', style: const TextStyle(color: Colors.teal, fontSize: 13)),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: _isLoading ? null : _removeImage,
                                  child: Text('Eliminar', style: TextStyle(color: _isLoading ? Colors.grey : Colors.red, fontSize: 13)),
                                ),
                              ],
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: _isPreviewExpanded
                                  ? ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: isWideScreen ? 250 : 150),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: kIsWeb
                                        ? (_selectedFile?.bytes != null
                                        ? Image.memory(_selectedFile!.bytes!, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Center(child: Text('Error al mostrar imagen (Web)')))
                                        : const Center(child: Text('Vista previa no disponible (Web)')))
                                        : (_selectedFile?.path != null
                                        ? Image.file(File(_selectedFile!.path!), fit: BoxFit.contain, errorBuilder: (c, e, s) => const Center(child: Text('Error al mostrar imagen (Móvil)')))
                                        : const Center(child: Text('Vista previa no disponible (Móvil)'))),
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
                  padding: EdgeInsets.fromLTRB(isWideScreen ? 24.0 : 8.0, 8.0, isWideScreen ? 24.0 : 8.0, 16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                  ),
                  child: ValueListenableBuilder<String>(
                    valueListenable: _textFieldValue,
                    builder: (context, textValue, child) {
                      bool canSendMessage = !_isLoading && (textValue.trim().isNotEmpty || _selectedFile != null);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            padding: const EdgeInsets.only(bottom: 8, right: 4),
                            icon: const Icon(Icons.add_photo_alternate_outlined, size: 28),
                            color: _isLoading ? Colors.grey : Colors.teal,
                            tooltip: 'Seleccionar Imagen',
                            onPressed: _isLoading ? null : _pickImage,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: InputDecoration(
                                hintText: 'Escribe tu pregunta aquí...',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide(color: Colors.teal.shade200, width: 1.5)),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                isDense: true,
                              ),
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (value) {
                                if (canSendMessage) _generateResponse(value.trim());
                              },
                              onChanged: (value) {
                                _textFieldValue.value = value;
                                _scrollToBottom(jump: false);
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
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send, size: 28),
                            tooltip: 'Enviar Mensaje',
                            color: canSendMessage ? Colors.teal : Colors.grey,
                            onPressed: canSendMessage ? () => _generateResponse(_controller.text.trim()) : null,
                          ),
                        ],
                      );
                    },
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