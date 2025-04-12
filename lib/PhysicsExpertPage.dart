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

class PhysicsExpertPage extends StatefulWidget {
  const PhysicsExpertPage({super.key});

  @override
  State<PhysicsExpertPage> createState() => _PhysicsExpertPageState();
}

class _PhysicsExpertPageState extends State<PhysicsExpertPage> {
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
      '¡Bienvenido! Soy tu experto en física. Pregúntame cualquier cosa sobre física o sube una imagen de un problema.';
  static const String _systemPrompt = """
Eres un experto en física con un conocimiento profundo en mecánica, termodinámica, electromagnetismo, óptica, física moderna y otras ramas. Tu función principal es responder preguntas relacionadas con física y analizar imágenes que contengan problemas, diagramas o situaciones físicas.

**Entrada del Usuario:**

El usuario puede proporcionar:

1. Una pregunta de texto sobre física (por ejemplo, "¿Cuál es la velocidad final de un objeto en caída libre tras 5 segundos?").
2. Una imagen que contenga un problema de física, un diagrama o una situación física.
3. Ambas cosas: una imagen Y una pregunta de texto relacionada.

**Instrucciones:**

* **Prioridad de la Imagen:** Si el usuario sube una imagen, analiza la imagen **CUIDADOSAMENTE**. Tu respuesta **DEBE** basarse principalmente en el contenido de la imagen. Si hay texto adicional, úsalo como **CONTEXTO**, pero la imagen tiene prioridad.
* **Imagen Ilegible:** Si la imagen es ilegible, borrosa o no contiene información física clara, indica esto en tu respuesta.
* **Análisis de Física (Texto o Imagen):**
    * Identifica el concepto físico relevante (por ejemplo, cinemática, dinámica, energía).
    * Si es un problema, resuélvelo paso a paso, mostrando todas las fórmulas y cálculos.
    * Proporciona explicaciones claras y detalladas de cada paso.
    * Si faltan datos, indícalos y explica qué se necesita para resolverlo.
* **Explicaciones Paso a Paso (Obligatorio):** Para problemas numéricos o conceptuales, descompón la solución en pasos numerados, mostrando fórmulas, sustituciones y resultados.
* **RESTRICCIÓN ABSOLUTA:** No respondas a preguntas fuera de física. Responde **ESTRICTAMENTE** con: "No puedo responder a esa pregunta, ya que está fuera de mi especialización en física."

**Formato de Respuesta (Markdown):**

* Usa notación matemática estándar (por ejemplo, v = u + at, F = ma, E = mc²).
* Resalta conceptos clave, fórmulas y resultados en **negritas**.
* Usa títulos y subtítulos en negritas (ej., **Concepto**, **Cálculo**, **Resultado**).
* Descompón los cálculos en pasos numerados.
""";

  @override
  void initState() {
    super.initState();
    print("Physics Page - Auth State Init: ${_auth.currentUser?.uid}");
    _setChatIdBasedOnUser();
    print("Physics Page - Initial Chat ID: $_chatId");
    _initializeModelAndLoadHistory();
    _controller.addListener(() => setState(() {}));
  }

  void _setChatIdBasedOnUser() {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      _chatId = currentUser.uid;
      print("Physics Page - Authenticated User: ${currentUser.email}, Chat ID: $_chatId");
    } else {
      _chatId = null;
      print("Physics Page - No authenticated user.");
    }
  }

  void _initializeModelAndLoadHistory() async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      _addErrorMessageLocally('Error: No se encontró la clave API en .env');
      return;
    }
    try {
      _model = GenerativeModel(
        model: 'gemini-2.5-pro-exp-03-25',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.6,
          topK: 64,
          topP: 0.95,
          maxOutputTokens: 8192,
        ),
        systemInstruction: Content.text(_systemPrompt),
      );
      print("Physics Page - Gemini model initialized.");
      if (_chatId != null) {
        _listenToChatHistory();
      } else {
        _addInitialMessage();
      }
    } catch (e) {
      print("Physics Page - Error initializing model: $e");
      _addErrorMessageLocally('Error al inicializar el asistente: $e');
    }
  }

  void _listenToChatHistory() {
    if (_chatId == null) return;
    print("Physics Page - Starting real-time listener for $_chatId/physics_messages");

    _chatSubscription?.cancel();

    _chatSubscription = _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('physics_messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final List<Map<String, dynamic>> newHistory = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        if (data['timestamp'] == null || data['timestamp'] is! Timestamp) {
          data['timestamp'] = Timestamp.now();
          print("Warning: Invalid timestamp in doc ${doc.id}, using now()");
        }
        return data;
      }).where((msg) => msg['text'] != 'init').toList();

      if (newHistory.isEmpty && !_isLoading) {
        final initialMessage = {
          'role': 'assistant',
          'text': _initialWelcomeMessageText,
          'timestamp': Timestamp.now(),
        };
        if (_chatHistory.isEmpty || _chatHistory.first['text'] != _initialWelcomeMessageText) {
          _saveMessageToFirestore(initialMessage);
        }
      } else {
        setState(() {
          _chatHistory = newHistory;
        });
      }

      print("Physics Page - Real-time update: ${_chatHistory.length} messages.");
      _scrollToBottom();
    }, onError: (e) {
      print("Physics Page - Error listening to history: $e");
      _addErrorMessageLocally('Error al escuchar el historial: $e');
    });
  }

  void _addInitialMessage() {
    final initialMessage = {
      'role': 'assistant',
      'text': _chatId != null
          ? _initialWelcomeMessageText
          : 'Inicia sesión para guardar y ver tu historial.',
      'timestamp': Timestamp.now()
    };
    if (mounted) setState(() => _chatHistory.add(initialMessage));
    if (_chatId != null && initialMessage['text'] == _initialWelcomeMessageText) {
      _saveMessageToFirestore(initialMessage);
    }
    _scrollToBottom();
  }

  void _addErrorMessageLocally(String text) {
    final err = {'role': 'system', 'text': text, 'timestamp': Timestamp.now()};
    if (mounted) setState(() => _chatHistory.add(err));
    _scrollToBottom();
  }

  Future<void> _saveMessageToFirestore(Map<String, dynamic> message) async {
    if (_chatId == null) return;
    if (message['role'] == 'system' &&
        (message['text'].contains('subida:') || message['text'].contains('eliminada'))) {
      print("Physics Page - Local UI message not saved: ${message['text']}");
      return;
    }
    try {
      final messageToSave = Map<String, dynamic>.from(message)
        ..remove('id')
        ..remove('imageBytes')
        ..remove('mimeType')
        ..['timestamp'] = FieldValue.serverTimestamp();
      print("Physics Page - Saving message to Firestore: ${messageToSave['role']}");
      await _firestore
          .collection('chats')
          .doc(_chatId)
          .collection('physics_messages')
          .add(messageToSave);
    } catch (e) {
      print('Physics Page - Error saving message: $e');
    }
  }

  Future<void> _generateResponse(String userPrompt) async {
    if (_model == null) {
      _addErrorMessageLocally('Error: Modelo no inicializado.');
      return;
    }
    if (userPrompt.trim().isEmpty && _selectedFile == null) {
      _addErrorMessageLocally('Por favor, ingresa una pregunta o selecciona una imagen.');
      return;
    }
    setState(() => _isLoading = true);

    Map<String, dynamic> userMessage = {
      'role': 'user',
      'text': userPrompt.trim(),
      'timestamp': Timestamp.now(),
    };
    List<Part> partsForGemini = [];

    if (_selectedFile != null) {
      userMessage['fileName'] = _selectedFile!.name;
      try {
        Uint8List imageBytes = kIsWeb
            ? _selectedFile!.bytes!
            : await File(_selectedFile!.path!).readAsBytes();
        if (imageBytes.isEmpty) throw Exception("El archivo de imagen está vacío o corrupto.");
        String mimeType = 'image/jpeg';
        final extension = _selectedFile!.extension?.toLowerCase();
        if (extension == 'png') mimeType = 'image/png';
        else if (extension == 'webp') mimeType = 'image/webp';
        else if (extension == 'gif') mimeType = 'image/gif';
        else if (extension == 'heic') mimeType = 'image/heic';
        partsForGemini.add(DataPart(mimeType, imageBytes));
        userMessage['imageBytes'] = imageBytes;
        userMessage['mimeType'] = mimeType;
      } catch (e) {
        print("Physics Page - Error procesando imagen: $e");
        _addErrorMessageLocally('Error procesando imagen: $e');
        setState(() {
          _isLoading = false;
          _selectedFile = null;
          _isPreviewExpanded = false;
        });
        return;
      }
    }

    if (userPrompt.trim().isNotEmpty) partsForGemini.add(TextPart(userPrompt.trim()));

    setState(() {
      _chatHistory.add(userMessage);
      _controller.clear();
    });
    _scrollToBottom();
    if (_chatId != null) _saveMessageToFirestore(userMessage);

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

      print("Physics Page - Sending ${conversationHistory.length} content items to Gemini...");
      final response = await _model!.generateContent(conversationHistory);
      print("Physics Page - Response received.");
      final assistantMessage = {
        'role': 'assistant',
        'text': response.text ?? 'No se recibió respuesta.',
        'timestamp': Timestamp.now(),
      };
      if (mounted) setState(() => _chatHistory.add(assistantMessage));
      if (_chatId != null) _saveMessageToFirestore(assistantMessage);
    } catch (e) {
      print("Physics Page - Error generating response: $e");
      _addErrorMessageLocally('Error al generar respuesta: $e');
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
                const SnackBar(content: Text('Permiso para acceder a imágenes denegado.')),
              );
            }
            return;
          }
        } else {
          if (!await Permission.storage.request().isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Permiso para acceder a imágenes denegado.')),
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
              const SnackBar(content: Text('La imagen excede el límite de 5MB.')),
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
        print("Physics Page - Image selected: ${_selectedFile?.name}");
      } else {
        print("Physics Page - Image selection cancelled.");
      }
    } catch (e) {
      print("Physics Page - Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar la imagen: $e')),
        );
      }
    }
  }

  void _removeImage() {
    if (_selectedFile != null) {
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
      print("Physics Page - Selected image removed.");
    }
  }

  Future<void> _clearChat() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar Chat de Física'),
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
      print("Physics Page - Clearing Firestore for $_chatId/physics_messages...");
      try {
        final ref = _firestore.collection('chats').doc(_chatId).collection('physics_messages');
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
        print("Physics Page - Firestore history cleared.");

        await _saveMessageToFirestore(welcomeMessage);

        if (mounted) {
          setState(() {
            _chatHistory = [welcomeMessage];
            _isLoading = false;
          });
        }
        _scrollToBottom();
      } catch (e) {
        print("Physics Page - Error clearing Firestore: $e");
        final err = {
          'role': 'system',
          'text': 'Error limpiando historial nube: $e',
          'timestamp': Timestamp.now()
        };
        if (mounted) {
          setState(() {
            _chatHistory = [err, welcomeMessage];
            _isLoading = false;
          });
        }
        _scrollToBottom();
      }
    } else {
      if (mounted) {
        setState(() {
          _chatHistory = [welcomeMessage];
          _isLoading = false;
        });
      }
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
              text == 'Inicia sesión para guardar y ver tu historial.')) return false;
      return true;
    }).toList();

    if (downloadableHistory.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay historial relevante para descargar.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final buffer = StringBuffer()
        ..writeln("Historial del Chat de Física")
        ..writeln("=" * 30)
        ..writeln("Exportado el: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now().toLocal())}")
        ..writeln();
      final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');

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
          print("Error formatting timestamp: $e");
        }
        buffer
          ..writeln("[$timestampStr] $role:")
          ..writeln(text);
        if (message['fileName'] != null) {
          buffer.writeln("  [Archivo adjunto: ${message['fileName']}]");
        }
        buffer.writeln("-" * 20);
      }

      final String fileContent = buffer.toString();
      final String fileName =
          'historial_fisica_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
      final List<int> fileBytes = utf8.encode(fileContent);

      if (kIsWeb) {
        final blob = html.Blob([fileBytes], 'text/plain', 'native');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Descarga iniciada (Web).')));
        }
      } else {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Historial de Física',
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
              SnackBar(content: Text('Historial guardado en: ${result.split(Platform.pathSeparator).last}')),
            );
          }
        }
      }
    } catch (e) {
      print("Physics Page - Error downloading history: $e");
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
        double chatBubbleMaxWidth = isWideScreen ? 600 : constraints.maxWidth * 0.85;
        bool canSendMessage = !_isLoading &&
            (_controller.text.trim().isNotEmpty || _selectedFile != null);
        bool hasDownloadableContent = !_isLoading && _chatHistory.any((msg) {
          final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
          final text = msg['text'] ?? '';
          if (role == 'SYSTEM' &&
              (text.contains('subida:') ||
                  text.contains('eliminada:') ||
                  text.contains('inicializada') ||
                  text.contains('Error:'))) return false;
          if (role == 'ASSISTANT' &&
              (text == _initialWelcomeMessageText ||
                  text == 'Inicia sesión para guardar y ver tu historial.')) return false;
          return true;
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text('Experto en Física'),
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
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(
                        horizontal: isWideScreen ? 24.0 : 16.0, vertical: 16.0),
                    itemCount: _chatHistory.length,
                    itemBuilder: (context, index) {
                      final message = _chatHistory[index];
                      final role = message['role'] ?? 'system';
                      final text = message['text'] ?? '';
                      final fileName = message['fileName'];
                      final imageBytes = message['imageBytes'] as Uint8List?;
                      final isUser = role == 'user';
                      final isSystem = role == 'system';
                      Color backgroundColor = isUser
                          ? Colors.blue[100]!
                          : isSystem
                          ? Colors.orange[100]!
                          : Colors.grey[200]!;
                      Color textColor = isUser
                          ? Colors.blue[900]!
                          : isSystem
                          ? Colors.orange[900]!
                          : Colors.black87;
                      Alignment alignment = isUser
                          ? Alignment.centerRight
                          : isSystem
                          ? Alignment.center
                          : Alignment.centerLeft;
                      if (isSystem && (text.contains('subida:') || text.contains('eliminada')))
                        return const SizedBox.shrink();

                      return Align(
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
                            crossAxisAlignment:
                            isSystem ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                            children: [
                              if (isUser && fileName != null && imageBytes != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.image_outlined,
                                              size: 16, color: textColor.withOpacity(0.8)),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              fileName,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontStyle: FontStyle.italic,
                                                  color: textColor.withOpacity(0.8)),
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
                                          errorBuilder: (c, e, s) =>
                                          const Text('Error al mostrar imagen'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (text.isNotEmpty)
                                role == 'assistant'
                                    ? MarkdownBody(
                                  data: text,
                                  selectable: true,
                                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                                      .copyWith(
                                      p: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: textColor, height: 1.4)),
                                )
                                    : SelectableText(
                                  text,
                                  textAlign: isSystem ? TextAlign.center : TextAlign.left,
                                  style: TextStyle(
                                    color: textColor,
                                    fontStyle:
                                    isSystem ? FontStyle.italic : FontStyle.normal,
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
                    padding: EdgeInsets.fromLTRB(
                        isWideScreen ? 24.0 : 8.0, 0, isWideScreen ? 24.0 : 8.0, 8.0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.image_outlined, color: Colors.blue[700], size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedFile!.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(60, 30),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: () =>
                                      setState(() => _isPreviewExpanded = !_isPreviewExpanded),
                                  child: Text(_isPreviewExpanded ? 'Ocultar' : 'Mostrar',
                                      style: const TextStyle(color: Colors.blue, fontSize: 13)),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(60, 30),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: _isLoading ? null : _removeImage,
                                  child: Text('Eliminar',
                                      style: TextStyle(
                                          color: _isLoading ? Colors.grey : Colors.red,
                                          fontSize: 13)),
                                ),
                              ],
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: _isPreviewExpanded
                                  ? ConstrainedBox(
                                constraints:
                                BoxConstraints(maxHeight: isWideScreen ? 250 : 150),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: kIsWeb
                                      ? Image.memory(
                                    _selectedFile!.bytes!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (c, e, s) =>
                                    const Text('Error al mostrar imagen web'),
                                  )
                                      : (_selectedFile!.path != null)
                                      ? Image.file(
                                    File(_selectedFile!.path!),
                                    fit: BoxFit.contain,
                                    errorBuilder: (c, e, s) => const Text(
                                        'Error al mostrar imagen móvil'),
                                  )
                                      : const Center(
                                      child: Text(
                                          'Vista previa no disponible (móvil)')),
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
                  padding: EdgeInsets.fromLTRB(
                      isWideScreen ? 24.0 : 8.0, 8.0, isWideScreen ? 24.0 : 8.0, 16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        padding: const EdgeInsets.only(bottom: 8, right: 4),
                        icon: const Icon(Icons.add_photo_alternate_outlined, size: 28),
                        color: _isLoading ? Colors.grey : Colors.blue,
                        tooltip: 'Seleccionar Imagen',
                        onPressed: _isLoading ? null : _pickImage,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: 'Pregunta sobre física...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25.0),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25.0),
                              borderSide: BorderSide(color: Colors.blue.shade200, width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            isDense: true,
                          ),
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (value) {
                            if (canSendMessage) {
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
                            child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send, size: 28),
                        tooltip: 'Enviar Mensaje',
                        color: canSendMessage ? Colors.blue : Colors.grey,
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