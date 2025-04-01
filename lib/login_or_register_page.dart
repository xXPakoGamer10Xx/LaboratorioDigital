import 'package:flutter/material.dart';
import 'login_page.dart'; // Pantalla de inicio de sesión
import 'register_page.dart'; // Pantalla de registro

class LoginOrRegisterPage extends StatefulWidget {
  const LoginOrRegisterPage({super.key});

  @override
  State<LoginOrRegisterPage> createState() => _LoginOrRegisterPageState();
}

class _LoginOrRegisterPageState extends State<LoginOrRegisterPage>
    with SingleTickerProviderStateMixin {
  // Controla si se muestra la página de login o registro
  bool showLoginPage = true;

  // Controlador para la animación de transición
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Inicializa el controlador de animación
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 0),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Inicia la animación al cargar la página
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Alterna entre las páginas con animación
  void togglePages() {
    setState(() {
      showLoginPage = !showLoginPage;
      _animationController.reset();
      _animationController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Fondo con gradiente para un diseño más atractivo
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal, Colors.blueGrey],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: showLoginPage
                ? LoginPage(onTap: togglePages)
                : RegisterPage(onTap: togglePages),
          ),
        ),
      ),
    );
  }
}