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

// --- NUEVO: Añadir WidgetsBindingObserver ---
class _PhysicsExpertPageState extends State<PhysicsExpertPage> with WidgetsBindingObserver {
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
  bool _isScrolling = false; // Controlar desplazamiento múltiple
  Map<String, dynamic>? _pendingUserMessage;
  bool _initialScrollExecuted = false;
  int _previousMessageCount = 0;
  final _textFieldValue = ValueNotifier<String>(''); // Para ValueListenableBuilder

  static const String _initialWelcomeMessageText =
      '¡Bienvenido! Soy tu experto en física. Pregúntame cualquier cosa sobre física o sube una imagen de un problema.';
  static const String _loginPromptMessageText =
      'Inicia sesión para guardar y ver tu historial.';
  static const String _systemPrompt = """
Eres un experto en física con un conocimiento profundo en mecánica, termodinámica, electromagnetismo, óptica, física moderna y otras ramas. Tu función principal es responder preguntas relacionadas con física y analizar imágenes que contengan problemas, diagramas o situaciones físicas.

**Entrada del Usuario:**

El usuario puede proporcionar:

1. Una pregunta de texto sobre física (por ejemplo, "¿Cuál es la velocidad final de un objeto en caída libre tras 5 segundos?").
2. Una imagen que contenga un problema de física, un diagrama o una situación física.
3. Ambas cosas: una imagen Y una pregunta de texto relacionada.

**Instrucciones:**

* **Prioridad de la Imagen:** Si el usuario sube una imagen, analiza la imagen **CUIDADOSAMENTE**. Tu respuesta **DEBE** basarse principalmente en el contenido de la imagen. Si hay texto adicional, úsalo como **CONTEXTO**, pero la imagen tiene prioridad.
* **Imagen Ilegible:** Si la imagen es ilegible, borrosa o no contiene información física clara, indica esto en tu respuesta con: "La imagen proporcionada no parece contener información física válida."
* **Análisis de Física (Texto o Imagen):**
    * Identifica el **concepto físico** relevante (por ejemplo, cinemática, dinámica, energía).
    * Si es un problema, resuélvelo **paso a paso**, mostrando **todas** las fórmulas y cálculos.
    * Proporciona explicaciones **claras y detalladas** de cada paso.
    * Si faltan datos, indícalos y explica qué se necesita para resolverlo.
* **Explicaciones Paso a Paso (Obligatorio):** Para problemas numéricos o conceptuales, descompón la solución en **pasos numerados**, mostrando **fórmulas**, **sustituciones** y **resultados**.
* **Definiciones (Obligatorio):** Define *todos* los términos físicos clave (por ejemplo, "aceleración", "energía potencial", "campo eléctrico").
* **RESTRICCIÓN ABSOLUTA:** No respondas a preguntas fuera de física. Responde **ESTRICTAMENTE** con: "No puedo responder a esa pregunta, ya que está fuera de mi especialización en física."
* **Formato de Respuesta (Markdown Estricto):**
    * Usa **Markdown** para todo el texto.
    * Usa notación matemática estándar (por ejemplo, v = u + at, F = ma, E = mc²).
    * Resalta **conceptos clave**, **fórmulas** y **resultados** en negritas.
    * Usa **títulos** y **subtítulos** en negritas (ej., **Concepto**, **Cálculo**, **Resultado**).
    * Descompón los cálculos en **pasos numerados**.
""";

  @override
  void initState() {
    super.initState();
    print("Physics Page - Auth State Init: ${_auth.currentUser?.uid}");
    _setChatIdBasedOnUser();
    print("Physics Page - Initial Chat ID: $_chatId");
    _initializeModel();
    _textFieldValue.value = _controller.text; // Inicializar notifier
    // --- NUEVO: Registrar el observador ---
    WidgetsBinding.instance.addObserver(this);
  }

  // --- NUEVO: Método del ciclo de vida ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Si la app se reanuda (vuelve del segundo plano)
    if (state == AppLifecycleState.resumed) {
      // Forzar un redibujo de la UI
      if (mounted) {
        setState(() {
          // No es necesario cambiar nada aquí, solo llamar a setState
          // para que Flutter reconstruya el widget y refresque la UI.
          print("Physics Page - App resumed, forcing UI redraw.");
        });
      }
    }
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
        model: 'gemini-2.5-pro-exp-03-25', // Modelo adecuado para visión y texto
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
    } catch (e) {
      print("Physics Page - Error initializing model: $e");
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
        .collection('physics_messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Future<void> _saveMessageToFirestore(Map<String, dynamic> message) async {
    if (_chatId == null) return;
    // Evitar guardar mensajes locales del sistema
    if (message['role'] == 'system' &&
        (message['text'].contains('subida:') || message['text'].contains('eliminada'))) {
      print("Physics Page - Local UI message not saved: ${message['text']}");
      return;
    }
    try {
      final messageToSave = Map<String, dynamic>.from(message);
      messageToSave.remove('id');
      messageToSave.remove('imageBytes'); // No guardar bytes
      messageToSave.remove('mimeType');
      messageToSave['timestamp'] = FieldValue.serverTimestamp(); // Timestamp del servidor
      print("Physics Page - Saving message to Firestore: ${messageToSave['role']}");
      await _firestore
          .collection('chats')
          .doc(_chatId)
          .collection('physics_messages')
          .add(messageToSave);
    } catch (e) {
      print("Physics Page - Error saving message: $e");
      // Considerar mostrar feedback
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
    // Validar entrada
    if (userPrompt.trim().isEmpty && _selectedFile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Por favor, ingresa una pregunta o selecciona una imagen.')),
        );
      }
      _scrollToBottom(jump: false);
      return;
    }

    setState(() => _isLoading = true);

    // --- Preparar Mensaje Usuario ---
    Map<String, dynamic> userMessageForHistory = {
      'role': 'user',
      'text': userPrompt.trim(),
      'timestamp': DateTime.now(),
    };
    List<Part> partsForGemini = [];
    Uint8List? imageBytesForHistory;
    String? mimeTypeForHistory;

    // Procesar imagen
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

        mimeTypeForHistory = 'image/jpeg'; // Default
        final extension = _selectedFile!.extension?.toLowerCase();
        if (extension == 'png') mimeTypeForHistory = 'image/png';
        else if (extension == 'webp') mimeTypeForHistory = 'image/webp';
        else if (extension == 'gif') mimeTypeForHistory = 'image/gif';
        else if (extension == 'heic') mimeTypeForHistory = 'image/heic';

        partsForGemini.add(DataPart(mimeTypeForHistory!, imageBytes)); // Añadir a API
        imageBytesForHistory = imageBytes; // Guardar para UI local
      } catch (e) {
        print("Physics Page - Error procesando imagen: $e");
        final err = {'role': 'system', 'text': 'Error procesando imagen: $e', 'timestamp': DateTime.now()};
        if (mounted) {
          setState(() { _chatHistory.add(err); _isLoading = false; _selectedFile = null; _isPreviewExpanded = false; });
        }
        if (_chatId != null) _saveMessageToFirestore(err);
        _scrollToBottom(jump: false);
        return;
      }
    }

    // Añadir texto
    if (userPrompt.trim().isNotEmpty) {
      partsForGemini.add(TextPart(userPrompt.trim()));
    }

    // Añadir bytes a historial local
    if (imageBytesForHistory != null) {
      userMessageForHistory['imageBytes'] = imageBytesForHistory;
    }

    // --- Actualizar UI y Guardar Mensaje Usuario ---
    setState(() {
      _chatHistory.add(userMessageForHistory);
      _pendingUserMessage = null;
      _controller.clear();
      _textFieldValue.value = ''; // Limpiar notifier
    });
    _scrollToBottom(jump: false);

    // Guardar en Firestore (sin bytes)
    if (_chatId != null) {
      final messageToSave = Map<String, dynamic>.from(userMessageForHistory);
      messageToSave.remove('imageBytes');
      messageToSave.remove('mimeType');
      await _saveMessageToFirestore(messageToSave);
    }

    if (partsForGemini.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // --- Llamada a Gemini API ---
    try {
      // Construir historial para API
      List<Content> conversationHistoryForGemini = _chatHistory
          .where((msg) => msg['role'] == 'user' || msg['role'] == 'assistant')
          .map((msg) {
        List<Part> currentParts = [];
        if (msg['text'] != null && (msg['text'] as String).trim().isNotEmpty) {
          currentParts.add(TextPart(msg['text']));
        }
        // Añadir imagen solo si es el mensaje actual y tiene datos
        if (msg == userMessageForHistory && msg['imageBytes'] != null && mimeTypeForHistory != null) {
          currentParts.add(DataPart(mimeTypeForHistory, msg['imageBytes']));
        } else if (msg['fileName'] != null && msg['role'] == 'user') {
          currentParts.add(TextPart("[Imagen adjunta: ${msg['fileName']}]"));
        }
        final role = msg['role'] == 'assistant' ? 'model' : 'user';
        return Content(role, currentParts.isNotEmpty ? currentParts : [TextPart('')]);
      }).toList();

      print("Physics Page - Sending content to Gemini with history: ${conversationHistoryForGemini.length} items");
      final response = await _model!.generateContent(conversationHistoryForGemini); // Enviar historial

      print("Physics Page - Response received: ${response.text}");
      final assistantMessage = {
        'role': 'assistant',
        'text': response.text ?? 'El asistente no proporcionó respuesta.',
        'timestamp': DateTime.now(),
      };

      // --- Actualizar UI y Guardar Respuesta Asistente ---
      setState(() {
        _chatHistory.add(assistantMessage);
      });
      _scrollToBottom(jump: false);

      if (_chatId != null) await _saveMessageToFirestore(assistantMessage);

    } catch (e) {
      print("Physics Page - Error generating response: $e");
      final err = {'role': 'system', 'text': 'Error al contactar al asistente: $e', 'timestamp': DateTime.now()};
      if (mounted) setState(() => _chatHistory.add(err));
      if (_chatId != null) _saveMessageToFirestore(err);
    } finally {
      // --- Limpieza Final ---
      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedFile = null; // Limpiar archivo después de enviar
          _isPreviewExpanded = false;
        });
        _scrollToBottom(jump: false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      // --- Permisos ---
      bool permissionGranted = false;
      if (!kIsWeb && Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        print("Android SDK: $sdkInt");
        PermissionStatus status;
        if (sdkInt >= 33) {
          status = await Permission.photos.request();
        } else {
          status = await Permission.storage.request();
        }
        if (status.isPermanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Permiso denegado permanentemente.'), action: SnackBarAction(label: 'Abrir Configuración', onPressed: openAppSettings)));
          }
          return;
        }
        permissionGranted = status.isGranted;
        print("${sdkInt >= 33 ? 'Photos' : 'Storage'} Permission Granted: $permissionGranted");
      } else {
        permissionGranted = true;
      }

      if (!permissionGranted) {
        print("Permiso denegado.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permiso para acceder a imágenes denegado.')));
        }
        return;
      }

      // --- Selección ---
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: kIsWeb);

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        // Validar tamaño
        if (file.size > 5 * 1024 * 1024) { // 5MB
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La imagen excede el límite de 5MB.')));
          }
          return;
        }
        // Actualizar estado
        if (mounted) {
          setState(() {
            _selectedFile = file;
            _isPreviewExpanded = true;
            _chatHistory.add({'role': 'system', 'text': 'Imagen subida: ${file.name}', 'timestamp': DateTime.now()});
          });
          _scrollToBottom(jump: false);
          print("Physics Page - Image selected: ${_selectedFile?.name}");
        }
      } else {
        print("Physics Page - Image selection cancelled.");
      }
    } catch (e) {
      print("Physics Page - Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar la imagen: $e')));
      }
    }
  }

  void _removeImage() {
    if (mounted && _selectedFile != null) {
      setState(() {
        _chatHistory.add({'role': 'system', 'text': 'Imagen eliminada: ${_selectedFile!.name}', 'timestamp': DateTime.now()});
        _selectedFile = null;
        _isPreviewExpanded = false;
      });
      _scrollToBottom(jump: false);
      print("Physics Page - Selected image removed.");
    }
  }

  Future<void> _clearChat() async {
    // Confirmación
    bool? confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Limpiar Chat de Física'), content: const Text('¿Seguro? Esta acción no se puede deshacer.'), actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')), TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Limpiar', style: TextStyle(color: Colors.red)))]));
    if (confirm != true) return;

    if (mounted) setState(() => _isLoading = true);

    // Mensaje bienvenida
    final welcomeMessage = {'role': 'assistant', 'text': _chatId != null ? _initialWelcomeMessageText : _loginPromptMessageText, 'timestamp': DateTime.now()};

    if (_chatId != null) {
      // Limpiar Firestore
      print("Physics Page - Clearing Firestore for $_chatId/physics_messages...");
      try {
        final ref = _firestore.collection('chats').doc(_chatId).collection('physics_messages');
        QuerySnapshot snapshot; int deletedCount = 0;
        do {
          snapshot = await ref.limit(100).get();
          if (snapshot.docs.isNotEmpty) {
            final batch = _firestore.batch();
            for (var doc in snapshot.docs) { batch.delete(doc.reference); }
            await batch.commit(); deletedCount += snapshot.docs.length;
            print("Lote de ${snapshot.docs.length} mensajes borrado (total: $deletedCount).");
          }
        } while (snapshot.docs.isNotEmpty);
        print("Physics Page - Firestore history cleared.");

        await _saveMessageToFirestore(welcomeMessage); // Guardar bienvenida

        // Actualizar UI
        if (mounted) {
          setState(() { _chatHistory = [welcomeMessage]; _isLoading = false; _initialScrollExecuted = false; _selectedFile = null; _isPreviewExpanded = false; _controller.clear(); _textFieldValue.value = ''; });
        }
        _scrollToBottom(jump: true);

      } catch (e) {
        print("Physics Page - Error clearing Firestore: $e");
        final err = {'role': 'system', 'text': 'Error limpiando historial nube: $e', 'timestamp': DateTime.now()};
        if (mounted) { setState(() { _chatHistory = [err, welcomeMessage]; _isLoading = false; }); }
        _scrollToBottom(jump: true);
      }
    } else {
      // Limpiar localmente
      if (mounted) {
        setState(() { _chatHistory = [welcomeMessage]; _isLoading = false; _selectedFile = null; _isPreviewExpanded = false; _controller.clear(); _textFieldValue.value = ''; });
      }
      _scrollToBottom(jump: true);
    }
  }

  Future<void> _downloadHistory() async {
    // 1. Filtrar
    final downloadableHistory = _chatHistory.where((msg) {
      final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM'; final text = msg['text'] ?? '';
      if (role == 'SYSTEM' && (text.contains('subida:') || text.contains('eliminada:') || text.contains('inicializada') || text.contains('Error:'))) return false;
      if (role == 'ASSISTANT' && (text == _initialWelcomeMessageText || text == _loginPromptMessageText)) return false;
      return true;
    }).toList();

    // 2. Verificar mensajes usuario
    final hasUserMessages = _chatHistory.any((msg) => msg['role'] == 'user' && (msg['text']?.toString().trim().isNotEmpty == true || msg['fileName'] != null));

    // 3. Bloquear Android sin mensajes
    if (!kIsWeb && Platform.isAndroid && !hasUserMessages) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay preguntas enviadas para descargar.'))); }
      return;
    }

    // 4. Verificar historial relevante
    if (downloadableHistory.isEmpty) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay historial relevante para descargar.'))); }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      // 5. Crear contenido
      final StringBuffer buffer = StringBuffer();
      buffer.writeln("Historial del Chat de Física"); buffer.writeln("=" * 30);
      buffer.writeln("Exportado el: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now().toLocal())}"); buffer.writeln();
      final DateFormat formatter = DateFormat('yyyy-MM-dd HH:mm:ss');

      for (final message in downloadableHistory) {
        final role = message['role']?.toString().toUpperCase() ?? 'SYSTEM'; final text = message['text'] ?? '';
        dynamic ts = message['timestamp']; String timestampStr = 'N/A';
        try {
          if (ts is Timestamp) timestampStr = formatter.format(ts.toDate().toLocal());
          else if (ts is DateTime) timestampStr = formatter.format(ts.toLocal());
          else timestampStr = formatter.format(DateTime.now().toLocal());
        } catch (e) { print("Error formateando timestamp: $e"); timestampStr = formatter.format(DateTime.now().toLocal()); }
        buffer.writeln("[$timestampStr] $role:"); buffer.writeln(text);
        if (message['fileName'] != null) buffer.writeln("  [Archivo adjunto: ${message['fileName']}]");
        buffer.writeln("-" * 20);
      }

      // 6. Guardar/Descargar
      final String fileContent = buffer.toString();
      final String fileName = 'historial_fisica_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
      final List<int> fileBytes = utf8.encode(fileContent);

      if (kIsWeb) {
        final blob = html.Blob([fileBytes], 'text/plain', 'native'); final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)..setAttribute("download", fileName)..click();
        html.Url.revokeObjectUrl(url);
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Descarga iniciada (Web).'))); }
      } else {
        String? outputFile = await FilePicker.platform.saveFile(dialogTitle: 'Guardar Historial de Física', fileName: fileName, bytes: Uint8List.fromList(fileBytes));
        if (outputFile == null) {
          if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado cancelado.'))); }
        } else {
          if (mounted) { final savedFileName = outputFile.split(Platform.pathSeparator).last; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Historial guardado como: $savedFileName'))); }
        }
      }
    } catch (e) {
      print("Error general al descargar (Physics): $e");
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al preparar la descarga: $e'))); }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _textFieldValue.dispose(); // Dispose notifier
    // --- NUEVO: Remover el observador ---
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
        if ((maxExtent - currentPosition).abs() > 50) { // Solo si no está cerca del final
          if (jump) {
            _scrollController.jumpTo(maxExtent);
          } else {
            _scrollController.animateTo(maxExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        }
      }
      Future.delayed(const Duration(milliseconds: 50), () => _isScrolling = false); // Permitir siguiente scroll
    });
  }


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 720;
        double chatBubbleMaxWidth = isWideScreen ? 600 : constraints.maxWidth * 0.85;
        // Determinar si se puede descargar
        bool hasDownloadableContent = !_isLoading && _chatHistory.any((msg) {
          final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM'; final text = msg['text'] ?? '';
          if (role == 'SYSTEM' && (text.contains('subida:') || text.contains('eliminada:') || text.contains('Error:'))) return false;
          if (role == 'ASSISTANT' && (text == _initialWelcomeMessageText || text == _loginPromptMessageText)) return false;
          return true;
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text('Experto en Física'),
            centerTitle: true,
            elevation: 1,
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.canPop(context) ? Navigator.pop(context) : null),
            actions: [
              IconButton(icon: const Icon(Icons.download_outlined), onPressed: hasDownloadableContent ? _downloadHistory : null, tooltip: 'Descargar historial', color: hasDownloadableContent ? null : Colors.grey),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: _isLoading ? null : _clearChat, tooltip: 'Limpiar chat', color: _isLoading ? Colors.grey : null),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Área del Chat
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _getChatStream(),
                    builder: (context, snapshot) {
                      // --- Estados ---
                      if (snapshot.connectionState == ConnectionState.waiting && _chatId != null) return const Center(child: CircularProgressIndicator());
                      if (snapshot.hasError) { print("Physics Page - Stream Error: ${snapshot.error}"); return Center(child: Text('Error: ${snapshot.error}')); }
                      if (_chatId == null) { if (_chatHistory.isEmpty) _chatHistory.add({'role': 'assistant', 'text': _loginPromptMessageText, 'timestamp': DateTime.now()}); }

                      // --- Mensajes ---
                      final List<Map<String, dynamic>> messagesFromStream;
                      if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                        messagesFromStream = snapshot.data!.docs.map((doc) { final data = doc.data(); data['id'] = doc.id; if (data['timestamp'] is Timestamp) data['timestamp'] = (data['timestamp'] as Timestamp).toDate(); else if (data['timestamp'] is! DateTime) data['timestamp'] = DateTime.now(); return data; }).toList();
                        _chatHistory = messagesFromStream;
                      } else {
                        messagesFromStream = [];
                        if (_chatHistory.isEmpty && _chatId != null) _chatHistory.add({'role': 'assistant', 'text': _initialWelcomeMessageText, 'timestamp': DateTime.now()});
                      }

                      final allMessages = [..._chatHistory];
                      if (_pendingUserMessage != null) { allMessages.add(_pendingUserMessage!); allMessages.sort((a, b) => (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime)); }

                      // --- Scroll ---
                      final currentMessageCount = allMessages.length;
                      if (currentMessageCount > 0 && !_initialScrollExecuted) { print("Physics Page - Initial load ($currentMessageCount)."); WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: true)); _initialScrollExecuted = true; }
                      else if (currentMessageCount > _previousMessageCount && _initialScrollExecuted) { print("Physics Page - New message ($currentMessageCount > $_previousMessageCount)."); WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: false)); }
                      _previousMessageCount = currentMessageCount;

                      // --- Lista ---
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: ListView.builder(
                          key: ValueKey(allMessages.length),
                          controller: _scrollController,
                          padding: EdgeInsets.symmetric(horizontal: isWideScreen ? 24.0 : 16.0, vertical: 16.0),
                          itemCount: allMessages.length,
                          itemBuilder: (context, index) {
                            final message = allMessages[index];
                            final role = message['role'] as String? ?? 'system'; final text = message['text'] as String? ?? '';
                            final fileName = message['fileName'] as String?; final imageBytes = message['imageBytes'] as Uint8List?;
                            final isUser = role == 'user'; final isSystem = role == 'system';
                            final key = ValueKey(message['id'] ?? message['timestamp'].toString());

                            Color backgroundColor; Color textColor; Alignment alignment; TextAlign textAlign; CrossAxisAlignment crossAxisAlignment;
                            if (isUser) { backgroundColor = Colors.blue[100]!; textColor = Colors.blue[900]!; alignment = Alignment.centerRight; textAlign = TextAlign.left; crossAxisAlignment = CrossAxisAlignment.start; }
                            else if (isSystem) { backgroundColor = Colors.orange[100]!; textColor = Colors.orange[900]!; alignment = Alignment.center; textAlign = TextAlign.center; crossAxisAlignment = CrossAxisAlignment.center; }
                            else { backgroundColor = Colors.grey[200]!; textColor = Colors.black87; alignment = Alignment.centerLeft; textAlign = TextAlign.left; crossAxisAlignment = CrossAxisAlignment.start; }

                            if (isSystem && (text.contains('subida:') || text.contains('eliminada:'))) return const SizedBox.shrink();

                            return Align(
                              key: key, alignment: alignment,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 5.0), padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                                decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(16.0), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 2, offset: const Offset(0, 1))]),
                                constraints: BoxConstraints(maxWidth: chatBubbleMaxWidth),
                                child: Column(
                                  crossAxisAlignment: crossAxisAlignment, mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isUser && fileName != null && imageBytes != null) Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.image_outlined, size: 16, color: textColor.withOpacity(0.8)), const SizedBox(width: 4), Flexible(child: Text(fileName, style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: textColor.withOpacity(0.8)), overflow: TextOverflow.ellipsis))]), const SizedBox(height: 6), ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(imageBytes, fit: BoxFit.contain, height: 100, errorBuilder: (c, e, s) => const Text('Error imagen')))])),
                                    if (text.isNotEmpty) (role == 'assistant') ? MarkdownBody(data: text, selectable: true, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor, height: 1.4), code: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', backgroundColor: Colors.black12, color: textColor))) : SelectableText(text, textAlign: textAlign, style: TextStyle(color: textColor, fontStyle: isSystem ? FontStyle.italic : FontStyle.normal, fontSize: isSystem ? 13 : 16, height: 1.4)),
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

                // Previsualización Imagen
                if (_selectedFile != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(isWideScreen ? 24.0 : 8.0, 0, isWideScreen ? 24.0 : 8.0, 8.0),
                    child: Card(
                      elevation: 2, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Row(children: [Icon(Icons.image_outlined, color: Colors.blue[700], size: 20), const SizedBox(width: 8), Expanded(child: Text(_selectedFile!.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))), TextButton(style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap), onPressed: () => setState(() => _isPreviewExpanded = !_isPreviewExpanded), child: Text(_isPreviewExpanded ? 'Ocultar' : 'Mostrar', style: const TextStyle(color: Colors.blue, fontSize: 13))), TextButton(style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap), onPressed: _isLoading ? null : _removeImage, child: Text('Eliminar', style: TextStyle(color: _isLoading ? Colors.grey : Colors.red, fontSize: 13)))]),
                            AnimatedSize(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, child: _isPreviewExpanded ? ConstrainedBox(constraints: BoxConstraints(maxHeight: isWideScreen ? 250 : 150), child: Padding(padding: const EdgeInsets.only(top: 8.0), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: kIsWeb ? (_selectedFile?.bytes != null ? Image.memory(_selectedFile!.bytes!, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Center(child: Text('Error (Web)'))) : const Center(child: Text('No disponible (Web)'))) : (_selectedFile?.path != null ? Image.file(File(_selectedFile!.path!), fit: BoxFit.contain, errorBuilder: (c, e, s) => const Center(child: Text('Error (Móvil)'))) : const Center(child: Text('No disponible (Móvil)')))))) : const SizedBox.shrink()),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Barra de Entrada
                Container(
                  padding: EdgeInsets.fromLTRB(isWideScreen ? 24.0 : 8.0, 8.0, isWideScreen ? 24.0 : 8.0, 16.0),
                  decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.5))),
                  child: ValueListenableBuilder<String>( // Usar ValueListenableBuilder
                    valueListenable: _textFieldValue,
                    builder: (context, textValue, child) {
                      bool canSendMessage = !_isLoading && (textValue.trim().isNotEmpty || _selectedFile != null);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(padding: const EdgeInsets.only(bottom: 8, right: 4), icon: const Icon(Icons.add_photo_alternate_outlined, size: 28), color: _isLoading ? Colors.grey : Colors.blue, tooltip: 'Seleccionar Imagen', onPressed: _isLoading ? null : _pickImage),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: InputDecoration(hintText: 'Pregunta sobre física...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide(color: Colors.blue.shade200, width: 1.5)), filled: true, fillColor: Colors.grey.shade100, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), isDense: true),
                              minLines: 1, maxLines: 5, textInputAction: TextInputAction.send,
                              onSubmitted: (value) { if (canSendMessage) _generateResponse(value.trim()); },
                              onChanged: (value) => _textFieldValue.value = value, // Actualizar notifier
                              keyboardType: TextInputType.multiline, enabled: !_isLoading, style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(padding: const EdgeInsets.only(bottom: 8, left: 4), icon: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, size: 28), tooltip: 'Enviar Mensaje', color: canSendMessage ? Colors.blue : Colors.grey, onPressed: canSendMessage ? () => _generateResponse(_controller.text.trim()) : null),
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
