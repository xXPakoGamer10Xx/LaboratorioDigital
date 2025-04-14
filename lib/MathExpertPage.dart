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

// --- NUEVO: Añadir WidgetsBindingObserver ---
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
    List<Part> partsForGemini = [];

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
        else if (extension == 'heic') mimeType = 'image/heic';

        partsForGemini.add(DataPart(mimeType, imageBytes));
        imageBytesForHistory = imageBytes;
        mimeTypeForHistory = mimeType;
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

    if (userPrompt.trim().isNotEmpty) {
      partsForGemini.add(TextPart(userPrompt.trim()));
    }

    if (imageBytesForHistory != null) {
      userMessageForHistory['imageBytes'] = imageBytesForHistory;
      userMessageForHistory['mimeType'] = mimeTypeForHistory;
    }

    setState(() {
      _chatHistory.add(userMessageForHistory);
      _pendingUserMessage = null;
      _controller.clear();
      _textFieldValue.value = ''; // Limpiar valor del notifier también
    });
    _scrollToBottom(jump: false);

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

    try {
      List<Content> conversationHistoryForGemini = _chatHistory
          .where((msg) => msg['role'] == 'user' || msg['role'] == 'assistant')
          .map((msg) {
        List<Part> currentParts = [];
        // Añadir texto si existe
        if (msg['text'] != null && (msg['text'] as String).trim().isNotEmpty) {
          currentParts.add(TextPart(msg['text']));
        }
        // Añadir imagen si existe (solo para mensajes del usuario)
        if (msg['role'] == 'user' && msg['imageBytes'] != null && msg['mimeType'] != null) {
          currentParts.add(DataPart(msg['mimeType'], msg['imageBytes']));
        }
        // Determinar el rol para Gemini
        final role = msg['role'] == 'assistant' ? 'model' : 'user';
        // Crear el Content object
        if (currentParts.isNotEmpty) {
          return Content(role, currentParts);
        } else {
          // Manejar caso donde no hay partes (aunque no debería ocurrir con la lógica actual)
          return Content(role, [TextPart('')]); // Enviar texto vacío si no hay nada más
        }
      }).toList();


      print("Math Page - Sending content to Gemini with history: ${conversationHistoryForGemini.length} items");
      final response = await _model!.generateContent(conversationHistoryForGemini); // Enviar el historial directamente


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
      final err = {
        'role': 'system',
        'text': 'Error al contactar al asistente: $e',
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
        withData: kIsWeb, // Cargar bytes directamente en web
        // withReadStream: !kIsWeb, // Usar stream en móvil si los archivos son grandes (opcional)
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        if (file.size > 5 * 1024 * 1024) { // Límite de 5MB
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('La imagen excede el límite de 5MB.')),
            );
          }
          return;
        }

        if (mounted) {
          setState(() {
            _selectedFile = file;
            _isPreviewExpanded = true; // Mostrar previsualización por defecto
            // Añadir mensaje informativo al historial local (no se guarda en Firestore)
            _chatHistory.add({
              'role': 'system',
              'text': 'Imagen subida: ${file.name}',
              'timestamp': DateTime.now(),
            });
          });
          _scrollToBottom(jump: false); // Desplazar hacia abajo
          print("Math Page - Image selected: ${_selectedFile?.name}");
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
        // Añadir mensaje informativo al historial local
        _chatHistory.add({
          'role': 'system',
          'text': 'Imagen eliminada: ${_selectedFile!.name}',
          'timestamp': DateTime.now(),
        });
        _selectedFile = null;
        _isPreviewExpanded = false; // Ocultar previsualización
      });
      _scrollToBottom(jump: false); // Desplazar hacia abajo
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

    if (confirm != true) return; // Si el usuario cancela

    if (mounted) setState(() => _isLoading = true); // Mostrar indicador de carga

    // Mensaje de bienvenida a añadir después de limpiar
    final welcomeMessage = {
      'role': 'assistant',
      'text': _chatId != null ? _initialWelcomeMessageText : _loginPromptMessageText,
      'timestamp': DateTime.now(), // Usar DateTime local para el mensaje inicial
    };

    if (_chatId != null) {
      // Usuario autenticado: Limpiar Firestore
      print("Math Page - Clearing Firestore for $_chatId/math_messages...");
      try {
        final ref = _firestore.collection('chats').doc(_chatId).collection('math_messages');
        // Borrar en lotes para evitar problemas con colecciones grandes
        QuerySnapshot snapshot;
        int deletedCount = 0;
        do {
          snapshot = await ref.limit(100).get(); // Obtener hasta 100 docs
          if (snapshot.docs.isNotEmpty) {
            final batch = _firestore.batch();
            for (var doc in snapshot.docs) {
              batch.delete(doc.reference); // Añadir borrado al lote
            }
            await batch.commit(); // Ejecutar el lote
            deletedCount += snapshot.docs.length;
            print("Lote de ${snapshot.docs.length} mensajes borrado (total: $deletedCount).");
          }
        } while (snapshot.docs.isNotEmpty); // Repetir si aún quedan documentos

        print("Math Page - Firestore history cleared.");

        // Guardar el mensaje de bienvenida inicial en Firestore
        await _saveMessageToFirestore(welcomeMessage);

        // Actualizar UI local solo después de confirmar el borrado y guardado
        if (mounted) {
          setState(() {
            _chatHistory = [welcomeMessage]; // Reiniciar historial local
            _isLoading = false; // Ocultar indicador
            _initialScrollExecuted = false; // Permitir scroll inicial de nuevo
          });
        }
        _scrollToBottom(jump: true); // Ir al final (al mensaje de bienvenida)

      } catch (e) {
        print("Math Page - Error clearing Firestore: $e");
        final err = {
          'role': 'system',
          'text': 'Error limpiando historial nube: $e',
          'timestamp': DateTime.now(),
        };
        if (mounted) {
          setState(() {
            // Mostrar error y mensaje de bienvenida
            _chatHistory = [err, welcomeMessage];
            _isLoading = false;
          });
        }
        _scrollToBottom(jump: true);
      }
    } else {
      // Usuario no autenticado: Limpiar solo historial local
      if (mounted) {
        setState(() {
          _chatHistory = [welcomeMessage]; // Reiniciar historial local
          _isLoading = false; // Ocultar indicador
        });
      }
      _scrollToBottom(jump: true);
    }
  }

  Future<void> _downloadHistory() async {
    // 1. Filtrar mensajes relevantes para la descarga
    final downloadableHistory = _chatHistory.where((msg) {
      final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
      final text = msg['text'] ?? '';
      // Excluir mensajes del sistema internos
      if (role == 'SYSTEM' && (text.contains('subida:') || text.contains('eliminada:') || text.contains('inicializada') || text.contains('Error:'))) {
        return false;
      }
      // Excluir mensajes iniciales de bienvenida/login
      if (role == 'ASSISTANT' && (text == _initialWelcomeMessageText || text == _loginPromptMessageText)) {
        return false;
      }
      return true; // Incluir mensajes de usuario y respuestas del asistente
    }).toList();

    // 2. Verificar si hay mensajes del usuario (texto o imagen)
    final hasUserMessages = _chatHistory.any((msg) =>
    msg['role'] == 'user' &&
        (msg['text']?.toString().trim().isNotEmpty == true || msg['fileName'] != null)
    );

    // 3. En Android, bloquear la descarga si no hay mensajes del usuario
    //    (Evita descargar solo el mensaje de bienvenida si no se ha interactuado)
    if (!kIsWeb && Platform.isAndroid && !hasUserMessages) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay preguntas enviadas para descargar.'),
          ),
        );
      }
      return;
    }


    // 4. Si no hay mensajes *relevantes* para descargar (después de filtrar)
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
      // 5. Crear el contenido del archivo de texto
      final StringBuffer buffer = StringBuffer();
      buffer.writeln("Historial del Chat de Matemáticas");
      buffer.writeln("=" * 30);
      buffer.writeln("Exportado el: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now().toLocal())}");
      buffer.writeln(); // Línea en blanco

      final DateFormat formatter = DateFormat('yyyy-MM-dd HH:mm:ss');

      for (final message in downloadableHistory) {
        final role = message['role']?.toString().toUpperCase() ?? 'SYSTEM';
        final text = message['text'] ?? '';
        dynamic ts = message['timestamp']; // Puede ser Timestamp o DateTime
        String timestampStr = 'N/A';

        // Formatear timestamp de forma segura
        try {
          if (ts is Timestamp) {
            timestampStr = formatter.format(ts.toDate().toLocal());
          } else if (ts is DateTime) {
            timestampStr = formatter.format(ts.toLocal());
          } else {
            // Fallback por si acaso (no debería ocurrir)
            timestampStr = formatter.format(DateTime.now().toLocal());
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
        buffer.writeln("-" * 20); // Separador
      }

      // 6. Preparar y guardar/descargar el archivo
      final String fileContent = buffer.toString();
      final String fileName = 'historial_matematicas_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
      final List<int> fileBytes = utf8.encode(fileContent); // Convertir a bytes UTF-8

      if (kIsWeb) {
        // Descarga en Web usando dart:html
        final blob = html.Blob([fileBytes], 'text/plain', 'native');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click(); // Simular clic para descargar
        html.Url.revokeObjectUrl(url); // Liberar memoria
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Descarga iniciada (Web).')),
          );
        }
      } else {
        // Guardar archivo en Móvil/Escritorio usando file_picker
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Historial Matemáticas',
          fileName: fileName,
          bytes: Uint8List.fromList(fileBytes), // file_picker necesita Uint8List
        );

        if (outputFile == null) {
          // Usuario canceló el guardado
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Guardado cancelado.')),
            );
          }
        } else {
          // Archivo guardado exitosamente
          if (mounted) {
            // Extraer solo el nombre del archivo de la ruta completa
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
    // Usar addPostFrameCallback para asegurar que el layout esté completo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Verificar si el controlador tiene clientes (está adjunto a un Scrollable)
      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        if (jump) {
          // Saltar directamente al final (útil para carga inicial)
          _scrollController.jumpTo(maxExtent);
        } else {
          // Animar suavemente hasta el final (útil para nuevos mensajes)
          _scrollController.animateTo(
            maxExtent,
            duration: const Duration(milliseconds: 300), // Duración de la animación
            curve: Curves.easeOut, // Curva de animación
          );
        }
      } else {
        // Si no hay clientes aún, reintentar después de un breve retraso
        // Esto puede pasar si se llama antes de que el ListView esté completamente construido
        Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom(jump: jump));
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder( // Usar LayoutBuilder para adaptar a diferentes anchos
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 720; // Definir punto de corte para pantalla ancha
        double chatBubbleMaxWidth = isWideScreen ? 600 : constraints.maxWidth * 0.85; // Ancho máximo de burbuja
        // Determinar si se puede descargar (no cargando y hay contenido relevante)
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
            elevation: 1, // Sombra sutil
            leading: IconButton( // Botón para volver atrás
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.canPop(context) ? Navigator.pop(context) : null,
            ),
            actions: [
              // Botón Descargar Historial
              IconButton(
                icon: const Icon(Icons.download_outlined),
                onPressed: hasDownloadableContent ? _downloadHistory : null, // Habilitar solo si hay contenido
                tooltip: 'Descargar historial',
                color: hasDownloadableContent ? null : Colors.grey, // Color gris si está deshabilitado
              ),
              // Botón Limpiar Chat
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _isLoading ? null : _clearChat, // Deshabilitar si está cargando
                tooltip: 'Limpiar chat',
                color: _isLoading ? Colors.grey : null, // Color gris si está deshabilitado
              ),
            ],
          ),
          body: SafeArea( // Asegura que el contenido no se solape con barras del sistema
            child: Column(
              children: [
                // Área del Chat (Expandida)
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _getChatStream(), // Escuchar mensajes de Firestore si está autenticado
                    builder: (context, snapshot) {
                      // --- Manejo de Estados del Stream ---
                      // Esperando conexión o carga inicial de Firestore
                      if (snapshot.connectionState == ConnectionState.waiting && _chatId != null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      // Error en el stream
                      if (snapshot.hasError) {
                        print("Math Page - StreamBuilder Error: ${snapshot.error}");
                        return Center(child: Text('Error al cargar mensajes: ${snapshot.error}'));
                      }
                      // Usuario no autenticado (no hay stream)
                      if (_chatId == null) {
                        // Si el historial local está vacío, añadir mensaje de login
                        if (_chatHistory.isEmpty) {
                          _chatHistory.add({
                            'role': 'assistant',
                            'text': _loginPromptMessageText,
                            'timestamp': DateTime.now(),
                          });
                        }
                        // No hacer nada más, se usará _chatHistory local
                      }

                      // --- Procesamiento de Mensajes ---
                      final List<Map<String, dynamic>> messagesFromStream;
                      if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                        // Datos recibidos de Firestore
                        messagesFromStream = snapshot.data!.docs.map((doc) {
                          final data = doc.data();
                          data['id'] = doc.id; // Añadir ID del documento
                          // Convertir Timestamp a DateTime si es necesario
                          if (data['timestamp'] is Timestamp) {
                            data['timestamp'] = (data['timestamp'] as Timestamp).toDate();
                          } else if (data['timestamp'] is! DateTime) {
                            data['timestamp'] = DateTime.now(); // Fallback
                          }
                          return data;
                        }).toList();
                        // Sincronizar historial local con Firestore
                        _chatHistory = messagesFromStream;
                      } else {
                        // No hay datos en Firestore (o usuario no autenticado)
                        messagesFromStream = [];
                        // Si el historial local está vacío (y no es el caso de login), añadir bienvenida
                        if (_chatHistory.isEmpty && _chatId != null) {
                          _chatHistory.add({
                            'role': 'assistant',
                            'text': _initialWelcomeMessageText,
                            'timestamp': DateTime.now(),
                          });
                        }
                        // Si _chatId es null, el mensaje de login ya se añadió arriba
                      }

                      // Combinar historial con mensaje pendiente (si existe)
                      final allMessages = [..._chatHistory];
                      if (_pendingUserMessage != null) {
                        allMessages.add(_pendingUserMessage!);
                        // Reordenar por si acaso (aunque normalmente se añade al final)
                        allMessages.sort((a, b) {
                          DateTime aTime = a['timestamp'] is Timestamp ? (a['timestamp'] as Timestamp).toDate() : a['timestamp'] as DateTime;
                          DateTime bTime = b['timestamp'] is Timestamp ? (b['timestamp'] as Timestamp).toDate() : b['timestamp'] as DateTime;
                          return aTime.compareTo(bTime);
                        });
                      }

                      // --- Lógica de Scroll Automático ---
                      final currentMessageCount = allMessages.length;
                      // Scroll inicial al cargar por primera vez
                      if (currentMessageCount > 0 && !_initialScrollExecuted) {
                        print("Math Page - Initial load ($currentMessageCount messages).");
                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: true));
                        _initialScrollExecuted = true;
                      }
                      // Scroll suave para nuevos mensajes
                      else if (currentMessageCount > _previousMessageCount && _initialScrollExecuted) {
                        print("Math Page - New message ($currentMessageCount > $_previousMessageCount).");
                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: false));
                      }
                      _previousMessageCount = currentMessageCount; // Actualizar contador


                      // --- Construcción de la Lista de Mensajes ---
                      return AnimatedSwitcher( // Animación suave al cambiar la lista
                        duration: const Duration(milliseconds: 300),
                        child: ListView.builder(
                          key: ValueKey(allMessages.length), // Key para forzar reconstrucción en AnimatedSwitcher
                          controller: _scrollController, // Controlador para scroll
                          padding: EdgeInsets.symmetric(horizontal: isWideScreen ? 24.0 : 16.0, vertical: 16.0), // Padding adaptable
                          itemCount: allMessages.length,
                          itemBuilder: (context, index) {
                            final message = allMessages[index];
                            final role = message['role'] as String? ?? 'system';
                            final text = message['text'] as String? ?? '';
                            final fileName = message['fileName'] as String?;
                            final imageBytes = message['imageBytes'] as Uint8List?; // Bytes para mostrar imagen
                            final isUser = role == 'user';
                            final isSystem = role == 'system'; // Mensajes del sistema (errores, etc.)

                            // Key única para cada elemento, ayuda a Flutter a optimizar
                            final key = ValueKey(message['id'] ?? message['timestamp'].toString());

                            // --- Estilos y Alineación por Rol ---
                            Color backgroundColor;
                            Color textColor;
                            Alignment alignment;
                            TextAlign textAlign;
                            CrossAxisAlignment crossAxisAlignment; // Alineación vertical dentro de la burbuja

                            if (isUser) {
                              backgroundColor = Colors.teal[100]!;
                              textColor = Colors.teal[900]!;
                              alignment = Alignment.centerRight; // A la derecha
                              textAlign = TextAlign.left; // Texto alineado a la izquierda dentro de la burbuja
                              crossAxisAlignment = CrossAxisAlignment.start;
                            } else if (isSystem) {
                              backgroundColor = Colors.orange[100]!;
                              textColor = Colors.orange[900]!;
                              alignment = Alignment.center; // Centrado
                              textAlign = TextAlign.center;
                              crossAxisAlignment = CrossAxisAlignment.center;
                            } else { // Assistant
                              backgroundColor = Colors.grey[200]!;
                              textColor = Colors.black87;
                              alignment = Alignment.centerLeft; // A la izquierda
                              textAlign = TextAlign.left;
                              crossAxisAlignment = CrossAxisAlignment.start;
                            }

                            // Ocultar mensajes internos del sistema de subida/eliminación
                            if (isSystem && (text.contains('subida:') || text.contains('eliminada:'))) {
                              return const SizedBox.shrink(); // No mostrar nada
                            }


                            // --- Construcción de la Burbuja del Mensaje ---
                            return Align( // Alinear la burbuja completa
                              key: key,
                              alignment: alignment,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 5.0), // Margen vertical
                                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0), // Padding interno
                                decoration: BoxDecoration(
                                  color: backgroundColor,
                                  borderRadius: BorderRadius.circular(16.0), // Bordes redondeados
                                  boxShadow: [ // Sombra sutil
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.2),
                                      spreadRadius: 1,
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                constraints: BoxConstraints(maxWidth: chatBubbleMaxWidth), // Ancho máximo
                                child: Column( // Para poner imagen y texto verticalmente si es necesario
                                  crossAxisAlignment: crossAxisAlignment,
                                  mainAxisSize: MainAxisSize.min, // Ajustar tamaño al contenido
                                  children: [
                                    // Mostrar imagen si es mensaje de usuario y tiene imagen
                                    if (isUser && fileName != null && imageBytes != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Nombre del archivo
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.image_outlined, size: 16, color: textColor.withOpacity(0.8)),
                                                const SizedBox(width: 4),
                                                Flexible( // Para que el texto no se desborde
                                                  child: Text(
                                                    fileName,
                                                    style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: textColor.withOpacity(0.8)),
                                                    overflow: TextOverflow.ellipsis, // Poner puntos suspensivos si es largo
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            // Previsualización de la imagen
                                            ClipRRect( // Para redondear esquinas de la imagen
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.memory(
                                                imageBytes,
                                                fit: BoxFit.contain, // Ajustar sin distorsionar
                                                height: 100, // Altura fija para la previsualización
                                                // Manejo de error si la imagen no carga
                                                errorBuilder: (c, e, s) => const Text('Error al mostrar imagen'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Mostrar texto si existe
                                    if (text.isNotEmpty)
                                      (role == 'assistant') // Usar Markdown para respuestas del asistente
                                          ? MarkdownBody(
                                        data: text,
                                        selectable: true, // Permitir seleccionar texto
                                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                          // Estilos personalizados para Markdown
                                          p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor, height: 1.4), // Estilo de párrafo
                                          code: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', backgroundColor: Colors.black12, color: textColor), // Estilo de código
                                        ),
                                      )
                                          : SelectableText( // Texto normal seleccionable para usuario y sistema
                                        text,
                                        textAlign: textAlign,
                                        style: TextStyle(
                                          color: textColor,
                                          fontStyle: isSystem ? FontStyle.italic : FontStyle.normal, // Cursiva para sistema
                                          fontSize: isSystem ? 13 : 16, // Tamaño diferente para sistema
                                          height: 1.4, // Espaciado de línea
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

                // Previsualización de Imagen Seleccionada (si existe)
                if (_selectedFile != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(isWideScreen ? 24.0 : 8.0, 0, isWideScreen ? 24.0 : 8.0, 8.0), // Padding adaptable
                    child: Card( // Usar Card para darle un fondo y elevación
                      elevation: 2,
                      margin: EdgeInsets.zero, // Sin margen externo adicional
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // Bordes redondeados
                      child: Padding(
                        padding: const EdgeInsets.all(8.0), // Padding interno
                        child: Column(
                          children: [
                            // Fila con icono, nombre y botones
                            Row(
                              children: [
                                Icon(Icons.image_outlined, color: Colors.teal, size: 20), // Icono
                                const SizedBox(width: 8),
                                Expanded(child: Text(_selectedFile!.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))), // Nombre (con elipsis)
                                // Botón Mostrar/Ocultar
                                TextButton(
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: () => setState(() => _isPreviewExpanded = !_isPreviewExpanded), // Alternar visibilidad
                                  child: Text(_isPreviewExpanded ? 'Ocultar' : 'Mostrar', style: const TextStyle(color: Colors.teal, fontSize: 13)),
                                ),
                                // Botón Eliminar
                                TextButton(
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: _isLoading ? null : _removeImage, // Deshabilitar si está cargando
                                  child: Text('Eliminar', style: TextStyle(color: _isLoading ? Colors.grey : Colors.red, fontSize: 13)),
                                ),
                              ],
                            ),
                            // Contenedor animado para la previsualización
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: _isPreviewExpanded // Mostrar solo si está expandido
                                  ? ConstrainedBox( // Limitar altura máxima
                                constraints: BoxConstraints(maxHeight: isWideScreen ? 250 : 150), // Altura adaptable
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8.0), // Espacio arriba
                                  child: ClipRRect( // Redondear imagen
                                    borderRadius: BorderRadius.circular(8),
                                    child: kIsWeb // Diferente lógica para Web y Móvil
                                        ? (_selectedFile?.bytes != null // Mostrar desde bytes en Web
                                        ? Image.memory(_selectedFile!.bytes!, fit: BoxFit.contain, errorBuilder: (c,e,s) => const Center(child: Text('Error al mostrar imagen (Web)')))
                                        : const Center(child: Text('Vista previa no disponible (Web)')))
                                        : (_selectedFile?.path != null // Mostrar desde ruta en Móvil
                                        ? Image.file(File(_selectedFile!.path!), fit: BoxFit.contain, errorBuilder: (c,e,s) => const Center(child: Text('Error al mostrar imagen (Móvil)')))
                                        : const Center(child: Text('Vista previa no disponible (Móvil)'))),
                                  ),
                                ),
                              )
                                  : const SizedBox.shrink(), // Ocultar si no está expandido
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Barra de Entrada de Texto y Botones
                Container(
                  padding: EdgeInsets.fromLTRB(isWideScreen ? 24.0 : 8.0, 8.0, isWideScreen ? 24.0 : 8.0, 16.0), // Padding adaptable
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor, // Color de fondo
                    border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.5)), // Borde superior sutil
                  ),
                  child: ValueListenableBuilder<String>( // Escuchar cambios en el TextField para habilitar/deshabilitar botón
                    valueListenable: _textFieldValue,
                    builder: (context, textValue, child) {
                      // Determinar si se puede enviar el mensaje
                      bool canSendMessage = !_isLoading && (textValue.trim().isNotEmpty || _selectedFile != null);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end, // Alinear botones y campo de texto abajo
                        children: [
                          // Botón para adjuntar imagen
                          IconButton(
                            padding: const EdgeInsets.only(bottom: 8, right: 4), // Ajuste fino del padding
                            icon: const Icon(Icons.add_photo_alternate_outlined, size: 28),
                            color: _isLoading ? Colors.grey : Colors.teal, // Color adaptable
                            tooltip: 'Seleccionar Imagen',
                            onPressed: _isLoading ? null : _pickImage, // Deshabilitar si está cargando
                          ),
                          // Campo de texto expandido
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: InputDecoration(
                                hintText: 'Escribe tu pregunta aquí...',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide.none), // Sin borde por defecto
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide(color: Colors.teal.shade200, width: 1.5)), // Borde al enfocar
                                filled: true,
                                fillColor: Colors.grey.shade100, // Fondo gris claro
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Padding interno
                                isDense: true, // Hacerlo más compacto
                              ),
                              minLines: 1, // Mínimo 1 línea
                              maxLines: 5, // Máximo 5 líneas antes de scroll
                              textInputAction: TextInputAction.send, // Acción de teclado "Enviar"
                              onSubmitted: (value) { // Enviar al presionar "Enviar" en teclado
                                if (canSendMessage) _generateResponse(value.trim());
                              },
                              onChanged: (value) {
                                _textFieldValue.value = value; // Actualizar notifier para habilitar/deshabilitar botón
                                _scrollToBottom(jump: false); // Scroll mientras escribe si es necesario
                              },
                              keyboardType: TextInputType.multiline, // Permitir múltiples líneas
                              enabled: !_isLoading, // Deshabilitar si está cargando
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8), // Espacio entre texto y botón enviar
                          // Botón de Enviar
                          IconButton(
                            padding: const EdgeInsets.only(bottom: 8, left: 4), // Ajuste fino
                            icon: _isLoading // Mostrar indicador de carga o icono de enviar
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send, size: 28),
                            tooltip: 'Enviar Mensaje',
                            color: canSendMessage ? Colors.teal : Colors.grey, // Color adaptable
                            onPressed: canSendMessage ? () => _generateResponse(_controller.text.trim()) : null, // Habilitar/deshabilitar
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
