import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'dart:math' as math;

class AreaVisualizerPage extends StatefulWidget {
  const AreaVisualizerPage({super.key});

  @override
  State<AreaVisualizerPage> createState() => _AreaVisualizerPageState();
}

class _AreaVisualizerPageState extends State<AreaVisualizerPage> {
  final TextEditingController _functionController = TextEditingController();
  final TextEditingController _lowerLimitController = TextEditingController();
  final TextEditingController _upperLimitController = TextEditingController();
  String? _function; // Sin función por defecto
  double? _lowerLimit;
  double? _upperLimit;

  @override
  void initState() {
    super.initState();
    // No establecemos valores por defecto
  }

  // Función para evaluar la expresión ingresada (solo soporta x^2, x, constantes por simplicidad)
  double _evaluateFunction(String function, double x) {
    try {
      if (function.contains('x^2')) {
        return math.pow(x, 2).toDouble();
      } else if (function.contains('x')) {
        return x;
      } else {
        return double.parse(function); // Constante
      }
    } catch (e) {
      return 0; // En caso de error, retorna 0
    }
  }

  @override
  void dispose() {
    _functionController.dispose();
    _lowerLimitController.dispose();
    _upperLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualizador de Áreas'),
        centerTitle: true,
        elevation: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
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
              TextField(
                controller: _functionController,
                decoration: const InputDecoration(
                  labelText: 'Función (ej. x^2, 2x, 5)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _function = value.isEmpty ? null : value;
                  });
                },
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
                      keyboardType: TextInputType.number,
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
                      keyboardType: TextInputType.number,
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
              if (_function != null && _lowerLimit != null && _upperLimit != null)
                Card(
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Math.tex(
                      r'\int_{' +
                          _lowerLimit!.toString() +
                          r'}^{' +
                          _upperLimit!.toString() +
                          r'} ' +
                          _function! +
                          r' \,dx',
                      textStyle: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 300,
                child: _function != null && _lowerLimit != null && _upperLimit != null
                    ? CustomPaint(
                  painter: FunctionGraphPainter(
                    function: _function!,
                    lowerLimit: _lowerLimit!,
                    upperLimit: _upperLimit!,
                    evaluateFunction: _evaluateFunction,
                  ),
                )
                    : Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: Text(
                      'Ingresa una función y límites para ver la gráfica',
                      style: TextStyle(color: Colors.grey),
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
    final paint = Paint()
      ..color = Colors.teal
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final areaPaint = Paint()
      ..color = Colors.red.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final dashedPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final axisPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;

    final textStyle = const TextStyle(color: Colors.black, fontSize: 12);

    // Escala
    double xMin = math.min(lowerLimit, -5);
    double xMax = math.max(upperLimit, 5);
    double yMin = -10;
    double yMax = 10;

    double scaleX = size.width / (xMax - xMin);
    double scaleY = size.height / (yMax - yMin);

    // Ejes
    double originX = -xMin * scaleX;
    double originY = size.height - (-yMin * scaleY);
    canvas.drawLine(Offset(0, originY), Offset(size.width, originY), axisPaint); // Eje X
    canvas.drawLine(Offset(originX, 0), Offset(originX, size.height), axisPaint); // Eje Y

    // Etiquetas en los ejes
    for (int x = xMin.toInt(); x <= xMax.toInt(); x++) {
      if (x != 0) {
        double canvasX = (x - xMin) * scaleX;
        _drawText(canvas, x.toString(), Offset(canvasX - 5, originY + 5), textStyle);
      }
    }
    for (int y = yMin.toInt(); y <= yMax.toInt(); y += 2) {
      if (y != 0) {
        double canvasY = size.height - (y - yMin) * scaleY;
        _drawText(canvas, y.toString(), Offset(originX + 5, canvasY - 5), textStyle);
      }
    }

    // Dibujar la función
    Path path = Path();
    bool isFirst = true;
    List<Offset> areaPoints = [];

    for (double x = xMin; x <= xMax; x += (xMax - xMin) / size.width) {
      double y = evaluateFunction(function, x);
      double canvasX = (x - xMin) * scaleX;
      double canvasY = size.height - (y - yMin) * scaleY;

      if (isFirst) {
        path.moveTo(canvasX, canvasY);
        isFirst = false;
      } else {
        path.lineTo(canvasX, canvasY);
      }

      // Guardar puntos para el área bajo la curva
      if (x >= lowerLimit && x <= upperLimit) {
        areaPoints.add(Offset(canvasX, canvasY));
      }
    }

    canvas.drawPath(path, paint);

    // Dibujar el área bajo la curva
    if (areaPoints.isNotEmpty) {
      Path areaPath = Path();
      areaPath.moveTo((lowerLimit - xMin) * scaleX, originY); // Punto inicial en el eje X
      areaPath.lineTo(areaPoints.first.dx, areaPoints.first.dy);
      for (var point in areaPoints) {
        areaPath.lineTo(point.dx, point.dy);
      }
      areaPath.lineTo((upperLimit - xMin) * scaleX, originY); // Punto final en el eje X
      areaPath.close();
      canvas.drawPath(areaPath, areaPaint);

      // Líneas punteadas para los límites
      _drawDashedLine(canvas, Offset((lowerLimit - xMin) * scaleX, 0), Offset((lowerLimit - xMin) * scaleX, size.height), dashedPaint);
      _drawDashedLine(canvas, Offset((upperLimit - xMin) * scaleX, 0), Offset((upperLimit - xMin) * scaleX, size.height), dashedPaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const double dashWidth = 5;
    const double dashSpace = 5;
    double distance = (end.dy - start.dy).abs();
    double currentY = start.dy;
    while (currentY < end.dy) {
      canvas.drawLine(
        Offset(start.dx, currentY),
        Offset(start.dx, math.min(currentY + dashWidth, end.dy)),
        paint,
      );
      currentY += dashWidth + dashSpace;
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}