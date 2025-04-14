import 'package:flutter/material.dart';
import 'dart:math' as math;

class MotionGraphPage extends StatefulWidget {
  const MotionGraphPage({super.key});

  @override
  State<MotionGraphPage> createState() => _MotionGraphPageState();
}

// --- NUEVO: Añadir WidgetsBindingObserver ---
class _MotionGraphPageState extends State<MotionGraphPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  String? _selectedMotion;
  final TextEditingController _initialVelocityController = TextEditingController();
  final TextEditingController _accelerationController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  late AnimationController _animationController;
  List<Offset> _positionData = []; // Almacena (tiempo, posición)
  double _objectPosition = 0.0; // Posición actual para animación del objeto
  double _maxTime = 0.0; // Tiempo total ingresado
  // --- Volver a usar _maxPosition para la escala original de GraphPainter ---
  double _maxPosition = 0.0; // Máxima posición calculada (usada para escalar gráfica y animación)
  double _finalVelocity = 0.0; // Velocidad al final del tiempo

  final List<String> _motions = ['MRU', 'MRUA', 'Caída Libre'];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5), // Duración fija de la animación visual
    )..addListener(() {
      // Actualizar la gráfica y la posición del objeto animado
      _updateSimulationState();
    });
    // --- NUEVO: Registrar observador ---
    WidgetsBinding.instance.addObserver(this);
  }

  // --- NUEVO: Método del ciclo de vida ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Forzar redibujo si la app se reanuda
      if (mounted) {
        setState(() {
          print("MotionGraph Page - App resumed, forcing UI redraw.");
          // Forzar un redibujo es suficiente aquí, los datos se mantienen.
        });
      }
    }
  }


  // Inicia la generación de datos y la animación
  void _startAnimation() {
    // --- Validación de Entradas ---
    if (_selectedMotion == null) {
      _showError('Selecciona un tipo de movimiento.');
      return;
    }
    final timeInput = double.tryParse(_timeController.text);
    if (timeInput == null || timeInput <= 0) {
      _showError('Ingresa un tiempo total válido y positivo.');
      return;
    }
    // Validar otros campos antes de usarlos
    double v0Input = 0.0;
    if (_selectedMotion != 'Caída Libre') {
      v0Input = double.tryParse(_initialVelocityController.text) ?? 0.0; // Default a 0 si es inválido
      // Podríamos mostrar error si es null aquí también
    }
    double aInput = 0.0;
    if (_selectedMotion == 'MRUA') {
      aInput = double.tryParse(_accelerationController.text) ?? 0.0; // Default a 0 si es inválido
      // Podríamos mostrar error si es null aquí también
    }

    _maxTime = timeInput;


    // --- Recalcular maxPosition basado en la lógica original ---
    _maxPosition = _calculateMaxPosition(); // Necesario para GraphPainter y animación original
    _finalVelocity = _calculateFinalVelocity(); // Calcular velocidad final

    // Limpiar datos anteriores y reiniciar animación
    setState(() {
      _positionData.clear(); // Limpiar puntos de la gráfica
      _objectPosition = 0.0; // Resetear posición del objeto animado
    });
    _animationController.reset();
    _animationController.forward(); // Iniciar animación (llamará a _updateSimulationState)
  }

  // Calcula la posición máxima al final del tiempo (usado por GraphPainter y animación)
  double _calculateMaxPosition() {
    double tMax = double.tryParse(_timeController.text) ?? 0.0;
    if (tMax <= 0) return 0.0; // Retornar 0.0 si el tiempo es inválido

    double v0 = 0.0;
    if (_selectedMotion != 'Caída Libre') {
      v0 = double.tryParse(_initialVelocityController.text) ?? 0.0;
    }

    double a = 0.0;
    if (_selectedMotion == 'MRUA') {
      a = double.tryParse(_accelerationController.text) ?? 0.0;
    } else if (_selectedMotion == 'Caída Libre') {
      a = 9.81;
      v0 = 0;
    }

    double finalPos;
    switch (_selectedMotion) {
      case 'MRU':
        finalPos = v0 * tMax;
        break;
      case 'MRUA':
        finalPos = v0 * tMax + 0.5 * a * tMax * tMax;
        break;
      case 'Caída Libre':
        finalPos = 0.5 * a * tMax * tMax; // Asumiendo v0=0
        break;
      default:
        finalPos = 0.0;
    }
    // Devolver el valor calculado. Si es cero, la escala podría necesitar ajuste.
    // Devolver 1.0 si es cero puede distorsionar la escala si la posición real es muy pequeña.
    // Es mejor manejar la escala cero en el painter/builder.
    return finalPos;
  }

  // Calcula la velocidad final
  double _calculateFinalVelocity() {
    double tMax = double.tryParse(_timeController.text) ?? 0.0;
    if (tMax <= 0) return 0.0;

    double v0 = 0.0;
    if (_selectedMotion != 'Caída Libre') {
      v0 = double.tryParse(_initialVelocityController.text) ?? 0.0;
    }

    double a = 0.0;
    if (_selectedMotion == 'MRUA') {
      a = double.tryParse(_accelerationController.text) ?? 0.0;
    } else if (_selectedMotion == 'Caída Libre') {
      a = 9.81;
      v0 = 0;
    }

    switch (_selectedMotion) {
      case 'MRU': return v0;
      case 'MRUA': return v0 + a * tMax;
      case 'Caída Libre': return v0 + a * tMax; // v = v0 + gt
      default: return 0.0;
    }
  }

  // Actualiza el estado de la simulación en cada frame de la animación
  void _updateSimulationState() {
    if (_maxTime <= 0) return; // No hacer nada si el tiempo no es válido

    // Tiempo simulado actual basado en el progreso de la animación
    double t = _animationController.value * _maxTime;

    // Calcular posición actual usando las fórmulas
    double v0 = 0.0;
    if (_selectedMotion != 'Caída Libre') {
      v0 = double.tryParse(_initialVelocityController.text) ?? 0.0;
    }
    double a = 0.0;
    if (_selectedMotion == 'MRUA') {
      a = double.tryParse(_accelerationController.text) ?? 0.0;
    } else if (_selectedMotion == 'Caída Libre') {
      a = 9.81;
      v0 = 0;
    }

    double currentPosition = 0.0;
    switch (_selectedMotion) {
      case 'MRU':
        currentPosition = v0 * t;
        break;
      case 'MRUA':
        currentPosition = v0 * t + 0.5 * a * t * t;
        break;
      case 'Caída Libre':
        currentPosition = 0.5 * a * t * t;
        break;
    }

    // Actualizar estado para redibujar gráfica y objeto
    // Usar setState solo si el widget está montado
    if (mounted) {
      setState(() {
        // Añadir punto actual a la gráfica (si no existe ya uno muy cercano en tiempo)
        if (_positionData.isEmpty || (t - _positionData.last.dx).abs() > (_maxTime / 200)) { // Umbral basado en maxTime
          _positionData.add(Offset(t, currentPosition));
        } else if (_positionData.isNotEmpty) {
          // Opcional: actualizar el último punto si el tiempo es muy cercano
          _positionData.last = Offset(t, currentPosition);
        }
        // Actualizar posición para la animación del objeto
        _objectPosition = currentPosition;
      });
    }

  }


  // Reinicia el estado de la simulación
  void _reset() {
    _animationController.stop();
    // Usar setState solo si el widget está montado
    if (mounted) {
      setState(() {
        _positionData.clear();
        _objectPosition = 0.0;
        _maxTime = 0.0;
        _maxPosition = 0.0; // Resetear maxPosition también
        _finalVelocity = 0.0;
        _initialVelocityController.clear();
        _accelerationController.clear();
        _timeController.clear();
        _selectedMotion = null;
      });
    }

  }

  // Muestra un SnackBar de error
  void _showError(String message) {
    // Asegurarse de que el contexto es válido antes de mostrar SnackBar
    if (mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    }
  }


  @override
  void dispose() {
    _animationController.dispose();
    _initialVelocityController.dispose();
    _accelerationController.dispose();
    _timeController.dispose();
    // --- NUEVO: Remover observador ---
    WidgetsBinding.instance.removeObserver(this);
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
          onPressed: () => Navigator.pop(context),
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
              // --- Selección de Movimiento ---
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Tipo de Movimiento', border: OutlineInputBorder()),
                value: _selectedMotion,
                items: _motions.map((motion) => DropdownMenuItem<String>(value: motion, child: Text(motion))).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedMotion = value;
                    _initialVelocityController.clear();
                    _accelerationController.clear();
                  });
                },
              ),
              const SizedBox(height: 16),

              // --- Campos de Entrada ---
              if (_selectedMotion != 'Caída Libre') ...[
                TextField(
                  controller: _initialVelocityController,
                  decoration: const InputDecoration(labelText: 'Velocidad Inicial (m/s)', border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
              ],
              if (_selectedMotion == 'MRUA') ...[
                TextField(
                  controller: _accelerationController,
                  decoration: const InputDecoration(labelText: 'Aceleración (m/s²)', border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _timeController,
                decoration: const InputDecoration(labelText: 'Tiempo Total (s)', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _startAnimation(), // Iniciar al presionar Done
              ),
              const SizedBox(height: 16),

              // --- Botón de Inicio ---
              ElevatedButton(
                onPressed: _startAnimation,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('Iniciar Simulación', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 24),

              // --- Gráfica de Posición vs Tiempo (Usando CustomPaint) ---
              Text("Posición vs Tiempo", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                height: 250, // Altura fija para la gráfica
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50], // Fondo ligero para la gráfica
                ),
                child: CustomPaint(
                  // Pasar los datos y los límites calculados al Painter
                  // Asegurarse de que maxPosition no sea cero para evitar división por cero en Painter
                  painter: GraphPainter(_positionData, _maxTime, _maxPosition == 0 ? 1.0 : _maxPosition),
                  child: Container(), // Container vacío necesario para que CustomPaint tenga tamaño
                ),
              ),
              const SizedBox(height: 24),

              // --- Animación del Objeto ---
              Text("Animación", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
                ),
                child: LayoutBuilder( // Usar LayoutBuilder para obtener el ancho disponible
                    builder: (context, constraints) {
                      double screenWidth = constraints.maxWidth; // Ancho disponible para la animación
                      const double iconWidth = 30.0; // Ancho aproximado del icono

                      // Escalar la posición del objeto (_objectPosition) al ancho disponible.
                      // La escala original dependía de _maxPosition.
                      // Usar el valor absoluto de maxPosition para la escala para manejar negativos.
                      // Si maxPosition es 0, la escala es 0 (o screenWidth si queremos que ocupe todo).
                      double effectiveMaxPosMagnitude = _maxPosition.abs();
                      if (effectiveMaxPosMagnitude < 1e-6) effectiveMaxPosMagnitude = 1.0; // Evitar división por cero o escala infinita

                      double scaleFactor = screenWidth / effectiveMaxPosMagnitude;

                      // Calcular posición en pantalla.
                      // Esta lógica simple asume que la animación siempre empieza en 0 (izquierda).
                      double scaledPosition = _objectPosition * scaleFactor;

                      // CORRECCIÓN: Ajustar el clamp para que el icono no se salga
                      // El límite superior debe ser el ancho menos el ancho del icono.
                      // Asegurarse de que el límite no sea negativo si la pantalla es muy estrecha.
                      double maxLeftPosition = (screenWidth - iconWidth).clamp(0.0, double.infinity);
                      scaledPosition = scaledPosition.clamp(0.0, maxLeftPosition);


                      return Stack(
                        children: [
                          Positioned(
                            left: scaledPosition,
                            bottom: 15,
                            child: const Icon(Icons.directions_run, size: iconWidth, color: Colors.teal),
                          ),
                        ],
                      );
                    }
                ),
              ),
              const SizedBox(height: 24),

              // --- Resultados Finales ---
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Resultados Finales', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      // Mostrar la posición calculada al final del tiempo _maxTime
                      _buildResultRow('Posición Final:', '${_calculatePositionAtTime(_maxTime).toStringAsFixed(2)} m'),
                      _buildResultRow('Velocidad Inicial:', '${(double.tryParse(_initialVelocityController.text) ?? 0.0).toStringAsFixed(2)} m/s'),
                      _buildResultRow('Velocidad Final:', '${_finalVelocity.toStringAsFixed(2)} m/s'),
                      _buildResultRow('Tiempo Total:', '${_maxTime.toStringAsFixed(2)} s'),
                      _buildResultRow('Aceleración:', '${_getAccelerationValue()} m/s²'),

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

  // Helper para calcular posición en un tiempo t específico (usado para resultados finales)
  double _calculatePositionAtTime(double t) {
    if (t < 0) return 0.0;
    double v0 = 0.0;
    if (_selectedMotion != 'Caída Libre') {
      v0 = double.tryParse(_initialVelocityController.text) ?? 0.0;
    }
    double a = 0.0;
    if (_selectedMotion == 'MRUA') {
      a = double.tryParse(_accelerationController.text) ?? 0.0;
    } else if (_selectedMotion == 'Caída Libre') {
      a = 9.81;
      v0 = 0;
    }

    switch (_selectedMotion) {
      case 'MRU': return v0 * t;
      case 'MRUA': return v0 * t + 0.5 * a * t * t;
      case 'Caída Libre': return 0.5 * a * t * t;
      default: return 0.0;
    }
  }


  // Helper para obtener el valor de aceleración a mostrar
  String _getAccelerationValue() {
    switch (_selectedMotion) {
      case 'MRU': return '0.00';
      case 'MRUA': return (double.tryParse(_accelerationController.text) ?? 0.0).toStringAsFixed(2);
      case 'Caída Libre': return '9.81';
      default: return 'N/A';
    }
  }

  // Helper para construir filas de resultados
  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

}


// --- Clase CustomPainter para la Gráfica (Restaurada) ---
class GraphPainter extends CustomPainter {
  final List<Offset> positionData; // Lista de (tiempo, posición)
  final double maxTime;
  // Volver a usar maxPosition para la escala Y como en la versión original
  // pero asegurando que no sea cero para evitar división por cero.
  final double maxPosition;

  GraphPainter(this.positionData, this.maxTime, this.maxPosition);

  @override
  void paint(Canvas canvas, Size size) {
    // --- Configuración de Pintura ---
    final axisPaint = Paint()..color = Colors.grey..strokeWidth = 1..style = PaintingStyle.stroke;
    final gridPaint = Paint()..color = Colors.grey.shade300..strokeWidth = 0.5..style = PaintingStyle.stroke;
    final graphPaint = Paint()..color = Colors.teal..strokeWidth = 2..style = PaintingStyle.stroke;
    final textStyle = const TextStyle(color: Colors.black54, fontSize: 10);

    // --- Dibujar Ejes ---
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), axisPaint); // Eje X
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), axisPaint); // Eje Y

    if (positionData.isEmpty || maxTime <= 0) return;

    // --- Calcular Escala ---
    double effectiveMaxTime = maxTime <= 0 ? 1.0 : maxTime;
    double xScale = size.width / effectiveMaxTime;

    // Usar la magnitud de maxPosition para la escala, pero asegurar que sea al menos 1.0
    // Esto mantiene la escala original pero evita división por cero.
    // NOTA: Esto aún puede ocultar valores negativos si maxPosition es positivo.
    // Para un escalado que muestre negativos, necesitaríamos min/max Y.
    double effectiveMaxPosMagnitude = maxPosition.abs();
    if (effectiveMaxPosMagnitude < 1e-6) effectiveMaxPosMagnitude = 1.0; // Evitar cero o muy pequeño
    double yScale = size.height / effectiveMaxPosMagnitude;


    // --- Dibujar Rejilla y Marcas ---
    const int xTicks = 5;
    double xStepValue = effectiveMaxTime / xTicks;
    for (int i = 0; i <= xTicks; i++) {
      double xVal = i * xStepValue;
      double xPos = xVal * xScale;
      canvas.drawLine(Offset(xPos, 0), Offset(xPos, size.height), gridPaint);
      _drawText(canvas, xVal.toStringAsFixed(1), Offset(xPos - 5, size.height + 4), textStyle);
    }

    const int yTicks = 5;
    // Marcas Y basadas en la magnitud de maxPosition
    double yStepValue = effectiveMaxPosMagnitude / yTicks;
    for (int i = 0; i <= yTicks; i++) {
      double yVal = i * yStepValue;
      // Calcular posición Y en pantalla: Invertir desde la altura total
      // Esta escala asume que 0 está en la parte inferior.
      double yPos = size.height - (yVal * yScale);
      if (yPos >= -5 && yPos <= size.height + 5) { // Dibujar solo si visible
        canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
        _drawText(canvas, yVal.toStringAsFixed(1), Offset(-30, yPos - 6), textStyle, textAlign: TextAlign.right);
      }
      // Si quisiéramos manejar negativos, necesitaríamos calcular el y=0 position
      // double yZeroPos = size.height - (0 * yScale); // Asumiendo escala desde 0
    }


    // --- Dibujar Gráfica ---
    Path path = Path();
    if (positionData.isNotEmpty) {
      // Mover al primer punto
      double firstX = positionData.first.dx * xScale;
      // Escalar Y desde la parte inferior basado en la escala de magnitud
      double firstY = size.height - (positionData.first.dy * yScale);
      path.moveTo(firstX.clamp(0, size.width), firstY.clamp(0, size.height)); // Clamp inicial

      for (int i = 1; i < positionData.length; i++) {
        double x = positionData[i].dx * xScale;
        double y = size.height - (positionData[i].dy * yScale);
        path.lineTo(x.clamp(0, size.width), y.clamp(0, size.height)); // Clamp en cada punto
      }
      canvas.drawPath(path, graphPaint);
    }


    // --- Etiquetas de los Ejes ---
    _drawText(canvas, 'Tiempo (s)', Offset(size.width - 50, size.height - 15), textStyle);
    _drawText(canvas, 'Posición (m)', const Offset(5, 5), textStyle);
  }

  // Helper para dibujar texto
  void _drawText(Canvas canvas, String text, Offset position, TextStyle style, {TextAlign textAlign = TextAlign.left}) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr, textAlign: textAlign);
    textPainter.layout(minWidth: 0, maxWidth: 50); // Limitar ancho para etiquetas Y
    // Ajustar offset para evitar que se salga del canvas
    double finalX = position.dx;
    if (textAlign == TextAlign.right && finalX + textPainter.width > 0) {
      // Si es alineado a la derecha y se sale por la izquierda, ajustar (poco probable con -30)
    } else if (textAlign == TextAlign.left && finalX < 0) {
      finalX = 0; // Evitar que se salga por la izquierda
    }
    textPainter.paint(canvas, Offset(finalX, position.dy));

  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}