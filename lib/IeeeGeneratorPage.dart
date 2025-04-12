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

class _IeeeGeneratorPageState extends State<IeeeGeneratorPage> {
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
      '¡Bienvenido! Soy tu experto en normas IEEE. Sube un PDF o haz una pregunta.';
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
    * Si un usuario no sube un documento ni hace referencia a una norma IEEE o a algo relacionado con la norma, responde únicamente con: "Por favor, sube un documento PDF relacionado con las normas IEEE o haz una pregunta específica sobre una norma IEEE.".
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
    _initializeModelAndLoadHistory();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
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

  void _initializeModelAndLoadHistory() async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      _addErrorMessage('Error: No se encontró la clave API en .env');
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
      print("IEEE Page - Error initializing model: $e");
      _addErrorMessage('Error al inicializar el asistente: $e');
    }
  }

  void _addErrorMessage(String text) {
    final err = {'role': 'system', 'text': text, 'timestamp': Timestamp.now()};
    if (mounted) setState(() => _chatHistory.add(err));
    _scrollToBottom();
  }

  void _listenToChatHistory() {
    if (_chatId == null) return;
    print("IEEE Page - Starting real-time listener for $_chatId/ieee_messages");

    _chatSubscription?.cancel();

    _chatSubscription = _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('ieee_messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final List<Map<String, dynamic>> newHistory = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        if (data['timestamp'] == null || data['timestamp'] is! Timestamp) {
          data['timestamp'] = Timestamp.now();
          print("Advertencia: Timestamp inválido encontrado en doc ${doc.id}, usando now()");
        }
        return data;
      }).toList();

      if (newHistory.isEmpty && !_isLoading) {
        final initialMessage = {
          'role': 'assistant',
          'text': _initialWelcomeMessageText,
          'timestamp': Timestamp.now(),
        };
        if (_chatHistory.isEmpty || (_chatHistory.length == 1 && _chatHistory.first['text'] != _initialWelcomeMessageText)) {
          _saveMessageToFirestore(initialMessage);
        }
      } else {
        setState(() {
          _chatHistory = newHistory;
        });
      }

      print("IEEE Page - Real-time update: ${_chatHistory.length} messages.");
      _scrollToBottom();
    }, onError: (e) {
      print("IEEE Page - Error listening to history: $e");
      _addErrorMessage('Error al escuchar el historial: $e');
    });
  }

  Future<void> _saveMessageToFirestore(Map<String, dynamic> message) async {
    if (_chatId == null) return;
    if (message['role'] == 'system' &&
        (message['text'].contains('subido:') || message['text'].contains('eliminado'))) {
      print("IEEE Page - Local UI message not saved: ${message['text']}");
      return;
    }
    try {
      final messageToSave = Map<String, dynamic>.from(message)
        ..remove('pdfBytes')
        ..remove('mimeType')
        ..['timestamp'] = FieldValue.serverTimestamp();
      await _firestore
          .collection('chats')
          .doc(_chatId)
          .collection('ieee_messages')
          .add(messageToSave);
    } catch (e) {
      print('Error saving message: $e');
    }
  }

  Future<void> _generateResponse(String userPrompt) async {
    if (_model == null) {
      _addErrorMessage('Error: Modelo no inicializado.');
      return;
    }
    if (userPrompt.trim().isEmpty && _selectedFile == null) {
      _addErrorMessage('Por favor, ingresa una pregunta o selecciona un PDF.');
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
        Uint8List pdfBytes = kIsWeb
            ? _selectedFile!.bytes!
            : await File(_selectedFile!.path!).readAsBytes();
        if (pdfBytes.isEmpty) throw Exception("El archivo PDF está vacío o corrupto.");
        String mimeType = 'application/pdf';
        partsForGemini.add(DataPart(mimeType, pdfBytes));
        userMessage['pdfBytes'] = pdfBytes;
        userMessage['mimeType'] = mimeType;
      } catch (e) {
        _addErrorMessage('Error procesando PDF: $e');
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
    if (_chatId != null) {
      final messageToSave = Map<String, dynamic>.from(userMessage)
        ..remove('pdfBytes')
        ..remove('mimeType');
      _saveMessageToFirestore(messageToSave);
    }

    try {
      List<Content> conversationHistory = _chatHistory
          .where((msg) => msg['role'] == 'user' || msg['role'] == 'assistant')
          .map((msg) {
        if (msg['role'] == 'user') {
          return Content.text(msg['text'] ?? '');
        } else {
          return Content.text(msg['text'] ?? '');
        }
      }).toList();

      if (conversationHistory.isNotEmpty) conversationHistory.removeLast();
      conversationHistory.add(Content.multi(partsForGemini));

      final response = await _model!.generateContent(conversationHistory);
      final assistantMessage = {
        'role': 'assistant',
        'text': response.text ?? 'No se recibió respuesta.',
        'timestamp': Timestamp.now(),
      };
      if (mounted) setState(() => _chatHistory.add(assistantMessage));
      if (_chatId != null) _saveMessageToFirestore(assistantMessage);
    } catch (e) {
      _addErrorMessage('Error al generar respuesta: $e');
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

  Future<void> _pickFile() async {
    if (!kIsWeb && Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt ?? 0;
      if (sdkInt >= 33) {
        if (!await Permission.photos.request().isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso para acceder a archivos denegado.')),
          );
          return;
        }
      } else if (sdkInt <= 31) {
        if (!await Permission.storage.request().isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso para almacenamiento denegado.')),
          );
          return;
        }
      }
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
      withData: kIsWeb,
    );

    if (result != null && result.files.isNotEmpty && mounted) {
      final file = result.files.first;
      if (file.size > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El PDF excede el límite de 5MB.')),
        );
        return;
      }
      setState(() {
        _selectedFile = file;
        _isPreviewExpanded = true;
      });
      _scrollToBottom();
    }
  }

  void _removeFile() {
    if (_selectedFile != null) {
      setState(() {
        _selectedFile = null;
        _isPreviewExpanded = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _clearChat() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpiar Chat IEEE'),
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
      print("IEEE Page - Clearing Firestore for $_chatId/ieee_messages...");
      try {
        final ref = _firestore.collection('chats').doc(_chatId).collection('ieee_messages');
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

        await _saveMessageToFirestore(welcomeMessage);

        if (mounted) {
          setState(() {
            _chatHistory = [welcomeMessage];
            _isLoading = false;
          });
        }
        _scrollToBottom();
      } catch (e) {
        print("IEEE Page - Error clearing Firestore: $e");
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
      if (role == 'SYSTEM' && (text.contains('subido:') || text.contains('eliminado'))) return false;
      if (role == 'ASSISTANT' && (text == _initialWelcomeMessageText || text == 'Inicia sesión para guardar y ver tu historial.')) return false;
      return true;
    }).toList();

    if (downloadableHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay historial relevante para descargar.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final buffer = StringBuffer()
        ..writeln('Historial del Chat IEEE')
        ..writeln('=' * 30)
        ..writeln('Exportado el: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now().toLocal())}')
        ..writeln();
      final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');

      for (final msg in downloadableHistory) {
        final role = msg['role'].toString().toUpperCase();
        final text = msg['text'] ?? '';
        dynamic ts = msg['timestamp'];
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
        buffer
          ..writeln('[$timestampStr] $role:')
          ..writeln(text);
        if (msg['fileName'] != null) buffer.writeln('  [Archivo: ${msg['fileName']}]');
        buffer.writeln('-' * 20);
      }

      final String fileContent = buffer.toString();
      final String fileName = 'historial_ieee_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt';
      final List<int> fileBytes = utf8.encode(fileContent);

      if (kIsWeb) {
        final blob = html.Blob([fileBytes], 'text/plain', 'native');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Descarga iniciada (Web).')));
        }
      } else {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Historial IEEE',
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
      print("Error general al descargar (IEEE): $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al preparar la descarga: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
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
        bool canSendMessage =
            !_isLoading && (_controller.text.trim().isNotEmpty || _selectedFile != null);
        bool hasDownloadableContent = !_isLoading && _chatHistory.any((msg) {
          final role = msg['role']?.toString().toUpperCase() ?? 'SYSTEM';
          final text = msg['text'] ?? '';
          if (role == 'SYSTEM' && (text.contains('subido:') || text.contains('eliminado'))) return false;
          if (role == 'ASSISTANT' && (text == _initialWelcomeMessageText || text == 'Inicia sesión para guardar y ver tu historial.')) return false;
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
                      if (isSystem && (text.contains('subido:') || text.contains('eliminado')))
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
                              if (isUser && fileName != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.picture_as_pdf_outlined,
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
                                Icon(Icons.picture_as_pdf_outlined,
                                    color: Colors.red[700], size: 20),
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
                                  onPressed: _isLoading ? null : _removeFile,
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
                                  child: Text(
                                      'Vista previa no disponible para PDF en esta plataforma'),
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
                        icon: const Icon(Icons.upload_file_outlined, size: 28),
                        color: _isLoading ? Colors.grey : Colors.teal,
                        tooltip: 'Seleccionar PDF',
                        onPressed: _isLoading ? null : _pickFile,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: 'Pregunta sobre normas IEEE...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25.0),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25.0),
                              borderSide: BorderSide(color: Colors.teal.shade200, width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            isDense: true,
                          ),
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (value) => canSendMessage ? _generateResponse(value) : null,
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
                        color: canSendMessage ? Colors.teal : Colors.grey,
                        onPressed: canSendMessage ? () => _generateResponse(_controller.text) : null,
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