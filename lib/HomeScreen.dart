import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'MathExpertPage.dart';
import 'IeeeGeneratorPage.dart';
import 'AreaVisualizerPage.dart';
import 'ShapesPage.dart';
import 'MotionGraphPage.dart';
import 'PhysicsExpertPage.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // Muestra un SnackBar con un mensaje
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Cierra la sesión del usuario
  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      _showSnackBar(context, 'Sesión cerrada exitosamente.');
      // AuthGate detectará el cambio y navegará a LoginOrRegisterPage
    } catch (e) {
      _showSnackBar(context, 'Error al cerrar sesión: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final padding = screenSize.width * 0.03;
    final spacing = screenSize.width * 0.02;

    // Número de columnas según el ancho de la pantalla
    final crossAxisCount = screenSize.width > 1200
        ? 4
        : screenSize.width > 800
        ? 3
        : 2;

    // Aspect ratio para los botones
    final childAspectRatio = kIsWeb
        ? (screenSize.width / screenSize.height) * 1.2
        : (screenSize.width / screenSize.height) * 2.0;

    return Scaffold(
      backgroundColor: Colors.grey[100], // Fondo gris claro como antes
      appBar: AppBar(
        title: const Text('Laboratorio Digital'),
        centerTitle: true,
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: GridView.count(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: childAspectRatio,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildButton(
                      context,
                      title: 'Generador de IEEE',
                      icon: Icons.engineering,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const IeeeGeneratorPage()),
                      ),
                    ),
                    _buildButton(
                      context,
                      title: 'Calculadora Matemática',
                      icon: Icons.calculate,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MathExpertPage()),
                      ),
                    ),
                    _buildButton(
                      context,
                      title: 'Visualizador de Áreas',
                      icon: Icons.area_chart,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AreaVisualizerPage()),
                      ),
                    ),
                    _buildButton(
                      context,
                      title: 'Figuras',
                      icon: Icons.shape_line,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ShapesPage()),
                      ),
                    ),
                    _buildButton(
                      context,
                      title: 'Gráficas en Movimiento',
                      icon: Icons.graphic_eq,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MotionGraphPage()),
                      ),
                    ),
                    _buildButton(
                      context,
                      title: 'Calculadora Física',
                      icon: Icons.science,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const PhysicsExpertPage()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton(
      BuildContext context, {
        required String title,
        required IconData icon,
        required VoidCallback onPressed,
      }) {
    final screenSize = MediaQuery.of(context).size;
    final iconSize = (screenSize.width * 0.09).clamp(18.0, 32.0);
    final fontSize = (screenSize.width * 0.045).clamp(10.0, 12.0);
    final buttonPadding = screenSize.width * 0.01;

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.all(buttonPadding),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 5,
        // El color del botón se define en el ThemeData (Colors.teal)
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: iconSize, color: Colors.white),
          SizedBox(height: screenSize.height * 0.01),
          Text(
            title,
            style: TextStyle(fontSize: fontSize, color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}