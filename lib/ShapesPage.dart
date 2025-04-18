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

class ShapesPage extends StatefulWidget {
  const ShapesPage({super.key});

  @override
  State<ShapesPage> createState() => _ShapesPageState();
}

class _ShapesPageState extends State<ShapesPage> with WidgetsBindingObserver {
  String? _selectedShape;
  final TextEditingController _side1Controller = TextEditingController();
  final TextEditingController _side2Controller = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _sidesController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _perimeterController = TextEditingController();
  final TextEditingController _apothemController = TextEditingController();
  final TextEditingController _controller = TextEditingController();

  List<Map<String, dynamic>> _chatHistory = [];
  PlatformFile? _selectedFile;
  GenerativeModel? _model;
  bool _isLoading = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _chatId;
  final ScrollController _scrollController = ScrollController();
  bool _isPreviewExpanded = false;
  bool _isScrolling = false;
  Map<String, dynamic>? _pendingUserMessage;
  bool _initialScrollExecuted = false;
  int _previousMessageCount = 0;

  final List<String> _shapes = [
    'Triángulo',
    'Rectángulo',
    'Círculo',
    'Polígono Regular',
    'Texto'
  ];
  static const String _initialWelcomeMessageText =
      '¡Bienvenido! Soy tu experto en figuras geométricas. Selecciona, describe o sube una imagen.';
  static const String _loginPromptMessageText =
      'Inicia sesión para guardar y ver tu historial.';
  static const String _systemPrompt = """
Eres un experto en geometría, con un profundo conocimiento de las propiedades de las figuras geométricas, incluyendo triángulos, rectángulos, círculos, polígonos regulares y otras formas. Tu función principal es analizar figuras geométricas, calcular sus propiedades (área, perímetro, apotema, etc.) y proporcionar explicaciones claras y concisas.

**Entrada del Usuario:**

El usuario puede proporcionar:

1. La selección de una figura predefinida (Triángulo, Rectángulo, Círculo, Polígono Regular) y sus dimensiones (base, altura, radio, lado, número de lados, área, perímetro, apotema).
2. Una descripción textual de una figura geométrica (por ejemplo, "un pentágono regular de lado 5 cm, color azul").
3. Una imagen que contiene una figura geométrica (dibujada, diagrama, foto, etc.).
4. Una combinación de las anteriores.

**Instrucciones:**

* **Prioridad de la Imagen:** Si el usuario sube una imagen, analiza la imagen **CUIDADOSAMENTE**. Tu respuesta **DEBE** basarse principalmente en el contenido de la imagen. Si hay texto adicional, úsalo como **CONTEXTO**, pero la imagen es la fuente principal.
* **Imagen Ilegible:** Si la imagen es ilegible, borrosa, incompleta o no contiene una figura geométrica clara, indica esto en tu respuesta con: "La imagen proporcionada no parece contener una figura geométrica válida."
* **Análisis de la Figura (Texto o Imagen):**
    * Identifica la **figura geométrica**.
    * Calcula **todas** las propiedades relevantes (área, perímetro, apotema, etc.). Si falta información, indícalo y explica qué se necesita.
    * Proporciona una descripción textual de la figura.
    * Si es posible, describe *cualitativamente* cómo se vería la figura (color, forma general).
* **Polígonos Regulares:** Para polígonos regulares, usa el número de lados (n) y al menos una de las siguientes medidas (lado, área, perímetro, apotema) para calcular las demás propiedades. Fórmulas:
    * **Área** = (Perímetro × Apotema) / 2
    * **Perímetro** = n × Lado
    * **Área** = (n × Lado × Apotema) / 2
    * **Apotema** = Lado / (2 × tan(π/n))
* **Explicaciones Paso a Paso (Obligatorio):** Explica **DETALLADAMENTE** cada paso de tus cálculos, mostrando **TODAS** las fórmulas y operaciones intermedias. Descompón la solución en pasos numerados.
* **Definiciones (Obligatorio):** Define *todos* los términos geométricos clave (por ejemplo, "área", "perímetro", "apotema", "radio").
* **RESTRICCIÓN ABSOLUTA:** No respondas a preguntas fuera de geometría. Responde **ESTRICTAMENTE** con: "No puedo responder a esa pregunta, ya que está fuera de mi especialización en geometría."
* **Formato de Respuesta (Markdown Estricto):**
    * Usa **Markdown** para todo el texto.
    * **Negritas:** Resalta nombres de figuras, fórmulas, resultados y términos clave.
    * **Pasos Numerados:** Usa listas numeradas para los cálculos.
    * **Títulos:** Usa títulos en negritas (ej., **Identificación**, **Cálculo del Área**).
    * Utiliza notación matemática estándar (π para pi, +, -, ×, ÷, √, ^).
""";

  @override
  void initState() {
    super.initState();
    print("Shapes Page - Auth State Init: ${_auth.currentUser?.uid}");
    _setChatIdBasedOnUser();
    print("Shapes Page - Initial Chat ID: $_chatId");
    _initializeModel();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {
          print("Shapes Page - App resumed, forcing UI redraw.");
        });
      }
    }
  }

  void _setChatIdBasedOnUser() {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      _chatId = currentUser.uid;
      print("Shapes Page - Authenticated User: ${currentUser.email}, Chat ID: $_chatId");
    } else {
      _chatId = null;
      print("Shapes Page - No authenticated user.");
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
          temperature: 0.6,
          topK: 64,
          topP: 0.95,
          maxOutputTokens: 8192,
        ),
        systemInstruction: Content.text(_systemPrompt),
      );
      print("Shapes Page - Gemini model initialized.");
    } catch (e) {
      print("Shapes Page - Error initializing model: $e");
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
        .collection('shapes_messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Future<void> _saveMessageToFirestore(Map<String, dynamic> message) async {
    if (_chatId == null) return;
    if (message['role'] == 'system' &&
        (message['text'].contains('subida:') || message['text'].contains('eliminada'))) {
      print("Shapes Page - Local UI message not saved: ${message['text']}");
      return;
    }
    try {
      final messageToSave = Map<String, dynamic>.from(message);
      messageToSave.remove('id');
      messageToSave.remove('imageBytes');
      messageToSave.remove('mimeType');
      messageToSave['timestamp'] = FieldValue.serverTimestamp();
      print("Shapes Page - Saving message to Firestore: ${messageToSave['role']}");
      await _firestore
          .collection('chats')
          .doc(_chatId)
          .collection('shapes_messages')
          .add(messageToSave);
    } catch (e) {
      print("Shapes Page - Error saving message: $e");
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
    if (userPrompt.trim().isEmpty && _selectedFile == null && _selectedShape == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, selecciona una figura, describe una o sube una imagen.')),
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
    List<Part> currentParts = [];

    Uint8List? imageBytesForHistory;
    String? mimeTypeForHistory;

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
          print("Shapes Page - Warning: HEIC format may not be fully supported by Gemini.");
        }

        currentParts.add(DataPart(mimeType, imageBytes));
        imageBytesForHistory = imageBytes;
        mimeTypeForHistory = mimeType;
        print("Shapes Page - Image prepared: ${_selectedFile!.name}, MIME: $mimeType, Bytes: ${imageBytes.length}");
      } catch (e) {
        print("Shapes Page - Error procesando imagen: $e");
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

    if (userPrompt.trim().isNotEmpty) {
      currentParts.add(TextPart(userPrompt.trim()));
    }

    if (imageBytesForHistory != null) {
      userMessageForHistory['imageBytes'] = imageBytesForHistory;
      userMessageForHistory['mimeType'] = mimeTypeForHistory;
    }

    setState(() {
      _chatHistory.add(userMessageForHistory);
      _pendingUserMessage = null;
      _side1Controller.clear();
      _side2Controller.clear();
      _textController.clear();
      _sidesController.clear();
      _areaController.clear();
      _perimeterController.clear();
      _apothemController.clear();
    });
    _scrollToBottom(jump: false);

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
      List<Content> conversationHistoryForGemini = _chatHistory
          .where((msg) => msg['role'] == 'user' || msg['role'] == 'assistant')
          .take(_chatHistory.length - 1)
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

      conversationHistoryForGemini.add(Content('user', currentParts));

      print("Shapes Page - Sending content to Gemini: ${conversationHistoryForGemini.length} items, Current parts: ${currentParts.length}");
      final response = await _model!.generateContent(conversationHistoryForGemini);

      print("Shapes Page - Response received: ${response.text}");
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
      print("Shapes Page - Error generating response: $e");
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
          if (imageBytesForHistory != null || _textController.text.isNotEmpty) {
            _selectedShape = null;
          }
          if (_textController.text.isNotEmpty) {
            _textController.clear();
          }
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
        permissionGranted = true;
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
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        if (file.size > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('La imagen excede el límite de 5MB.')),
            );
          }
          return;
        }

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
          print("Shapes Page - Error: Image bytes are null or empty.");
          return;
        }

        if (mounted) {
          setState(() {
            _selectedFile = file;
            _isPreviewExpanded = true;
            _selectedShape = null;
            _side1Controller.clear();
            _side2Controller.clear();
            _textController.clear();
            _sidesController.clear();
            _areaController.clear();
            _perimeterController.clear();
            _apothemController.clear();
            _chatHistory.add({
              'role': 'system',
              'text': 'Imagen subida: ${file.name}',
              'timestamp': DateTime.now(),
            });
          });
          _scrollToBottom(jump: false);
          print("Shapes Page - Image selected: ${file.name}, Bytes: ${imageBytes.length}");
        }
      } else {
        print("Shapes Page - Image selection cancelled.");
      }
    } catch (e) {
      print("Shapes Page - Error picking image: $e");
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
      print("Shapes Page - Selected image removed.");
    }
  }

  Future<void> _clearChat() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar Chat de Figuras'),
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
      print("Shapes Page - Clearing Firestore for $_chatId/shapes_messages...");
      try {
        final ref = _firestore.collection('chats').doc(_chatId).collection('shapes_messages');
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
        print("Shapes Page - Firestore history cleared.");

        await _saveMessageToFirestore(welcomeMessage);

        if (mounted) {
          setState(() {
            _chatHistory = [welcomeMessage];
            _isLoading = false;
            _initialScrollExecuted = false;
            _selectedFile = null;
            _selectedShape = null;
            _isPreviewExpanded = false;
            _side1Controller.clear();
            _side2Controller.clear();
            _textController.clear();
            _sidesController.clear();
            _areaController.clear();
            _perimeterController.clear();
            _apothemController.clear();
          });
        }
        _scrollToBottom(jump: true);
      } catch (e) {
        print("Shapes Page - Error clearing Firestore: $e");
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
          _selectedFile = null;
          _selectedShape = null;
          _isPreviewExpanded = false;
          _side1Controller.clear();
          _side2Controller.clear();
          _textController.clear();
          _sidesController.clear();
          _areaController.clear();
          _perimeterController.clear();
          _apothemController.clear();
        });
      }
      _scrollToBottom(jump: true);
    }
  }

  Future<void> _downloadHistory() async {
    final downloadableHistory = _chatHistory.where((msg) {
      final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
      final text = msg['text'] ?? '';
      if (role == 'SYSTEM' && (text.contains('subida:') || text.contains('eliminada:') || text.contains('inicializada') || text.contains('Error:'))) {
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
      buffer.writeln("Historial del Chat de Figuras Geométricas");
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
      final String fileName = 'historial_figuras_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
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
          dialogTitle: 'Guardar Historial de Figuras',
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
      print("Error general al descargar (Shapes): $e");
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
    _side1Controller.dispose();
    _side2Controller.dispose();
    _textController.dispose();
    _sidesController.dispose();
    _areaController.dispose();
    _perimeterController.dispose();
    _apothemController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scrollToBottom({required bool jump}) {
    if (_isScrolling) return;
    _isScrolling = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        final currentPosition = _scrollController.position.pixels;
        if ((maxExtent - currentPosition).abs() > 50) {
          if (jump) {
            _scrollController.jumpTo(maxExtent);
          } else {
            _scrollController.animateTo(
              maxExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        }
      }
      Future.delayed(const Duration(milliseconds: 50), () => _isScrolling = false);
    });
  }

  void _tryGenerateResponse() {
    if (_isLoading) return;

    String userPrompt = '';

    if (_selectedFile != null) {
      userPrompt = 'Analiza la figura geométrica en la imagen subida.';
      _textController.clear();
      _generateResponse(userPrompt);
      return;
    }

    if (_selectedShape != null) {
      bool isValidInput = true;
      String shapeDetails = '';

      switch (_selectedShape) {
        case 'Triángulo':
          final base = double.tryParse(_side1Controller.text.trim());
          final altura = double.tryParse(_side2Controller.text.trim());
          if (base == null || altura == null || base <= 0 || altura <= 0) {
            isValidInput = false;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa base y altura numéricas válidas y positivas.')));
          } else {
            shapeDetails = 'un triángulo con base $base y altura $altura';
          }
          break;
        case 'Rectángulo':
          final ancho = double.tryParse(_side1Controller.text.trim());
          final altura = double.tryParse(_side2Controller.text.trim());
          if (ancho == null || altura == null || ancho <= 0 || altura <= 0) {
            isValidInput = false;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa ancho y altura numéricos válidos y positivos.')));
          } else {
            shapeDetails = 'un rectángulo con ancho $ancho y altura $altura';
          }
          break;
        case 'Círculo':
          final radio = double.tryParse(_side1Controller.text.trim());
          if (radio == null || radio <= 0) {
            isValidInput = false;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un radio numérico válido y positivo.')));
          } else {
            shapeDetails = 'un círculo con radio $radio';
          }
          break;
        case 'Polígono Regular':
          final nLados = int.tryParse(_sidesController.text.trim());
          if (nLados == null || nLados < 3) {
            isValidInput = false;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un número de lados válido (entero ≥ 3).')));
            break;
          }
          final lado = _side1Controller.text.trim().isNotEmpty ? double.tryParse(_side1Controller.text.trim()) : null;
          final area = _areaController.text.trim().isNotEmpty ? double.tryParse(_areaController.text.trim()) : null;
          final perimetro = _perimeterController.text.trim().isNotEmpty ? double.tryParse(_perimeterController.text.trim()) : null;
          final apotema = _apothemController.text.trim().isNotEmpty ? double.tryParse(_apothemController.text.trim()) : null;

          bool hasAtLeastOneMeasure = lado != null || area != null || perimetro != null || apotema != null;
          bool optionalFieldsAreValid =
              (_side1Controller.text.trim().isEmpty || (lado != null && lado > 0)) &&
                  (_areaController.text.trim().isEmpty || (area != null && area > 0)) &&
                  (_perimeterController.text.trim().isEmpty || (perimetro != null && perimetro > 0)) &&
                  (_apothemController.text.trim().isEmpty || (apotema != null && apotema > 0));

          if (!hasAtLeastOneMeasure) {
            isValidInput = false;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proporciona al menos una medida válida (lado, área, perímetro o apotema).')));
          } else if (!optionalFieldsAreValid) {
            isValidInput = false;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa valores numéricos positivos en los campos opcionales o déjalos vacíos.')));
          } else {
            shapeDetails = 'un polígono regular con $nLados lados';
            if (lado != null) shapeDetails += ', lado $lado';
            if (area != null) shapeDetails += ', área $area';
            if (perimetro != null) shapeDetails += ', perímetro $perimetro';
            if (apotema != null) shapeDetails += ', apotema $apotema';
          }
          break;
        case 'Texto':
          if (_textController.text.trim().isEmpty) {
            isValidInput = false;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, describe la figura.')));
          } else {
            shapeDetails = 'una figura con las siguientes características: ${_textController.text.trim()}';
          }
          break;
        default:
          isValidInput = false;
      }

      if (isValidInput) {
        userPrompt = 'Analiza $shapeDetails.';
        _generateResponse(userPrompt);
      }
      return;
    }

    if (_textController.text.trim().isNotEmpty) {
      userPrompt = 'Analiza una figura con las siguientes características: ${_textController.text.trim()}.';
      _generateResponse(userPrompt);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Selecciona una figura, describe una o sube una imagen.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 720;
        double chatBubbleMaxWidth = isWideScreen ? 600 : constraints.maxWidth * 0.85;
        bool canSendMessage = !_isLoading &&
            (_selectedFile != null ||
                _selectedShape != null ||
                _textController.text.trim().isNotEmpty);
        bool hasDownloadableContent = !_isLoading && _chatHistory.any((msg) {
          final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
          final text = msg['text'] ?? '';
          if (role == 'SYSTEM' && (text.contains('subida:') || text.contains('eliminada:') || text.contains('Error:'))) return false;
          if (role == 'ASSISTANT' && (text == _initialWelcomeMessageText || text == _loginPromptMessageText)) return false;
          return true;
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text('Análisis de Figuras'),
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
                        print("Shapes Page - StreamBuilder Error: ${snapshot.error}");
                        return Center(child: Text('Error al cargar mensajes: ${snapshot.error}'));
                      }
                      if (_chatId == null) {
                        if (_chatHistory.isEmpty) {
                          _chatHistory.add({'role': 'assistant', 'text': _loginPromptMessageText, 'timestamp': DateTime.now()});
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
                          _chatHistory.add({'role': 'assistant', 'text': _initialWelcomeMessageText, 'timestamp': DateTime.now()});
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
                        print("Shapes Page - Initial load ($currentMessageCount messages).");
                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: true));
                        _initialScrollExecuted = true;
                      } else if (currentMessageCount > _previousMessageCount && _initialScrollExecuted) {
                        print("Shapes Page - New message ($currentMessageCount > $_previousMessageCount).");
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
                                        ? Image.memory(_selectedFile!.bytes!, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Center(child: Text('Error (Web)')))
                                        : const Center(child: Text('No disponible (Web)')))
                                        : (_selectedFile?.path != null
                                        ? Image.file(File(_selectedFile!.path!), fit: BoxFit.contain, errorBuilder: (c, e, s) => const Center(child: Text('Error (Móvil)')))
                                        : const Center(child: Text('No disponible (Móvil)'))),
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
                  decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.5))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            padding: const EdgeInsets.only(bottom: 8, right: 4),
                            icon: const Icon(Icons.image_search, size: 28),
                            color: _isLoading ? Colors.grey : Colors.teal,
                            tooltip: 'Subir Imagen',
                            onPressed: (_isLoading || _selectedShape != null) ? null : _pickImage,
                          ),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: 'Selecciona figura',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide(color: Colors.teal.shade200, width: 1.5)),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                isDense: true,
                              ),
                              value: _selectedShape,
                              items: _shapes.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
                              onChanged: (_isLoading || _selectedFile != null)
                                  ? null
                                  : (v) => setState(() {
                                _selectedShape = v;
                                _side1Controller.clear();
                                _side2Controller.clear();
                                _textController.clear();
                                _sidesController.clear();
                                _areaController.clear();
                                _perimeterController.clear();
                                _apothemController.clear();
                              }),
                            ),
                          ),
                          if (_selectedShape == null || _selectedShape == 'Texto')
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: IconButton(
                                padding: const EdgeInsets.only(bottom: 8, left: 4),
                                icon: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, size: 28),
                                tooltip: 'Analizar Figura',
                                color: canSendMessage ? Colors.teal : Colors.grey,
                                onPressed: canSendMessage ? _tryGenerateResponse : null,
                              ),
                            ),
                        ],
                      ),
                      if (_selectedShape != null && _selectedFile == null) ...[
                        const SizedBox(height: 8),
                        if (_selectedShape == 'Triángulo' || _selectedShape == 'Rectángulo')
                          Row(
                            children: [
                              Expanded(child: _buildTextField(_side1Controller, _selectedShape == 'Triángulo' ? 'Base' : 'Ancho')),
                              const SizedBox(width: 8),
                              Expanded(child: _buildTextField(_side2Controller, 'Altura')),
                            ],
                          ),
                        if (_selectedShape == 'Círculo')
                          _buildTextField(_side1Controller, 'Radio'),
                        if (_selectedShape == 'Polígono Regular') ...[
                          _buildTextField(_sidesController, 'Lados (n ≥ 3)', keyboard: TextInputType.number),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: _buildTextField(_side1Controller, 'Lado (opc)')),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField(_apothemController, 'Apotema (opc)')),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: _buildTextField(_areaController, 'Área (opc)')),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField(_perimeterController, 'Perímetro (opc)')),
                          ]),
                        ],
                        if (_selectedShape == 'Texto')
                          _buildTextField(_textController, 'Describe la figura...', keyboard: TextInputType.text, maxLines: 3),
                        if (_selectedShape != 'Texto')
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ElevatedButton.icon(
                              onPressed: canSendMessage ? _tryGenerateResponse : null,
                              icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
                              label: const Text('Analizar'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(45),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                              ),
                            ),
                          ),
                      ],
                      if (_selectedShape == null && _textController.text.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: ElevatedButton.icon(
                            onPressed: canSendMessage ? _tryGenerateResponse : null,
                            icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
                            label: const Text('Analizar Descripción'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(45),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                            ),
                          ),
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

  Widget _buildTextField(
      TextEditingController controller, String label,
      {TextInputType keyboard = TextInputType.number, int? maxLines = 1, TextInputAction? textInputAction, ValueChanged<String>? onSubmitted}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide(color: Colors.teal.shade200, width: 1.5)),
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        isDense: true,
      ),
      keyboardType: keyboard,
      maxLines: maxLines,
      enabled: !_isLoading,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 16),
    );
  }
}