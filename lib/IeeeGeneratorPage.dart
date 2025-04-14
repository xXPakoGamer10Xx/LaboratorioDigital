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

class IeeeGeneratorPage extends StatefulWidget {
  const IeeeGeneratorPage({super.key});

  @override
  State<IeeeGeneratorPage> createState() => _IeeeGeneratorPageState();
}

// --- NUEVO: Añadir WidgetsBindingObserver ---
class _IeeeGeneratorPageState extends State<IeeeGeneratorPage> with WidgetsBindingObserver {
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
      '¡Bienvenido! Soy tu experto en normas IEEE. Sube un PDF o haz una pregunta.';
  static const String _loginPromptMessageText =
      'Inicia sesión para guardar y ver tu historial.';
  static const String _systemPrompt = """
Eres un experto en las normas IEEE, con un profundo conocimiento de sus diversas secciones, cláusulas y requisitos. Tu función principal es analizar documentos relacionados con las normas IEEE que los usuarios proporcionen y responder preguntas específicas sobre esos documentos.

**Entrada del Usuario:**

El usuario puede proporcionar:

1. Un documento (en formato PDF) que pretende cumplir con una o varias normas IEEE.
2. Una pregunta de texto sobre una norma IEEE específica (sin subir un documento).
3. Ambas cosas: un documento Y una pregunta de texto relacionada.

**Instrucciones:**

* **Prioridad del Documento:** Si el usuario sube un documento, *todas* tus respuestas deben estar contextualizadas dentro de ese documento, a menos que el usuario haga explícitamente una pregunta general separada.
* **Análisis del Documento (Si se proporciona):**
    * Identifica la(s) norma(s) IEEE relevantes a las que el documento se refiere o intenta cumplir. Si el usuario no especifica la norma, intenta determinarla a partir del contenido del documento.
    * Analiza el documento para determinar si cumple con los requisitos de la(s) norma(s) identificada(s).
    * Identifica *específicamente* las secciones del documento que *no* cumplen con la(s) norma(s), proporcionando referencias precisas a las cláusulas relevantes de la norma IEEE (Número de norma, sección, cláusula). Sé *tan específico como sea posible*.
    * Sugiere modificaciones *concretas* al documento para que cumpla con la(s) norma(s). Las sugerencias deben ser claras, concisas y técnicamente precisas.
    * Si el documento es incompleto o faltan secciones clave según la norma IEEE, indica qué secciones faltan.
* **Preguntas Generales (Si no se proporciona un documento):**
    * Si el usuario hace una pregunta *general* sobre una norma IEEE (sin subir un documento), debes ser capaz de responderla basándote en tu conocimiento de la norma.
    * Cita *siempre* la sección y cláusula específica de la norma IEEE que respalda tu respuesta.
* **Si no se proporciona un archivo ni una pregunta relacionada con las normas IEEE:**
    * Si un usuario no sube un documento ni hace referencia a una norma IEEE o a algo relacionado con la norma, responde únicamente con: "Por favor, sube un documento PDF relacionado con las normas IEEE o haz una pregunta específica sobre una norma IEEE."
* **RESTRICCIÓN ABSOLUTA:** No respondas a preguntas que no estén directamente relacionadas con las normas IEEE. Si se te hace una pregunta fuera de este ámbito, responde únicamente con: "No puedo responder a esa pregunta, ya que está fuera de mi ámbito de especialización en las normas IEEE."

**Formato de Respuesta:**

* Sé claro, conciso y *extremadamente* preciso en tus referencias a las normas.
* Cita las normas IEEE de forma precisa: "Según **IEEE [Número de la norma]-[Versión], Sección [Número de sección], Cláusula [Número de cláusula]**..."
* **Para el análisis del documento (estructura sugerida):**
    * **Cumplimiento General:** (Opcional) Una breve declaración general sobre si el documento, en su conjunto, parece estar *intentando* cumplir con una norma.
    * **No Cumplimiento (Secciones Específicas):**
        * "En la página **[Número de página]**, sección **[Título de la sección del documento del usuario]**, **[Descripción del problema]**... Esto no cumple con **IEEE [Número de la norma]-[Versión], Sección [Número de sección], Cláusula [Número de cláusula]**, que establece: **[Cita textual de la norma]**."
        * "Sugerencia de modificación: **[Propuesta concreta, *específica* y *técnicamente precisa* para corregir el problema]**."
        * Repite este formato para *cada* área de no cumplimiento. Sé *exhaustivo*.
    * **Secciones Faltantes (si las hay):** "El documento no incluye una sección sobre **[Requisito de la norma]**, lo cual es requerido por **IEEE [Número de la norma]-[Versión], Sección [Número de sección], Cláusula [Número de cláusula]**."
* Si respondes una pregunta general (sin documento), cita la norma de forma precisa, usando negritas para resaltar la norma, sección y clausula.
* **Nota al pie (Disclaimer):** Agrega la siguiente nota al pie, en Markdown, *al final de cada respuesta*: \`*Descargo de responsabilidad: Esta información se proporciona solo con fines educativos y no constituye asesoramiento legal. Consulte a un profesional legal para obtener asesoramiento legal.*
""";

  @override
  void initState() {
    super.initState();
    print("IEEE Page - Auth State Init: ${_auth.currentUser?.uid}");
    _setChatIdBasedOnUser();
    print("IEEE Page - Initial Chat ID: $_chatId");
    _initializeModel();
    _textFieldValue.value = _controller.text;
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
          print("IEEE Page - App resumed, forcing UI redraw.");
        });
      }
    }
  }


  void _setChatIdBasedOnUser() {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      _chatId = currentUser.uid;
      print("IEEE Page - Authenticated User: ${currentUser.email}, Chat ID: $_chatId");
    } else {
      _chatId = null;
      print("IEEE Page - No authenticated user.");
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
        model: 'gemini-2.0-pro-exp-02-05',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.5,
          topK: 64,
          topP: 0.95,
          maxOutputTokens: 8192,
        ),
        systemInstruction: Content.text(_systemPrompt),
      );
      print("IEEE Page - Gemini model initialized.");
    } catch (e) {
      print("IEEE Page - Error initializing model: $e");
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
        .collection('ieee_messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Future<void> _saveMessageToFirestore(Map<String, dynamic> message) async {
    if (_chatId == null) return;
    // Evitar guardar mensajes del sistema locales (subida/eliminación de archivos)
    if (message['role'] == 'system' &&
        (message['text'].contains('subido:') || message['text'].contains('eliminado'))) {
      print("IEEE Page - Local UI message not saved: ${message['text']}");
      return;
    }
    try {
      final messageToSave = Map<String, dynamic>.from(message);
      // Remover datos que no van a Firestore
      messageToSave.remove('id');
      messageToSave.remove('pdfBytes'); // No guardar bytes de PDF en Firestore
      messageToSave.remove('mimeType');
      // Añadir timestamp del servidor
      messageToSave['timestamp'] = FieldValue.serverTimestamp();
      print("IEEE Page - Saving message to Firestore: ${messageToSave['role']}");
      await _firestore
          .collection('chats')
          .doc(_chatId)
          .collection('ieee_messages')
          .add(messageToSave);
    } catch (e) {
      print("IEEE Page - Error saving message: $e");
      // Considerar mostrar un SnackBar o manejar el error de forma visible
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
    // Validar que haya algo que enviar (texto o archivo)
    if (userPrompt.trim().isEmpty && _selectedFile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, ingresa una pregunta o selecciona un PDF.')),
        );
      }
      _scrollToBottom(jump: false);
      return;
    }

    setState(() => _isLoading = true);

    // --- Preparar Mensaje del Usuario ---
    Map<String, dynamic> userMessageForHistory = {
      'role': 'user',
      'text': userPrompt.trim(),
      'timestamp': DateTime.now(), // Usar DateTime local para UI inmediata
    };
    List<Part> partsForGemini = []; // Partes para enviar a la API

    Uint8List? pdfBytesForHistory; // Bytes para guardar temporalmente en historial local

    // Procesar archivo PDF si existe
    if (_selectedFile != null) {
      userMessageForHistory['fileName'] = _selectedFile!.name;
      try {
        Uint8List pdfBytes;
        if (kIsWeb) {
          if (_selectedFile!.bytes == null) throw Exception("Bytes de PDF no disponibles en web.");
          pdfBytes = _selectedFile!.bytes!;
        } else {
          if (_selectedFile!.path == null) throw Exception("Ruta de PDF no disponible en móvil.");
          pdfBytes = await File(_selectedFile!.path!).readAsBytes();
        }
        if (pdfBytes.isEmpty) throw Exception("El archivo PDF está vacío o corrupto.");

        String mimeType = 'application/pdf';
        partsForGemini.add(DataPart(mimeType, pdfBytes)); // Añadir PDF a la API
        pdfBytesForHistory = pdfBytes; // Guardar para UI
        // No añadir mimeType a userMessageForHistory, no es necesario para UI
      } catch (e) {
        print("IEEE Page - Error procesando PDF: $e");
        final err = {
          'role': 'system',
          'text': 'Error procesando PDF: $e',
          'timestamp': DateTime.now(),
        };
        if (mounted) {
          setState(() {
            _chatHistory.add(err);
            _isLoading = false;
            _selectedFile = null; // Limpiar archivo seleccionado en error
            _isPreviewExpanded = false;
          });
        }
        if (_chatId != null) _saveMessageToFirestore(err); // Guardar error si está autenticado
        _scrollToBottom(jump: false);
        return; // Detener ejecución
      }
    }

    // Añadir texto si existe
    if (userPrompt.trim().isNotEmpty) {
      partsForGemini.add(TextPart(userPrompt.trim()));
    }

    // Añadir bytes a historial local si hay PDF (para posible reintento o UI)
    if (pdfBytesForHistory != null) {
      userMessageForHistory['pdfBytes'] = pdfBytesForHistory;
      // userMessageForHistory['mimeType'] = mimeTypeForHistory; // No necesario para UI
    }

    // --- Actualizar UI y Guardar Mensaje del Usuario ---
    setState(() {
      _chatHistory.add(userMessageForHistory); // Añadir a UI
      _pendingUserMessage = null; // Limpiar mensaje pendiente
      _controller.clear(); // Limpiar campo de texto
      _textFieldValue.value = ''; // Limpiar notifier
    });
    _scrollToBottom(jump: false); // Desplazar hacia abajo

    // Guardar en Firestore si está autenticado (sin los bytes del PDF)
    if (_chatId != null) {
      final messageToSave = Map<String, dynamic>.from(userMessageForHistory);
      messageToSave.remove('pdfBytes'); // No guardar bytes
      messageToSave.remove('mimeType'); // No guardar mimeType
      await _saveMessageToFirestore(messageToSave);
    }

    // Si no hay partes para Gemini (no debería ocurrir con la validación inicial)
    if (partsForGemini.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // --- Llamada a la API de Gemini ---
    try {
      // Construir historial para la API (solo texto y referencias a archivos)
      List<Content> conversationHistoryForGemini = _chatHistory
          .where((msg) => msg['role'] == 'user' || msg['role'] == 'assistant') // Filtrar roles relevantes
          .map((msg) {
        // Crear el contenido para este mensaje
        List<Part> currentParts = [];
        // Añadir texto si existe
        if (msg['text'] != null && (msg['text'] as String).trim().isNotEmpty) {
          currentParts.add(TextPart(msg['text']));
        }
        // Añadir PDF si es mensaje de usuario y tiene bytes (solo para el último mensaje enviado)
        if (msg == userMessageForHistory && msg['pdfBytes'] != null) {
          currentParts.add(DataPart('application/pdf', msg['pdfBytes']));
        } else if (msg['fileName'] != null && msg['role'] == 'user') {
          // Para mensajes anteriores con archivo, solo indicar el nombre
          currentParts.add(TextPart("[Archivo adjunto: ${msg['fileName']}]"));
        }

        // Determinar el rol para Gemini ('user' o 'model')
        final role = msg['role'] == 'assistant' ? 'model' : 'user';

        // Crear el Content object si hay partes
        if (currentParts.isNotEmpty) {
          return Content(role, currentParts);
        } else {
          // Devolver un Content vacío si no hay partes (no debería pasar)
          return Content(role, [TextPart('')]);
        }
      }).toList();

      // Asegurarse de que el último mensaje enviado (con el PDF si lo hay) esté al final
      // (El mapeo anterior ya debería mantener el orden, pero esto es una doble verificación)
      // No es necesario reordenar si se mapea directamente desde _chatHistory que ya está ordenado.

      print("IEEE Page - Sending content to Gemini with history: ${conversationHistoryForGemini.length} items");
      // Enviar el historial completo a la API
      final response = await _model!.generateContent(conversationHistoryForGemini);


      print("IEEE Page - Response received: ${response.text}");
      final assistantMessage = {
        'role': 'assistant',
        'text': response.text ?? 'El asistente no proporcionó respuesta.',
        'timestamp': DateTime.now(), // Usar DateTime local para UI
      };

      // --- Actualizar UI y Guardar Respuesta del Asistente ---
      setState(() {
        _chatHistory.add(assistantMessage); // Añadir a UI
      });
      _scrollToBottom(jump: false); // Desplazar

      // Guardar en Firestore si está autenticado
      if (_chatId != null) await _saveMessageToFirestore(assistantMessage);

    } catch (e) {
      print("IEEE Page - Error generating response: $e");
      final err = {
        'role': 'system',
        'text': 'Error al contactar al asistente: $e',
        'timestamp': DateTime.now(),
      };
      if (mounted) setState(() => _chatHistory.add(err));
      if (_chatId != null) _saveMessageToFirestore(err); // Guardar error
    } finally {
      // --- Limpieza Final ---
      if (mounted) {
        setState(() {
          _isLoading = false; // Ocultar indicador de carga
          _selectedFile = null; // Limpiar archivo seleccionado después de enviar
          _isPreviewExpanded = false; // Ocultar previsualización
        });
        _scrollToBottom(jump: false); // Asegurar scroll al final
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      // --- Manejo de Permisos (Android) ---
      bool permissionGranted = false;
      if (!kIsWeb && Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        print("Android SDK: $sdkInt");
        PermissionStatus status;
        // Pedir permiso adecuado según versión de Android
        if (sdkInt >= 33) { // Android 13+
          status = await Permission.photos.request(); // Permiso más granular
        } else { // Android < 13
          status = await Permission.storage.request(); // Permiso de almacenamiento general
        }
        // Manejar caso de permiso denegado permanentemente
        if (status.isPermanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Permiso denegado permanentemente. Habilítalo en la configuración.'),
                action: SnackBarAction(label: 'Abrir Configuración', onPressed: openAppSettings), // Botón para ir a ajustes
              ),
            );
          }
          return; // No continuar si está denegado permanentemente
        }
        permissionGranted = status.isGranted; // Verificar si se concedió
        print("${sdkInt >= 33 ? 'Photos' : 'Storage'} Permission Granted: $permissionGranted");
      } else {
        permissionGranted = true; // Asumir permisos concedidos en otras plataformas (Web, iOS)
      }

      // Si no se concedió el permiso, mostrar mensaje y salir
      if (!permissionGranted) {
        print("Permiso denegado por el usuario.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso para acceder a archivos denegado.')),
          );
        }
        return;
      }

      // --- Selección de Archivo ---
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, // Tipo personalizado
        allowedExtensions: ['pdf'], // Solo permitir PDF
        allowMultiple: false, // Solo un archivo
        withData: kIsWeb, // Cargar bytes en Web
        // withReadStream: !kIsWeb, // Considerar stream para archivos grandes en móvil
      );

      // Si se seleccionó un archivo
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        // Validar tamaño del archivo (ej. 5MB)
        if (file.size > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('El PDF excede el límite de 5MB.')),
            );
          }
          return; // No procesar archivo grande
        }

        // Actualizar estado si el archivo es válido
        if (mounted) {
          setState(() {
            _selectedFile = file; // Guardar archivo seleccionado
            _isPreviewExpanded = true; // Mostrar previsualización
            // Añadir mensaje informativo local
            _chatHistory.add({
              'role': 'system',
              'text': 'PDF subido: ${file.name}',
              'timestamp': DateTime.now(),
            });
          });
          _scrollToBottom(jump: false); // Desplazar
          print("IEEE Page - PDF selected: ${_selectedFile?.name}");
        }
      } else {
        // Selección cancelada por el usuario
        print("IEEE Page - File selection cancelled.");
      }
    } catch (e) {
      // Manejo de errores durante la selección
      print("IEEE Page - Error picking file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar el PDF: $e')),
        );
      }
    }
  }

  void _removeFile() {
    if (mounted && _selectedFile != null) {
      setState(() {
        // Añadir mensaje informativo local
        _chatHistory.add({
          'role': 'system',
          'text': 'PDF eliminado: ${_selectedFile!.name}',
          'timestamp': DateTime.now(),
        });
        _selectedFile = null; // Limpiar archivo
        _isPreviewExpanded = false; // Ocultar previsualización
      });
      _scrollToBottom(jump: false); // Desplazar
      print("IEEE Page - Selected PDF removed.");
    }
  }

  Future<void> _clearChat() async {
    // Mostrar diálogo de confirmación
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar Chat IEEE'),
        content: const Text('¿Estás seguro de que quieres borrar todo el historial de este chat? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Cancelar
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Confirmar
            child: const Text('Limpiar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return; // Si el usuario cancela

    if (mounted) setState(() => _isLoading = true); // Mostrar indicador

    // Mensaje de bienvenida a restaurar
    final welcomeMessage = {
      'role': 'assistant',
      'text': _chatId != null ? _initialWelcomeMessageText : _loginPromptMessageText,
      'timestamp': DateTime.now(),
    };

    if (_chatId != null) {
      // Usuario autenticado: Limpiar Firestore
      print("IEEE Page - Clearing Firestore for $_chatId/ieee_messages...");
      try {
        final ref = _firestore.collection('chats').doc(_chatId).collection('ieee_messages');
        // Borrar en lotes
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
        print("IEEE Page - Firestore history cleared.");

        // Guardar mensaje de bienvenida en Firestore
        await _saveMessageToFirestore(welcomeMessage);

        // Actualizar UI local
        if (mounted) {
          setState(() {
            _chatHistory = [welcomeMessage];
            _isLoading = false;
            _initialScrollExecuted = false; // Permitir scroll inicial
          });
        }
        _scrollToBottom(jump: true); // Ir al mensaje de bienvenida

      } catch (e) {
        print("IEEE Page - Error clearing Firestore: $e");
        final err = {
          'role': 'system',
          'text': 'Error limpiando historial nube: $e',
          'timestamp': DateTime.now(),
        };
        if (mounted) {
          setState(() {
            _chatHistory = [err, welcomeMessage]; // Mostrar error y bienvenida
            _isLoading = false;
          });
        }
        _scrollToBottom(jump: true);
      }
    } else {
      // Usuario no autenticado: Limpiar solo localmente
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
    // 1. Filtrar mensajes relevantes
    final downloadableHistory = _chatHistory.where((msg) {
      final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
      final text = msg['text'] ?? '';
      if (role == 'SYSTEM' && (text.contains('subido:') || text.contains('eliminado') || text.contains('inicializada') || text.contains('Error:'))) {
        return false;
      }
      if (role == 'ASSISTANT' && (text == _initialWelcomeMessageText || text == _loginPromptMessageText)) {
        return false;
      }
      return true;
    }).toList();

    // 2. Verificar si hay mensajes de usuario
    final hasUserMessages = _chatHistory.any((msg) =>
    msg['role'] == 'user' &&
        (msg['text']?.toString().trim().isNotEmpty == true || msg['fileName'] != null));

    // 3. Bloquear en Android si no hay mensajes de usuario
    if (!kIsWeb && Platform.isAndroid && !hasUserMessages) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay preguntas o archivos enviados para descargar.'),
          ),
        );
      }
      return;
    }

    // 4. Si no hay historial relevante después de filtrar
    if (downloadableHistory.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay historial relevante para descargar.'),
          ),
        );
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true); // Mostrar carga

    try {
      // 5. Crear contenido del archivo
      final StringBuffer buffer = StringBuffer();
      buffer.writeln("Historial del Chat IEEE");
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
            timestampStr = formatter.format(DateTime.now().toLocal()); // Fallback
          }
        } catch (e) {
          print("Error formateando timestamp para descarga: $e");
          timestampStr = formatter.format(DateTime.now().toLocal()); // Fallback
        }

        buffer.writeln("[$timestampStr] $role:");
        buffer.writeln(text);
        if (message['fileName'] != null) {
          buffer.writeln("  [Archivo adjunto: ${message['fileName']}]");
        }
        buffer.writeln("-" * 20);
      }

      // 6. Preparar y guardar/descargar
      final String fileContent = buffer.toString();
      final String fileName = 'historial_ieee_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
      final List<int> fileBytes = utf8.encode(fileContent);

      if (kIsWeb) {
        // Descarga Web
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
        // Guardar Móvil/Escritorio
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Historial IEEE',
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
      print("Error general al descargar (IEEE): $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al preparar la descarga: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false); // Ocultar carga
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _textFieldValue.dispose();
    // --- NUEVO: Remover el observador ---
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
          // Solo animar si no estamos ya cerca del final
          if ((maxExtent - _scrollController.position.pixels).abs() > 50) {
            _scrollController.animateTo(
              maxExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        }
      } else {
        // Reintentar si no hay clientes
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
        // Determinar si se puede descargar
        bool hasDownloadableContent = !_isLoading && _chatHistory.any((msg) {
          final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
          final text = msg['text'] ?? '';
          if (role == 'SYSTEM' && (text.contains('subido:') || text.contains('eliminado') || text.contains('Error:'))) return false;
          if (role == 'ASSISTANT' && (text == _initialWelcomeMessageText || text == _loginPromptMessageText)) return false;
          return true;
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text('Experto Normas IEEE'),
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
                // Área del Chat
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _getChatStream(),
                    builder: (context, snapshot) {
                      // --- Manejo de Estados ---
                      if (snapshot.connectionState == ConnectionState.waiting && _chatId != null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        print("IEEE Page - StreamBuilder Error: ${snapshot.error}");
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

                      // --- Procesamiento de Mensajes ---
                      final List<Map<String, dynamic>> messagesFromStream;
                      if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                        messagesFromStream = snapshot.data!.docs.map((doc) {
                          final data = doc.data();
                          data['id'] = doc.id;
                          if (data['timestamp'] is Timestamp) {
                            data['timestamp'] = (data['timestamp'] as Timestamp).toDate();
                          } else if (data['timestamp'] is! DateTime) {
                            data['timestamp'] = DateTime.now(); // Fallback
                          }
                          return data;
                        }).toList();
                        _chatHistory = messagesFromStream; // Sincronizar
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

                      // --- Scroll Automático ---
                      final currentMessageCount = allMessages.length;
                      if (currentMessageCount > 0 && !_initialScrollExecuted) {
                        print("IEEE Page - Initial load ($currentMessageCount messages).");
                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: true));
                        _initialScrollExecuted = true;
                      } else if (currentMessageCount > _previousMessageCount && _initialScrollExecuted) {
                        print("IEEE Page - New message ($currentMessageCount > $_previousMessageCount).");
                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: false));
                      }
                      _previousMessageCount = currentMessageCount;

                      // --- Lista de Mensajes ---
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
                            // final pdfBytes = message['pdfBytes'] as Uint8List?; // No necesitamos mostrar PDF en burbuja
                            final isUser = role == 'user';
                            final isSystem = role == 'system';

                            final key = ValueKey(message['id'] ?? message['timestamp'].toString());

                            // --- Estilos ---
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
                            } else { // Assistant
                              backgroundColor = Colors.grey[200]!;
                              textColor = Colors.black87;
                              alignment = Alignment.centerLeft;
                              textAlign = TextAlign.left;
                              crossAxisAlignment = CrossAxisAlignment.start;
                            }

                            // Ocultar mensajes internos
                            if (isSystem && (text.contains('subido:') || text.contains('eliminado'))) {
                              return const SizedBox.shrink();
                            }

                            // --- Burbuja ---
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
                                    // Mostrar referencia a PDF si es mensaje de usuario y tiene archivo
                                    if (isUser && fileName != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.picture_as_pdf_outlined, size: 16, color: textColor.withOpacity(0.8)),
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
                                      ),
                                    // Mostrar texto
                                    if (text.isNotEmpty)
                                      (role == 'assistant')
                                          ? MarkdownBody( // Usar Markdown para asistente
                                        data: text,
                                        selectable: true,
                                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                          p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor, height: 1.4),
                                          code: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', backgroundColor: Colors.black12, color: textColor),
                                        ),
                                      )
                                          : SelectableText( // Texto normal para usuario/sistema
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

                // Previsualización de PDF Seleccionado
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
                                Icon(Icons.picture_as_pdf_outlined, color: Colors.red[700], size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_selectedFile!.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                                // Botón Mostrar/Ocultar (simplificado, ya que no hay preview real de PDF)
                                // TextButton(
                                //   style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                //   onPressed: () => setState(() => _isPreviewExpanded = !_isPreviewExpanded),
                                //   child: Text(_isPreviewExpanded ? 'Ocultar' : 'Mostrar', style: const TextStyle(color: Colors.teal, fontSize: 13)),
                                // ),
                                TextButton(
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: _isLoading ? null : _removeFile,
                                  child: Text('Eliminar', style: TextStyle(color: _isLoading ? Colors.grey : Colors.red, fontSize: 13)),
                                ),
                              ],
                            ),
                            // No mostrar AnimatedSize para PDF, ya que no hay previsualización
                            // AnimatedSize(
                            //   duration: const Duration(milliseconds: 300),
                            //   curve: Curves.easeInOut,
                            //   child: _isPreviewExpanded
                            //       ? ConstrainedBox(
                            //           constraints: BoxConstraints(maxHeight: isWideScreen ? 250 : 150),
                            //           child: Padding(
                            //             padding: const EdgeInsets.only(top: 8.0),
                            //             child: Text('Vista previa no disponible para PDF en esta plataforma'), // Mensaje informativo
                            //           ),
                            //         )
                            //       : const SizedBox.shrink(),
                            // ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Barra de Entrada
                Container(
                  padding: EdgeInsets.fromLTRB(isWideScreen ? 24.0 : 8.0, 8.0, isWideScreen ? 24.0 : 8.0, 16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                  ),
                  child: ValueListenableBuilder<String>(
                    valueListenable: _textFieldValue,
                    builder: (context, textValue, child) {
                      // Determinar si se puede enviar
                      bool canSendMessage = !_isLoading && (textValue.trim().isNotEmpty || _selectedFile != null);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Botón Adjuntar PDF
                          IconButton(
                            padding: const EdgeInsets.only(bottom: 8, right: 4),
                            icon: const Icon(Icons.upload_file_outlined, size: 28),
                            color: _isLoading ? Colors.grey : Colors.teal,
                            tooltip: 'Seleccionar PDF',
                            onPressed: _isLoading ? null : _pickFile,
                          ),
                          // Campo de Texto
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: InputDecoration(
                                hintText: 'Pregunta sobre normas IEEE...',
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
                                _textFieldValue.value = value; // Actualizar notifier
                                _scrollToBottom(jump: false); // Scroll al escribir
                              },
                              keyboardType: TextInputType.multiline,
                              enabled: !_isLoading,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botón Enviar
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
