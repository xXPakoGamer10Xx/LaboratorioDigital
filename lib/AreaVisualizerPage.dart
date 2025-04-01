import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'dart:math' as math;
import 'package:math_expressions/math_expressions.dart';

class AreaVisualizerPage extends StatefulWidget {
  const AreaVisualizerPage({super.key});

  @override
  State<AreaVisualizerPage> createState() => _AreaVisualizerPageState();
}

class _AreaVisualizerPageState extends State<AreaVisualizerPage> {
  final TextEditingController _functionController = TextEditingController();
  final TextEditingController _lowerLimitController = TextEditingController();
  final TextEditingController _upperLimitController = TextEditingController();
  String? _function;
  double? _lowerLimit;
  double? _upperLimit;
  String? _evaluationError; // Para mostrar errores en UI si es necesario

  @override
  void initState() {
    super.initState();
    // Listener para limpiar error si cambia la función o límites
    _functionController.addListener(_clearError);
    _lowerLimitController.addListener(_clearError);
    _upperLimitController.addListener(_clearError);
  }

  void _clearError() {
    if (_evaluationError != null) {
      setState(() {
        _evaluationError = null;
      });
    }
  }

  // --- Helper para añadir multiplicación explícita ---
  String _addExplicitMultiplication(String func) {
    // Quitar espacios primero para simplificar regex
    String result = func.replaceAll(' ', '');

    // Reemplazos específicos ANTES de añadir '*':
    result = result
        .replaceAll('pi', '(${math.pi})') // Reemplazar pi por su valor numérico
        .replaceAll('e', '(${math.e})');  // Reemplazar e por su valor numérico

    // Lista de funciones conocidas para evitar agregar * después de ellas
    final knownFunctions = ['sin', 'cos', 'tan', 'ln', 'log', 'sqrt', 'abs', 'sec', 'csc', 'cot'];

    // Iterar para aplicar reglas hasta que no haya cambios
    String previousResult;
    int iterations = 0; // Limitar iteraciones por seguridad
    do {
      previousResult = result;

      // 1. Dígito seguido de Letra (ej: 3x -> 3*x)
      result = result.replaceAllMapped(
        RegExp(r'(\d)([a-zA-Z])'),
            (match) {
          String nextChar = match.group(2)!;
          if (knownFunctions.contains(nextChar)) {
            return match.group(0)!; // No agregar * si es una función conocida
          }
          return '${match.group(1)}*${match.group(2)}';
        },
      );

      // 2. Letra seguida de Número (ej: x3 -> x*3)
      result = result.replaceAllMapped(
        RegExp(r'([a-zA-Z])(\d)'),
            (match) => '${match.group(1)}*${match.group(2)}',
      );

      // 3. Paréntesis cerrado seguido de Letra, Número o Paréntesis abierto (ej: )( -> )*(, )x -> )*x)
      result = result.replaceAllMapped(
        RegExp(r'(\))([a-zA-Z0-9\(])'),
            (match) => '${match.group(1)}*${match.group(2)}',
      );

      // 4. Dígito seguido de Paréntesis Abierto (ej: 3( -> 3*()
      result = result.replaceAllMapped(
        RegExp(r'(\d)(\()'),
            (match) => '${match.group(1)}*${match.group(2)}',
      );

      iterations++;
    } while (previousResult != result && iterations < 5); // Evitar bucles infinitos

    // --- Otros reemplazos (DESPUÉS de añadir '*') ---
    result = result
        .replaceAll('cot(', '1/tan(') // Cuidado con tan(0), etc.
        .replaceAll('sec(', '1/cos(')
        .replaceAll('csc(', '1/sin(')
        .replaceAll('ln(', 'log(') // ln(x) → log(x) para math_expressions
        .replaceAll('infinity', '1e10'); // Workaround

    // Transformar root(x, n) en x^(1/n)
    if (result.contains('root')) {
      RegExp rootRegExp = RegExp(r'root\(([^,]+),\s*([^)]+)\)');
      result = result.replaceAllMapped(rootRegExp, (match) {
        String base = match.group(1)!;
        String index = match.group(2)!;
        return '($base)^(1/($index))';
      });
    }

    return result;
  }

  // --- Evaluación de la función ---
  double _evaluateFunction(String function, double x) {
    String modifiedFunction = "";
    // Limpiar error al inicio de cada evaluación
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _evaluationError != null) {
        setState(() => _evaluationError = null);
      }
    });

    try {
      modifiedFunction = _addExplicitMultiplication(function);
      print('Función original: "$function", Modificada: "$modifiedFunction"'); // Depuración

      Parser p = Parser();
      Expression exp = p.parse(modifiedFunction);
      ContextModel cm = ContextModel();
      cm.bindVariable(Variable('x'), Number(x));

      double result = exp.evaluate(EvaluationType.REAL, cm);

      if (result.isNaN || result.isInfinite) {
        print('Resultado NaN o infinito para x=$x');
        return double.nan;
      }
      return result;
    } catch (e) {
      final errorMsg = 'Error en f(x): $e\nOriginal: "$function"\nModificada: "$modifiedFunction"';
      print(errorMsg);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _evaluationError == null) {
          setState(() => _evaluationError = 'Error en la función. Revisa la sintaxis.');
        }
      });
      return double.nan;
    }
  }

  // Método para mostrar el diálogo de símbolos matemáticos
  void _showMathSymbolsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Símbolos Matemáticos'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildSymbolButton('x²', '^2'),
                _buildSymbolButton('xⁿ', '^'),
                _buildSymbolButton('log', 'log'),
                _buildSymbolButton('ln', 'ln'),
                _buildSymbolButton('√', 'sqrt'),
                _buildSymbolButton('√ⁿ', 'root'),
                _buildSymbolButton('|x|', 'abs'),
                _buildSymbolButton('sin', 'sin'),
                _buildSymbolButton('cos', 'cos'),
                _buildSymbolButton('tan', 'tan'),
                _buildSymbolButton('cot', 'cot'),
                _buildSymbolButton('sec', 'sec'),
                _buildSymbolButton('csc', 'csc'),
                _buildSymbolButton('π', 'pi'),
                _buildSymbolButton('∞', 'infinity'),
                _buildSymbolButton('e', 'e'),
                _buildSymbolButton('(', '('),
                _buildSymbolButton(')', ')'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  // Método para construir un botón de símbolo
  Widget _buildSymbolButton(String display, String insert) {
    return ElevatedButton(
      onPressed: () {
        _insertSymbol(insert);
        Navigator.pop(context);
      },
      child: Text(display),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
    );
  }

  // Método para insertar el símbolo en el TextField
  void _insertSymbol(String symbol) {
    final currentText = _functionController.text;
    final selection = _functionController.selection;
    final cursorPos = selection.baseOffset;
    String textToInsert = symbol;
    int cursorOffset = symbol.length;

    bool placeCursorInside = false;

    switch (symbol) {
      case '^2':
        textToInsert = '^2';
        cursorOffset = textToInsert.length;
        break;
      case '^':
        textToInsert = '^';
        cursorOffset = textToInsert.length;
        break;
      case 'sqrt':
      case 'abs':
      case 'sin':
      case 'cos':
      case 'tan':
      case 'cot':
      case 'sec':
      case 'csc':
      case 'log':
      case 'ln':
        textToInsert = '$symbol(x)';
        placeCursorInside = true;
        break;
      case 'root':
        textToInsert = 'root(x,2)';
        cursorOffset = textToInsert.indexOf('(') + 1;
        break;
      case 'pi':
      case 'e':
      case 'infinity':
        break;
      case '(':
      case ')':
        break;
      default:
        textToInsert = symbol;
        cursorOffset = symbol.length;
    }

    if (placeCursorInside && textToInsert.endsWith(')')) {
      cursorOffset = textToInsert.length - 1;
    }

    final newText = currentText.replaceRange(selection.start, selection.end, textToInsert);

    _functionController.text = newText;
    _functionController.selection = TextSelection.collapsed(
      offset: selection.start + cursorOffset,
    );

    setState(() {
      _function = newText.isEmpty ? null : newText;
      _clearError();
    });
  }

  @override
  void dispose() {
    _functionController.removeListener(_clearError);
    _lowerLimitController.removeListener(_clearError);
    _upperLimitController.removeListener(_clearError);
    _functionController.dispose();
    _lowerLimitController.dispose();
    _upperLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool canVisualize = _function != null &&
        _function!.isNotEmpty &&
        _lowerLimit != null &&
        _upperLimit != null &&
        _evaluationError == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualizador de Áreas'),
        centerTitle: true,
        elevation: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ingresa la función y los límites de integración',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _functionController,
                      decoration: InputDecoration(
                        labelText: 'Función f(x)',
                        hintText: 'Ej: 3*x^2+5*x-9, sin(x)',
                        border: const OutlineInputBorder(),
                        errorText: _evaluationError,
                        errorMaxLines: 2,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _function = value.isEmpty ? null : value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.functions),
                    tooltip: 'Símbolos matemáticos',
                    onPressed: _showMathSymbolsDialog,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lowerLimitController,
                      decoration: const InputDecoration(
                        labelText: 'Límite inferior',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      onChanged: (value) {
                        setState(() {
                          _lowerLimit = double.tryParse(value);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _upperLimitController,
                      decoration: const InputDecoration(
                        labelText: 'Límite superior',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      onChanged: (value) {
                        setState(() {
                          _upperLimit = double.tryParse(value);
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (canVisualize)
                Card(
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: Math.tex(
                        r'\int_{' '{${_lowerLimit!.toStringAsFixed(2)}}' r'}^{' '{${_upperLimit!.toStringAsFixed(2)}}' r'} \left(' +
                            _function! +
                            r'\right) \,dx',
                        textStyle: const TextStyle(fontSize: 20),
                        mathStyle: MathStyle.display,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 300,
                child: canVisualize
                    ? RepaintBoundary(
                  child: CustomPaint(
                    painter: FunctionGraphPainter(
                      function: _function!,
                      lowerLimit: _lowerLimit!,
                      upperLimit: _upperLimit!,
                      evaluateFunction: _evaluateFunction,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                )
                    : Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      _evaluationError ?? 'Ingresa función y límites válidos',
                      style: TextStyle(color: _evaluationError != null ? Colors.red : Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FunctionGraphPainter extends CustomPainter {
  final String function;
  final double lowerLimit;
  final double upperLimit;
  final double Function(String, double) evaluateFunction;

  FunctionGraphPainter({
    required this.function,
    required this.lowerLimit,
    required this.upperLimit,
    required this.evaluateFunction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 0.5;
    final axisPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;
    final functionPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final areaPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    const textStyle = TextStyle(color: Colors.black, fontSize: 10);

    double xPlotMin = math.min(lowerLimit, -math.pi) - 1;
    double xPlotMax = math.max(upperLimit, math.pi) + 1;
    if (xPlotMax <= xPlotMin) xPlotMax = xPlotMin + 2;

    double yPlotMin = -10.0;
    double yPlotMax = 20.0;

    if (yPlotMax <= yPlotMin) {
      yPlotMin = -5;
      yPlotMax = 5;
    }

    double scaleX = size.width / (xPlotMax - xPlotMin);
    double scaleY = (yPlotMax == yPlotMin) ? 1 : size.height / (yPlotMax - yPlotMin);
    double originX = -xPlotMin * scaleX;
    double originY = size.height - (-yPlotMin * scaleY);

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (double x = xPlotMin; x <= xPlotMax; x += 1) {
      double canvasX = (x - xPlotMin) * scaleX;
      canvas.drawLine(Offset(canvasX, 0), Offset(canvasX, size.height), gridPaint);
    }
    for (double y = yPlotMin; y <= yPlotMax; y += 1) {
      double canvasY = size.height - (y - yPlotMin) * scaleY;
      canvas.drawLine(Offset(0, canvasY), Offset(size.width, canvasY), gridPaint);
    }

    canvas.drawLine(Offset(0, originY), Offset(size.width, originY), axisPaint);
    canvas.drawLine(Offset(originX, 0), Offset(originX, size.height), axisPaint);

    for (int x = xPlotMin.toInt(); x <= xPlotMax.toInt(); x += 2) {
      if (x != 0) {
        double canvasX = (x - xPlotMin) * scaleX;
        _drawText(canvas, x.toString(), Offset(canvasX - 5, originY + 5), textStyle);
      }
    }
    for (double y = yPlotMin; y <= yPlotMax; y += 1) {
      if (y != 0) {
        double canvasY = size.height - (y - yPlotMin) * scaleY;
        _drawText(canvas, y.toStringAsFixed(1), Offset(originX + 5, canvasY - 5), textStyle);
      }
    }

    Path functionPath = Path();
    List<Offset> areaPoints = [];
    bool firstValidPointInPath = true;
    bool firstPointInArea = true;

    double startAreaCanvasX = (lowerLimit - xPlotMin) * scaleX;
    if (startAreaCanvasX >= 0 && startAreaCanvasX <= size.width) {
      areaPoints.add(Offset(startAreaCanvasX, originY));
    }

    for (int i = 0; i <= size.width.toInt(); i++) {
      double x = xPlotMin + i / scaleX;
      double y = evaluateFunction(function, x);

      if (y.isNaN || y.isInfinite) {
        firstValidPointInPath = true;
        continue;
      }

      double canvasX = (x - xPlotMin) * scaleX;
      double canvasY = (size.height - (y - yPlotMin) * scaleY).clamp(0.0, size.height);

      if (firstValidPointInPath) {
        functionPath.moveTo(canvasX, canvasY);
        firstValidPointInPath = false;
      } else {
        functionPath.lineTo(canvasX, canvasY);
      }

      if (x >= lowerLimit && x <= upperLimit && canvasX >= 0 && canvasX <= size.width) {
        if (firstPointInArea && areaPoints.isEmpty) {
          areaPoints.add(Offset(canvasX, originY));
        }
        areaPoints.add(Offset(canvasX, canvasY));
        firstPointInArea = false;
      }
    }

    canvas.drawPath(functionPath, functionPaint);

    if (areaPoints.length > 1) {
      double endAreaCanvasX = (upperLimit - xPlotMin) * scaleX;
      if (endAreaCanvasX >= 0 && endAreaCanvasX <= size.width) {
        if (areaPoints.last.dx != endAreaCanvasX) {
          areaPoints.add(Offset(endAreaCanvasX, originY));
        } else {
          areaPoints.last = Offset(endAreaCanvasX, originY);
        }
      } else {
        areaPoints.add(Offset(areaPoints.last.dx, originY));
      }

      Path areaPath = Path();
      areaPath.moveTo(areaPoints.first.dx, areaPoints.first.dy);
      for (int i = 1; i < areaPoints.length; i++) {
        areaPath.lineTo(areaPoints[i].dx, areaPoints[i].dy);
      }
      areaPath.close();
      canvas.drawPath(areaPath, areaPaint);
    }
  }

  void _drawText(Canvas canvas, String text, Offset position, TextStyle style) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant FunctionGraphPainter oldDelegate) {
    return oldDelegate.function != function ||
        oldDelegate.lowerLimit != lowerLimit ||
        oldDelegate.upperLimit != upperLimit;
  }
}