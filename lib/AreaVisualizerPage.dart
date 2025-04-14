import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:math_expressions/math_expressions.dart';
import 'dart:math' as math;

class AreaVisualizerPage extends StatefulWidget {
  const AreaVisualizerPage({super.key});

  @override
  State<AreaVisualizerPage> createState() => _AreaVisualizerPageState();
}

class _AreaVisualizerPageState extends State<AreaVisualizerPage> with WidgetsBindingObserver {
  final TextEditingController _expressionController = TextEditingController();
  final TextEditingController _minXController = TextEditingController(text: '-10');
  final TextEditingController _maxXController = TextEditingController(text: '10');
  List<FlSpot> _points = [];
  double _area = 0.0;
  String _errorMessage = '';
  String _latexExpression = '';

  // Lista de funciones soportadas para los botones
  final List<Map<String, String>> _supportedFunctions = [
    {'name': 'sin', 'latex': '\\sin(x)'}, {'name': 'cos', 'latex': '\\cos(x)'},
    {'name': 'tan', 'latex': '\\tan(x)'}, {'name': 'csc', 'latex': '\\csc(x)'},
    {'name': 'sec', 'latex': '\\sec(x)'}, {'name': 'cot', 'latex': '\\cot(x)'},
    {'name': 'ln', 'latex': '\\ln(x)'}, {'name': 'log', 'latex': '\\log_{10}(x)'},
    {'name': 'sqrt', 'latex': '\\sqrt{x}'}, {'name': 'exp', 'latex': 'e^{x}'},
    {'name': 'abs', 'latex': '|x|'}, {'name': 'asin', 'latex': '\\arcsin(x)'},
    {'name': 'acos', 'latex': '\\arccos(x)'},{'name': 'atan', 'latex': '\\arctan(x)'},
    {'name': 'x^2', 'latex': 'x^{2}'}, {'name': 'x^3', 'latex': 'x^{3}'},
    {'name': 'x^(1/n)', 'latex': '\\sqrt[n]{x}'}, {'name': 'pi', 'latex': '\\pi'},
    {'name': 'e', 'latex': 'e'},
  ];

  final List<String> _functionsNeedingParentheses = [
    'sin', 'cos', 'tan', 'csc', 'sec', 'cot', 'ln', 'log', 'sqrt', 'exp', 'abs', 'asin', 'acos', 'atan'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() { print("AreaVisualizer Page - App resumed, forcing UI redraw."); });
      }
    }
  }

  // Función de evaluación principal
  double _evaluateExpression(String expression, double x) {
    String processedExpression = expression;
    String finalExpression = '';
    try {
      Parser p = Parser();
      processedExpression = processedExpression.toLowerCase();

      // Reemplazar constantes
      processedExpression = processedExpression
          .replaceAll('pi', '(${math.pi})')
          .replaceAllMapped(RegExp(r'(?<![a-z])e(?![a-z])'), (match) => '(${math.e})');

      // Reemplazar funciones para math_expressions
      processedExpression = processedExpression
          .replaceAllMapped(RegExp(r'\blog\s*\(([^)]*)\)'), (m) => '(ln(${m[1]})/ln(10))') // log() -> ln()/ln(10)
          .replaceAllMapped(RegExp(r'\bln\s*\(([^)]*)\)'), (m) => 'ln(${m[1]})')       // ln() -> ln()
          .replaceAllMapped(RegExp(r'\basin\s*\(([^)]*)\)'), (m) => 'arcsin(${m[1]})') // asin() -> arcsin()
          .replaceAllMapped(RegExp(r'\bacos\s*\(([^)]*)\)'), (m) => 'arccos(${m[1]})') // acos() -> arccos()
          .replaceAllMapped(RegExp(r'\batan\s*\(([^)]*)\)'), (m) => 'arctan(${m[1]})') // atan() -> arctan()
          .replaceAllMapped(RegExp(r'\bcsc\s*\(([^)]*)\)'), (m) => '(1/sin(${m[1]}))')  // csc() -> 1/sin()
          .replaceAllMapped(RegExp(r'\bsec\s*\(([^)]*)\)'), (m) => '(1/cos(${m[1]}))')  // sec() -> 1/cos()
          .replaceAllMapped(RegExp(r'\bcot\s*\(([^)]*)\)'), (m) => '(1/tan(${m[1]}))')  // cot() -> 1/tan()
          .replaceAllMapped(RegExp(r'\bsqrt\s*\(([^)]*)\)'), (m) => 'sqrt(${m[1]})')    // sqrt() -> sqrt()
          .replaceAllMapped(RegExp(r'\bexp\s*\(([^)]*)\)'), (m) => 'exp(${m[1]})')      // exp() -> exp()
          .replaceAllMapped(RegExp(r'\babs\s*\(([^)]*)\)'), (m) => 'abs(${m[1]})');     // abs() -> abs()

      // Reemplazar 'x' variable
      finalExpression = processedExpression.replaceAllMapped(
          RegExp(r'(?<![a-z])x(?![a-z])'),
              (match) => '(${x.toString()})'
      );

      Expression exp = p.parse(finalExpression);
      ContextModel cm = ContextModel();
      double result = exp.evaluate(EvaluationType.REAL, cm);

      if (result.isNaN || result.isInfinite) {
        return double.nan;
      }
      return result;

    } catch (e) {
      print("Error evaluating expression '$expression' [Final attempt: '$finalExpression'] at x=$x: $e");
      if (mounted && (_errorMessage.isEmpty || !_errorMessage.contains('Error en expresión'))) {
        setState(() { _errorMessage = 'Error en expresión. Verifique sintaxis y uso de *.'; });
      }
      return double.nan;
    }
  }

  // Función para convertir a LaTeX (solo visualización)
  String _toLatex(String expression) {
    String latex = expression
        .replaceAll('*', '\\cdot ')
        .replaceAllMapped(RegExp(r'x\^([\d\.\-]+)'), (m) => 'x^{${m[1]}}')
        .replaceAllMapped(RegExp(r'x\^\(([^)]+)\)'), (m) => 'x^{${m[1]}}')
        .replaceAllMapped(RegExp(r'x\^\(1/(\d+)\)'), (m) => '\\sqrt[${m[1]}]{x}')
        .replaceAllMapped(RegExp(r'sqrt\(([^)]*)\)'), (m) => '\\sqrt{${m[1]}}')
        .replaceAllMapped(RegExp(r'abs\(([^)]*)\)'), (m) => '|${m[1]}|')
        .replaceAllMapped(RegExp(r'log\(([^)]*)\)'), (m) => '\\log_{10}(${m[1]})')
        .replaceAllMapped(RegExp(r'ln\(([^)]*)\)'), (m) => '\\ln(${m[1]})')
        .replaceAllMapped(RegExp(r'sin\(([^)]*)\)'), (m) => '\\sin(${m[1]})')
        .replaceAllMapped(RegExp(r'cos\(([^)]*)\)'), (m) => '\\cos(${m[1]})')
        .replaceAllMapped(RegExp(r'tan\(([^)]*)\)'), (m) => '\\tan(${m[1]})')
        .replaceAllMapped(RegExp(r'csc\(([^)]*)\)'), (m) => '\\csc(${m[1]})')
        .replaceAllMapped(RegExp(r'sec\(([^)]*)\)'), (m) => '\\sec(${m[1]})')
        .replaceAllMapped(RegExp(r'cot\(([^)]*)\)'), (m) => '\\cot(${m[1]})')
        .replaceAllMapped(RegExp(r'asin\(([^)]*)\)'), (m) => '\\arcsin(${m[1]})')
        .replaceAllMapped(RegExp(r'acos\(([^)]*)\)'), (m) => '\\arccos(${m[1]})')
        .replaceAllMapped(RegExp(r'atan\(([^)]*)\)'), (m) => '\\arctan(${m[1]})')
        .replaceAllMapped(RegExp(r'exp\(([^)]*)\)'), (m) => 'e^{${m[1]}}')
        .replaceAll('pi', '\\pi')
        .replaceAllMapped(RegExp(r'(?<![a-zA-Z])e(?![a-zA-Z])'), (match) => '{e}');

    latex = latex.replaceAllMapped(RegExp(r'\((.+?)\)/\((.+?)\)'), (m) => '\\frac{${m[1]}}{${m[2]}}');
    latex = latex.replaceAllMapped(RegExp(r'([^ ]+)/([^ ]+)'), (m) {
      if (m[0]!.contains(r'\frac')) return m[0]!;
      return '\\frac{${m[1]}}{${m[2]}}';
    });

    return latex;
  }

  // Generar los puntos para la gráfica y calcular el área
  void _generatePlot() {
    setState(() {
      _points.clear(); _errorMessage = ''; _area = 0.0;
      _latexExpression = _expressionController.text.isNotEmpty ? _toLatex(_expressionController.text) : '';
    });

    final expression = _expressionController.text.trim();
    if (expression.isEmpty) {
      setState(() { _errorMessage = 'Por favor, ingrese una función'; }); return;
    }

    double? minX, maxX;
    try {
      minX = double.tryParse(_minXController.text); maxX = double.tryParse(_maxXController.text);
      if (minX == null || maxX == null) { setState(() { _errorMessage = 'Límites X deben ser válidos'; }); return; }
      if (minX >= maxX) { setState(() { _errorMessage = 'Mín X < Máx X'; }); return; }

      const int steps = 200; double step = (maxX - minX) / steps;
      List<FlSpot> tempPoints = []; List<double> xValA = []; List<double> yValA = [];
      bool hasValid = false; bool errorOccurred = false;

      _errorMessage = ''; // Reiniciar error

      for (int i = 0; i <= steps; i++) {
        double x = minX + i * step; x = double.parse(x.toStringAsFixed(8));
        double y = _evaluateExpression(expression, x);

        if (_errorMessage.isNotEmpty && _errorMessage.contains('Error en expresión')) {
          errorOccurred = true;
          // break; // Opcional: detener si ocurre un error
        }

        if (!y.isNaN && !y.isInfinite) {
          tempPoints.add(FlSpot(x, y)); xValA.add(x); yValA.add(y); hasValid = true;
        } else { print("Skip invalid point x=$x (y=$y)"); }
      }

      double calcArea = 0.0;
      if (xValA.length > 1) {
        for (int i = 1; i < xValA.length; i++) {
          double x0 = xValA[i - 1], x1 = xValA[i], y0 = yValA[i - 1], y1 = yValA[i];
          if (y0.isFinite && y1.isFinite) { calcArea += (y0 + y1) * (x1 - x0) / 2.0; }
        }
      }

      if(hasValid){
        setState(() { _points = tempPoints; _area = calcArea; });
      } else if (!errorOccurred) {
        setState(() { _errorMessage = 'No se generaron puntos válidos en el rango.'; });
      }

    } catch (e) {
      print("Error plot: $e");
      setState(() { _errorMessage = 'Error al graficar: ${e.toString()}'; _points.clear(); _area = 0.0; });
    }
  }

  Future<String?> _promptForRootIndex(BuildContext context) async {
    final TextEditingController indexController = TextEditingController();
    return showDialog<String>( context: context, builder: (context) => AlertDialog( title: const Text('Índice raíz'), content: TextField(controller: indexController, decoration: const InputDecoration(labelText: 'Ingrese n (ej. 2)', hintText: 'Entero > 1'), keyboardType: TextInputType.number, autofocus: true), actions: [ TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), TextButton( onPressed: () { final index = int.tryParse(indexController.text); if (index != null && index > 1) { Navigator.pop(context, index.toString()); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingrese entero > 1'), duration: Duration(seconds: 2))); } }, child: const Text('Aceptar'), ), ], ), );
  }

  void _showFunctionButtons() {
    showModalBottomSheet( context: context, isScrollControlled: true, builder: (context) => LayoutBuilder( builder: (context, constraints) { final isWide = constraints.maxWidth >= 600; final crossAxisCount = isWide ? 5 : 3; final rowCount = (_supportedFunctions.length / crossAxisCount).ceil(); final height = (rowCount * 65.0) + 80.0; return Container( height: height.clamp(200, 400), padding: const EdgeInsets.all(16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [ const Text('Insertar función', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 10), Expanded( child: GridView.builder( gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.8), itemCount: _supportedFunctions.length, itemBuilder: (context, index) { final func = _supportedFunctions[index]; return ElevatedButton( style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), textStyle: const TextStyle(fontSize: 14)), onPressed: () async { String baseName = func['name']!; String textToIns = baseName; bool placeCursorIn = false; if (baseName == 'x^(1/n)') { final nIdx = await _promptForRootIndex(context); if (nIdx != null) { textToIns = 'x^(1/$nIdx)'; } else { return; } } else if (_functionsNeedingParentheses.contains(baseName)) { textToIns = '$baseName()'; placeCursorIn = true; } else if (baseName == 'pi' || baseName == 'e') { textToIns = baseName; } final ctrl = _expressionController; final currentVal = ctrl.value; final sel = currentVal.selection; final newTxt = currentVal.text.replaceRange(sel.start, sel.end, textToIns); int newOff; if (placeCursorIn) { newOff = sel.start + textToIns.length - 1; } else { newOff = sel.start + textToIns.length; } ctrl.value = TextEditingValue(text: newTxt, selection: TextSelection.collapsed(offset: newOff)); setState(() { _latexExpression = _toLatex(ctrl.text); }); Navigator.pop(context); }, child: Math.tex(func['latex']!, textStyle: const TextStyle(fontSize: 16)), ); }, ), ), ], ), ); }, ), );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualizador de Áreas'),
        actions: [
          IconButton(icon: const Icon(Icons.functions), tooltip: 'Insertar función', onPressed: _showFunctionButtons),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Recalcular', onPressed: _generatePlot),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _expressionController,
                decoration: const InputDecoration(
                    labelText: 'Función f(x)',
                    hintText: 'Ej: 2*x^3 + sin(pi*x) (use * para multiplicar)', // Recordatorio de '*'
                    border: OutlineInputBorder()
                ),
                style: const TextStyle(fontSize: 16),
                onChanged: (value) { setState(() { _latexExpression = _toLatex(value); }); },
                onSubmitted: (_) => _generatePlot(),
              ),
              const SizedBox(height: 10),
              if (_latexExpression.isNotEmpty) Container( padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)), child: Center(child: Math.tex('f(x) = $_latexExpression', mathStyle: MathStyle.display, textStyle: const TextStyle(fontSize: 20), onErrorFallback: (e) => Text('Error LaTeX: ${e.message}'))), ),
              const SizedBox(height: 10),
              Row( children: [ Expanded(child: TextField(controller: _minXController, decoration: const InputDecoration(labelText: 'Mínimo X', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true), onSubmitted: (_) => _generatePlot())), const SizedBox(width: 10), Expanded(child: TextField(controller: _maxXController, decoration: const InputDecoration(labelText: 'Máximo X', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true), onSubmitted: (_) => _generatePlot())), ], ),
              const SizedBox(height: 15),
              ElevatedButton.icon(icon: const Icon(Icons.analytics_outlined), label: const Text('Graficar y Calcular Área'), onPressed: _generatePlot, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), textStyle: const TextStyle(fontSize: 16))),
              // Mostrar mensaje de error si existe
              AnimatedSwitcher( // Para animar la aparición/desaparición del error
                duration: const Duration(milliseconds: 300),
                child: _errorMessage.isNotEmpty
                    ? Padding(
                  key: ValueKey(_errorMessage), // Key para que AnimatedSwitcher detecte el cambio
                  padding: const EdgeInsets.only(top: 15.0),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                )
                    : const SizedBox.shrink(key: ValueKey('noError')), // Ocupa espacio cero si no hay error
              ),
              const SizedBox(height: 20),
              // Gráfica
              Container(
                height: 350, padding: const EdgeInsets.only(top: 10, right: 10), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                child: LineChart(
                  LineChartData(
                    // *** Parámetros de animación ELIMINADOS por incompatibilidad ***
                    // swapAnimationDuration: const Duration(milliseconds: 250),
                    // swapAnimationCurve: Curves.linear,

                    // ... (resto de la configuración de LineChartData) ...
                    gridData: FlGridData(show: true, drawVerticalLine: true, horizontalInterval: _calculateInterval(_points.map((p) => p.y).where((y) => y.isFinite).toList()), verticalInterval: _calculateInterval(_points.map((p) => p.x).where((x) => x.isFinite).toList()), getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade300, strokeWidth: 0.5), getDrawingVerticalLine: (v) => FlLine(color: Colors.grey.shade300, strokeWidth: 0.5)),
                    titlesData: FlTitlesData(bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: _calculateInterval(_points.map((p) => p.x).where((x) => x.isFinite).toList()), getTitlesWidget: _bottomTitleWidgets)), leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 45, interval: _calculateInterval(_points.map((p) => p.y).where((y) => y.isFinite).toList()), getTitlesWidget: _leftTitleWidgets)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
                    borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade400, width: 1)),
                    lineBarsData: [ LineChartBarData(spots: _points, isCurved: true, gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.lightBlueAccent]), barWidth: 3, isStrokeCapRound: true, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.blueAccent.withOpacity(0.3), Colors.lightBlueAccent.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter))) ],
                    lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) => LineTooltipItem('(${spot.x.toStringAsFixed(2)}, ${spot.y.toStringAsFixed(2)})', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))).toList()
                        ),
                        handleBuiltInTouches: true
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              // Área calculada (mostrar solo si no hay error y hay puntos)
              if (_points.isNotEmpty && _errorMessage.isEmpty)
                Center(child: Text('Área ≈ ${_area.abs().toStringAsFixed(4)}\n(Integral ≈ ${_area.toStringAsFixed(4)})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 12);
    String text; double interval = meta.appliedInterval;
    // Evitar precisión innecesaria si el intervalo es >= 1
    if (interval >= 1.0) {
      text = value.toInt().toString();
    } else {
      text = value.toStringAsFixed(1); // Mostrar 1 decimal para intervalos < 1
    }
    if (value > -0.001 && value < 0.001) text = "0"; // Asegurar que 0 se muestre como 0
    return SideTitleWidget(axisSide: meta.axisSide, space: 8.0, child: Text(text, style: style));
  }

  Widget _leftTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 12);
    String text; double interval = meta.appliedInterval;
    if (interval >= 1.0) {
      text = value.toInt().toString();
    } else {
      text = value.toStringAsFixed(1);
    }
    if (value > -0.001 && value < 0.001) text = "0";
    return SideTitleWidget(axisSide: meta.axisSide, space: 8.0, child: Text(text, style: style, textAlign: TextAlign.right));
  }

  double _calculateInterval(List<double> values) {
    if (values.isEmpty) return 1.0;
    final finiteValues = values.where((v) => v.isFinite).toList();
    if (finiteValues.isEmpty) return 1.0;
    double minVal = finiteValues.reduce(math.min); double maxVal = finiteValues.reduce(math.max);
    double range = maxVal - minVal;
    if (range <= 1e-9 || !range.isFinite) { // Usar un epsilon pequeño para rangos muy cercanos a cero
      // Si el rango es muy pequeño, basar el intervalo en la magnitud del valor
      double absMax = math.max(minVal.abs(), maxVal.abs());
      if (absMax < 1e-9) return 0.1; // Intervalo pequeño si cerca de 0
      // Calcular magnitud para logaritmo base 10
      double log10AbsMax = absMax == 0 ? -1 : math.log(absMax) / math.ln10; // Evitar log(0)
      return math.pow(10, log10AbsMax.floor() -1).toDouble().clamp(1e-6, 1.0); // Intervalo basado en magnitud
    }
    // Intentar ~5-6 intervalos visibles
    double interval = range / 5.0;
    if (interval <= 0 || !interval.isFinite) return 1.0;
    try {
      // Redondeo a número "agradable" (potencia de 10, 5, 2)
      double log10Interval = math.log(interval) / math.ln10;
      double magnitude = math.pow(10, log10Interval.floor()).toDouble();
      if (magnitude <= 0 || !magnitude.isFinite) return 1.0;
      double residual = interval / magnitude; // >= 1.0
      double niceInterval;
      if (residual > 5) niceInterval = 10 * magnitude;
      else if (residual > 2) niceInterval = 5 * magnitude;
      else if (residual > 1) niceInterval = 2 * magnitude;
      else niceInterval = 1 * magnitude;
      // Asegurarse de que el intervalo no sea extremadamente pequeño
      return niceInterval.clamp(1e-6, double.maxFinite);
    } catch (e) { print("Error calc interval: $e"); return 1.0; }
  }


  @override
  void dispose() {
    _expressionController.dispose(); _minXController.dispose(); _maxXController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
