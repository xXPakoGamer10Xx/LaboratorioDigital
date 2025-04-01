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

class _ShapesPageState extends State<ShapesPage> {
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
  StreamSubscription<QuerySnapshot>? _chatSubscription;

  final List<String> _shapes = ['Triángulo', 'Rectángulo', 'Círculo', 'Polígono Regular', 'Texto'];
  static const String _initialWelcomeMessageText =
      '¡Bienvenido! Soy tu experto en figuras geométricas. Selecciona, describe o sube una imagen.';
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
* **Imagen Ilegible:** Si la imagen es ilegible, borrosa, incompleta o no contiene una figura geométrica clara, indica esto en tu respuesta.
* **Análisis de la Figura (Texto o Imagen):**
    * Identifica la figura geométrica.
    * Calcula **todas** las propiedades relevantes de la figura (área, perímetro, apotema, etc.). Si falta información, indícalo y explica qué se necesita.
    * Proporciona una descripción textual de la figura.
    * Si es posible, describe *cualitativamente* cómo se vería la figura (color, forma general).
* **Polígonos Regulares:** Para polígonos regulares, usa el número de lados (n) y al menos una de las siguientes medidas (lado, área, perímetro, apotema) para calcular las demás propiedades. Fórmulas:
    * Área = (Perímetro × Apotema) / 2
    * Perímetro = n × Lado
    * Área = (n × Lado × Apotema) / 2
    * Apotema = Lado / (2 × tan(π/n))
* **Explicaciones Paso a Paso (Obligatorio):** Explica **DETALLADAMENTE** cada paso de tus cálculos, mostrando **TODAS** las fórmulas y operaciones intermedias. Descompón la solución en pasos numerados.
* **RESTRICCIÓN ABSOLUTA:** No respondas a preguntas fuera de geometría. Responde **ESTRICTAMENTE** con: "No puedo responder a esa pregunta, ya que está fuera de mi especialización en geometría."

**Formato de Respuesta (Markdown):**

* Utiliza notación matemática estándar (π para pi, +, -, ×, ÷, √, ^).
* Descompón los cálculos en pasos numerados.
* **Negritas:** Resalta nombres de figuras, fórmulas, resultados y términos clave.
* **Títulos y Subtítulos:** Usa títulos en negritas (ej., **Identificación**, **Cálculo del Área**, **Cálculo del Perímetro**).
""";

  @override
  void initState() {
    super.initState();
    print("Shapes Page - Auth State Init: ${_auth.currentUser?.uid}");
    _setChatIdBasedOnUser();
    print("Shapes Page - Initial Chat ID: $_chatId");
    _initializeModelAndLoadHistory();
    _controller.addListener(() => setState(() {}));
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

  void _initializeModelAndLoadHistory() async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      _addErrorMessage('Error: No se encontró la clave API en .env');
      return;
    }
    try {
      _model = GenerativeModel(
        model: 'gemini-2.5-pro-exp-03-25', // Actualizado para consistencia
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
      if (_chatId != null) {
        _listenToChatHistory();
      } else {
        _addInitialMessage();
      }
    } catch (e) {
      print("Shapes Page - Error initializing model: $e");
      _addErrorMessage('Error al inicializar el asistente: $e');
    }
  }

  void _listenToChatHistory() {
    if (_chatId == null) return;
    print("Shapes Page - Starting real-time listener for $_chatId/shapes_messages");

    _chatSubscription?.cancel();

    _chatSubscription = _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('shapes_messages')
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

      print("Shapes Page - Real-time update: ${_chatHistory.length} messages.");
      _scrollToBottom();
    }, onError: (e) {
      print("Shapes Page - Error listening to history: $e");
      _addErrorMessage('Error al escuchar el historial: $e');
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

  void _addErrorMessage(String text) {
    final err = {'role': 'system', 'text': text, 'timestamp': Timestamp.now()};
    if (mounted) setState(() => _chatHistory.add(err));
    _scrollToBottom();
  }

  Future<void> _saveMessageToFirestore(Map<String, dynamic> message) async {
    if (_chatId == null) return;
    if (message['role'] == 'system' &&
        (message['text'].contains('subida:') || message['text'].contains('eliminada'))) {
      print("Shapes Page - Local UI message not saved: ${message['text']}");
      return;
    }
    try {
      final messageToSave = Map<String, dynamic>.from(message)
        ..remove('id')
        ..remove('imageBytes')
        ..remove('mimeType')
        ..['timestamp'] = FieldValue.serverTimestamp();
      print("Shapes Page - Saving message to Firestore: ${messageToSave['role']}");
      await _firestore
          .collection('chats')
          .doc(_chatId)
          .collection('shapes_messages')
          .add(messageToSave);
    } catch (e) {
      print('Shapes Page - Error saving message: $e');
    }
  }

  Future<void> _generateResponse(String userPrompt) async {
    if (_model == null) {
      _addErrorMessage('Error: Modelo no inicializado.');
      return;
    }
    if (userPrompt.trim().isEmpty && _selectedFile == null && _selectedShape == null) {
      _addErrorMessage('Por favor, selecciona una figura, describe una o sube una imagen.');
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
        print("Shapes Page - Error procesando imagen: $e");
        _addErrorMessage('Error procesando imagen: $e');
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
      _side1Controller.clear();
      _side2Controller.clear();
      _textController.clear();
      _sidesController.clear();
      _areaController.clear();
      _perimeterController.clear();
      _apothemController.clear();
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

      print("Shapes Page - Sending ${conversationHistory.length} content items to Gemini...");
      final response = await _model!.generateContent(conversationHistory);
      print("Shapes Page - Response received.");
      final assistantMessage = {
        'role': 'assistant',
        'text': response.text ?? 'No se recibió respuesta.',
        'timestamp': Timestamp.now(),
      };
      if (mounted) setState(() => _chatHistory.add(assistantMessage));
      if (_chatId != null) _saveMessageToFirestore(assistantMessage);
    } catch (e) {
      print("Shapes Page - Error generating response: $e");
      _addErrorMessage('Error al generar respuesta: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedFile = null;
          _isPreviewExpanded = false;
          _selectedShape = null;
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
          _selectedShape = null;
          _side1Controller.clear();
          _side2Controller.clear();
          _textController.clear();
          _sidesController.clear();
          _areaController.clear();
          _perimeterController.clear();
          _apothemController.clear();
          _chatHistory.add(msg);
        });
        _scrollToBottom();
        print("Shapes Page - Image selected: ${_selectedFile?.name}");
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
      print("Shapes Page - Selected image removed.");
    }
  }

  Future<void> _clearChat() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar Chat de Figuras'),
        content: const Text('¿Estás seguro de que quieres borrar todo el historial?'),
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

    setState(() {
      _chatHistory.clear();
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
      _isLoading = true;
    });

    final welcomeMessage = {
      'role': 'assistant',
      'text': _chatId != null
          ? _initialWelcomeMessageText
          : 'Inicia sesión para guardar y ver tu historial.',
      'timestamp': Timestamp.now(),
    };

    if (_chatId != null) {
      print("Shapes Page - Clearing Firestore for $_chatId/shapes_messages...");
      try {
        final ref = _firestore.collection('chats').doc(_chatId).collection('shapes_messages');
        var snapshot = await ref.limit(100).get();
        while (snapshot.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (var doc in snapshot.docs) batch.delete(doc.reference);
          await batch.commit();
          print("Lote de ${snapshot.docs.length} mensajes borrado.");
          snapshot = await ref.limit(100).get();
        }
        print("Shapes Page - Firestore history cleared.");
        _saveMessageToFirestore(welcomeMessage);
        if (mounted) setState(() => _chatHistory.add(welcomeMessage));
      } catch (e) {
        print("Shapes Page - Error clearing Firestore: $e");
        _addErrorMessage('Error limpiando historial: $e');
        if (mounted) setState(() => _chatHistory.add(welcomeMessage));
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
        ..writeln("Historial del Chat de Figuras Geométricas")
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
          'historial_figuras_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
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
          dialogTitle: 'Guardar Historial de Figuras',
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
              SnackBar(content: Text('Historial guardado en: ${result.split('/').last}')),
            );
          }
        }
      }
    } catch (e) {
      print("Shapes Page - Error downloading history: $e");
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

  void _tryGenerateResponse() {
    if (_isLoading) return;
    String userPrompt = '';
    if (_selectedFile != null) {
      userPrompt = 'Analiza la figura geométrica en la imagen subida.';
      _generateResponse(userPrompt);
      return;
    }
    if (_selectedShape != null) {
      switch (_selectedShape) {
        case 'Triángulo':
          if (_side1Controller.text.trim().isEmpty ||
              _side2Controller.text.trim().isEmpty ||
              double.tryParse(_side1Controller.text.trim()) == null ||
              double.tryParse(_side2Controller.text.trim()) == null) {
            _addErrorMessage('Ingresa valores numéricos válidos para base y altura.');
            return;
          }
          userPrompt =
          'Analiza un triángulo con base ${_side1Controller.text} y altura ${_side2Controller.text}.';
          break;
        case 'Rectángulo':
          if (_side1Controller.text.trim().isEmpty ||
              _side2Controller.text.trim().isEmpty ||
              double.tryParse(_side1Controller.text.trim()) == null ||
              double.tryParse(_side2Controller.text.trim()) == null) {
            _addErrorMessage('Ingresa valores numéricos válidos para ancho y altura.');
            return;
          }
          userPrompt =
          'Analiza un rectángulo con ancho ${_side1Controller.text} y altura ${_side2Controller.text}.';
          break;
        case 'Círculo':
          if (_side1Controller.text.trim().isEmpty ||
              double.tryParse(_side1Controller.text.trim()) == null) {
            _addErrorMessage('Ingresa un valor numérico válido para el radio.');
            return;
          }
          userPrompt = 'Analiza un círculo con radio ${_side1Controller.text}.';
          break;
        case 'Polígono Regular':
          if (_sidesController.text.trim().isEmpty ||
              int.tryParse(_sidesController.text.trim()) == null ||
              int.parse(_sidesController.text.trim()) < 3) {
            _addErrorMessage('Ingresa un número de lados válido (entero >= 3).');
            return;
          }
          bool hasAtLeastOne = _side1Controller.text.isNotEmpty ||
              _areaController.text.isNotEmpty ||
              _perimeterController.text.isNotEmpty ||
              _apothemController.text.isNotEmpty;
          if (!hasAtLeastOne) {
            _addErrorMessage(
                'Proporciona al menos una medida (lado, área, perímetro o apotema).');
            return;
          }
          bool optionalsAreValid = (_side1Controller.text.isEmpty ||
              double.tryParse(_side1Controller.text.trim()) != null) &&
              (_areaController.text.isEmpty ||
                  double.tryParse(_areaController.text.trim()) != null) &&
              (_perimeterController.text.isEmpty ||
                  double.tryParse(_perimeterController.text.trim()) != null) &&
              (_apothemController.text.isEmpty ||
                  double.tryParse(_apothemController.text.trim()) != null);
          if (!optionalsAreValid) {
            _addErrorMessage('Ingresa valores numéricos válidos en los campos opcionales.');
            return;
          }
          userPrompt = 'Analiza un polígono regular con número de lados ${_sidesController.text}';
          if (_side1Controller.text.isNotEmpty) {
            userPrompt += ', mide cada lado ${_side1Controller.text}';
          }
          if (_areaController.text.isNotEmpty) userPrompt += ', área ${_areaController.text}';
          if (_perimeterController.text.isNotEmpty) {
            userPrompt += ', perímetro ${_perimeterController.text}';
          }
          if (_apothemController.text.isNotEmpty) {
            userPrompt += ', apotema ${_apothemController.text}';
          }
          userPrompt += '.';
          break;
        case 'Texto':
          if (_textController.text.trim().isEmpty) {
            _addErrorMessage('Por favor, describe la figura.');
            return;
          }
          userPrompt =
          'Analiza una figura con las siguientes características: ${_textController.text}.';
          break;
      }
      _generateResponse(userPrompt);
    } else {
      _addErrorMessage('Selecciona una figura, describe una o sube una imagen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 720;
        double chatBubbleMaxWidth = isWideScreen ? 600 : constraints.maxWidth * 0.8;
        bool canSendMessage = !_isLoading && (_selectedFile != null || _selectedShape != null);
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
                  text == 'Inicia sesión para guardar y ver tu historial.')) return false;
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
                onPressed: _isLoading || !hasDownloadableContent ? null : _downloadHistory,
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
                      final role = message['role'] ?? 'system';
                      final text = message['text'] ?? '';
                      final fileName = message['fileName'];
                      final imageBytes = message['imageBytes'] as Uint8List?;
                      final isUser = role == 'user';
                      final isSystem = role == 'system';
                      Color backgroundColor = isUser
                          ? Colors.teal[100]!
                          : isSystem
                          ? Colors.orange[100]!
                          : Colors.grey[200]!;
                      Color textColor = isUser
                          ? Colors.teal[900]!
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
                                Icon(Icons.image_outlined, color: Colors.teal[700], size: 20),
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
                                      style: const TextStyle(color: Colors.teal, fontSize: 13)),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(60, 30),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: _isLoading ? null : _removeImage,
                                  child: const Text('Eliminar',
                                      style: TextStyle(color: Colors.red, fontSize: 13)),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            padding: const EdgeInsets.only(bottom: 8, right: 4),
                            icon: const Icon(Icons.image_search, size: 28),
                            color: Colors.teal,
                            tooltip: 'Subir Imagen',
                            onPressed: _isLoading ? null : _pickImage,
                          ),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: 'Selecciona figura',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(25.0),
                                    borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(25.0),
                                  borderSide: BorderSide(color: Colors.teal.shade200, width: 1.5),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                isDense: true,
                              ),
                              value: _selectedShape,
                              items: _shapes
                                  .map((s) => DropdownMenuItem<String>(value: s, child: Text(s)))
                                  .toList(),
                              onChanged: _selectedFile != null || _isLoading
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
                          const SizedBox(width: 8),
                          IconButton(
                            padding: const EdgeInsets.only(bottom: 8, left: 4),
                            icon: _isLoading
                                ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send, size: 28),
                            tooltip: 'Analizar Figura',
                            color: canSendMessage ? Colors.teal : Colors.grey,
                            onPressed: canSendMessage ? _tryGenerateResponse : null,
                          ),
                        ],
                      ),
                      if (_selectedShape != null && _selectedFile == null) ...[
                        const SizedBox(height: 8),
                        if (_selectedShape == 'Triángulo' || _selectedShape == 'Rectángulo')
                          Row(
                            children: [
                              Expanded(
                                  child: _buildTextField(
                                      _side1Controller, _selectedShape == 'Triángulo' ? 'Base' : 'Ancho')),
                              const SizedBox(width: 8),
                              Expanded(child: _buildTextField(_side2Controller, 'Altura')),
                            ],
                          ),
                        if (_selectedShape == 'Círculo')
                          _buildTextField(_side1Controller, 'Radio'),
                        if (_selectedShape == 'Polígono Regular') ...[
                          _buildTextField(_sidesController, 'Lados (n ≥ 3)', keyboard: TextInputType.number),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _buildTextField(_side1Controller, 'Lado (opc)')),
                              const SizedBox(width: 8),
                              Expanded(child: _buildTextField(_apothemController, 'Apotema (opc)')),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _buildTextField(_areaController, 'Área (opc)')),
                              const SizedBox(width: 8),
                              Expanded(child: _buildTextField(_perimeterController, 'Perímetro (opc)')),
                            ],
                          ),
                        ],
                        if (_selectedShape == 'Texto')
                          _buildTextField(
                            _textController,
                            'Describe la figura...',
                            keyboard: TextInputType.text,
                            maxLines: 3,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _tryGenerateResponse(),
                          ),
                      ],
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
      TextEditingController controller,
      String label, {
        TextInputType keyboard = TextInputType.number,
        int? maxLines = 1,
        TextInputAction? textInputAction,
        ValueChanged<String>? onSubmitted,
      }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25.0),
          borderSide: BorderSide(color: Colors.teal.shade200, width: 1.5),
        ),
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
      style: const TextStyle(fontSize: 16),
    );
  }
}