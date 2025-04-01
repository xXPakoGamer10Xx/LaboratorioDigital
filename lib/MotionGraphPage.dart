import 'package:flutter/material.dart';
import 'dart:math' as math;

class MotionGraphPage extends StatefulWidget {
  const MotionGraphPage({super.key});

  @override
  State<MotionGraphPage> createState() => _MotionGraphPageState();
}

class _MotionGraphPageState extends State<MotionGraphPage> with SingleTickerProviderStateMixin {
  String? _selectedMotion;
  final TextEditingController _initialVelocityController = TextEditingController();
  final TextEditingController _accelerationController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  late AnimationController _animationController;
  List<Offset> _positionData = [];
  double _objectPosition = 0.0;
  double _maxPosition = 0.0;
  double _finalVelocity = 0.0;

  final List<String> _motions = ['MRU', 'MRUA', 'Caída Libre'];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addListener(() {
      _updateGraph();
    });
  }

  void _startAnimation() {
    if (_selectedMotion == null || _timeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona un tipo de movimiento y define el tiempo.')),
      );
      return;
    }

    _positionData.clear();
    _maxPosition = _calculateMaxPosition();
    _finalVelocity = _calculateFinalVelocity();
    _animationController.reset();
    _updateGraph();
    _animationController.forward();
  }

  double _calculateMaxPosition() {
    double tMax = double.tryParse(_timeController.text) ?? 0.0;
    double v0 = double.tryParse(_initialVelocityController.text) ?? 0.0;
    double a = _selectedMotion == 'Caída Libre'
        ? 9.81
        : double.tryParse(_accelerationController.text) ?? 0.0;

    double maxPos;
    switch (_selectedMotion) {
      case 'MRU':
        maxPos = v0 * tMax;
        break;
      case 'MRUA':
        maxPos = v0 * tMax + 0.5 * a * tMax * tMax;
        break;
      case 'Caída Libre':
        maxPos = 0.5 * a * tMax * tMax;
        break;
      default:
        maxPos = 1.0;
    }
    return maxPos.clamp(0.0, double.infinity);
  }

  double _calculateFinalVelocity() {
    double tMax = double.tryParse(_timeController.text) ?? 0.0;
    double v0 = double.tryParse(_initialVelocityController.text) ?? 0.0;
    double a = _selectedMotion == 'Caída Libre'
        ? 9.81
        : double.tryParse(_accelerationController.text) ?? 0.0;

    switch (_selectedMotion) {
      case 'MRU':
        return v0;
      case 'MRUA':
        return v0 + a * tMax;
      case 'Caída Libre':
        return a * tMax;
      default:
        return 0.0;
    }
  }

  void _updateGraph() {
    double tMax = double.tryParse(_timeController.text) ?? 0.0;
    if (tMax <= 0) return;

    double t = _animationController.value * tMax;
    double v0 = double.tryParse(_initialVelocityController.text) ?? 0.0;
    double a = _selectedMotion == 'Caída Libre'
        ? 9.81
        : double.tryParse(_accelerationController.text) ?? 0.0;

    double position = 0.0;
    switch (_selectedMotion) {
      case 'MRU':
        position = v0 * t;
        break;
      case 'MRUA':
        position = v0 * t + 0.5 * a * t * t;
        break;
      case 'Caída Libre':
        position = 0.5 * a * t * t;
        break;
    }

    position = position.clamp(0.0, double.infinity);

    setState(() {
      _positionData.add(Offset(t, position));
      _objectPosition = position;
    });
  }

  void _reset() {
    _animationController.stop();
    setState(() {
      _positionData.clear();
      _objectPosition = 0.0;
      _maxPosition = 0.0;
      _finalVelocity = 0.0;
      _initialVelocityController.clear();
      _accelerationController.clear();
      _timeController.clear();
      _selectedMotion = null;
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _initialVelocityController.dispose();
    _accelerationController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gráficas de Movimiento'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reset,
            tooltip: 'Reiniciar',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Tipo de Movimiento',
                  border: OutlineInputBorder(),
                ),
                value: _selectedMotion,
                items: _motions.map((motion) {
                  return DropdownMenuItem<String>(
                    value: motion,
                    child: Text(motion),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedMotion = value;
                    _initialVelocityController.clear();
                    _accelerationController.clear();
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_selectedMotion != 'Caída Libre') ...[
                TextField(
                  controller: _initialVelocityController,
                  decoration: const InputDecoration(
                    labelText: 'Velocidad Inicial (m/s)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
              ],
              if (_selectedMotion == 'MRUA') ...[
                TextField(
                  controller: _accelerationController,
                  decoration: const InputDecoration(
                    labelText: 'Aceleración (m/s²)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _timeController,
                decoration: const InputDecoration(
                  labelText: 'Tiempo Total (s)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _startAnimation,
                child: const Text('Iniciar Animación'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: CustomPaint(
                  painter: GraphPainter(_positionData, _selectedMotion, _maxPosition),
                  child: Container(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 100,
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    double screenWidth = MediaQuery.of(context).size.width - 50;
                    double scaledPosition = _maxPosition > 0 ? (_objectPosition / _maxPosition) * screenWidth : 0.0;
                    return Stack(
                      children: [
                        Positioned(
                          left: scaledPosition.clamp(0, screenWidth),
                          top: 25,
                          child: const Icon(
                            Icons.circle,
                            size: 30,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resultados Finales',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Distancia'),
                          Text('${_maxPosition.toStringAsFixed(2)} m'),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Velocidad Inicial'),
                          Text('${double.tryParse(_initialVelocityController.text)?.toStringAsFixed(2) ?? 0.0} m/s'),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Velocidad Final'),
                          Text('${_finalVelocity.toStringAsFixed(2)} m/s'),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Tiempo'),
                          Text('${double.tryParse(_timeController.text)?.toStringAsFixed(2) ?? 0.0} seg'),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Aceleración'),
                          Text(
                            _selectedMotion == 'Caída Libre'
                                ? '9.81 m/s²'
                                : '${double.tryParse(_accelerationController.text)?.toStringAsFixed(2) ?? 0.0} m/s²',
                          ),
                        ],
                      ),
                    ],
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

class GraphPainter extends CustomPainter {
  final List<Offset> positionData;
  final String? motionType;
  final double maxPosition;

  GraphPainter(this.positionData, this.motionType, this.maxPosition);

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final graphPaint = Paint()
      ..color = Colors.teal
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Dibujar ejes
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), axisPaint); // Eje X
    canvas.drawLine(Offset(0, size.height), Offset(0, 0), axisPaint); // Eje Y

    if (positionData.isEmpty) {
      _drawText(canvas, 'No hay datos', Offset(size.width / 2 - 30, size.height / 2));
      return;
    }

    // Escalar datos
    double maxTime = positionData.last.dx;
    double graphMaxPosition = math.max(maxPosition, positionData.map((p) => p.dy).reduce(math.max));
    if (maxTime <= 0) maxTime = 1.0;
    if (graphMaxPosition <= 0) graphMaxPosition = 1.0;

    double xScale = size.width / maxTime;
    double yScale = size.height / graphMaxPosition;

    // Dibujar marcas y números en el eje X (tiempo)
    const int xTicks = 5;
    double xStep = maxTime / xTicks;
    for (int i = 0; i <= xTicks; i++) {
      double x = i * (size.width / xTicks);
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height + 5), axisPaint);
      _drawText(canvas, (i * xStep).toStringAsFixed(1), Offset(x - 5, size.height + 10));
    }

    // Dibujar marcas y números en el eje Y (posición)
    const int yTicks = 5;
    double yStep = graphMaxPosition / yTicks;
    for (int i = 0; i <= yTicks; i++) {
      double y = size.height - (i * (size.height / yTicks));
      canvas.drawLine(Offset(0, y), Offset(-5, y), axisPaint);
      String label = (i * yStep).toStringAsFixed(1);
      double textX = -50; // Mover más a la izquierda
      double textY = y - 6; // Centrar verticalmente
      if (i == 0) textY = size.height - 15; // Ajustar el 0
      if (i == yTicks) textY = 5; // Ajustar el máximo
      _drawText(canvas, label, Offset(textX, textY));
    }

    // Dibujar gráfica
    Path path = Path();
    path.moveTo(0, size.height);
    for (var point in positionData) {
      double x = point.dx * xScale;
      double y = size.height - (point.dy * yScale);
      path.lineTo(x, y.clamp(0, size.height));
    }
    canvas.drawPath(path, graphPaint);

    // Etiquetas de los ejes
    _drawText(canvas, 'Tiempo (s)', Offset(size.width - 50, size.height - 20));
    _drawText(canvas, 'Posición (m)', const Offset(5, 5));
  }

  void _drawText(Canvas canvas, String text, Offset position) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.black, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}