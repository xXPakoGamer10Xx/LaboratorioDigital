import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'HomeScreen.dart'; // Pantalla principal de la app
import 'login_or_register_page.dart'; // Pantalla de login o registro

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Fondo opcional para mejorar la experiencia visual
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal, Colors.blueGrey],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: StreamBuilder<User?>(
          // Escucha los cambios en el estado de autenticación de Firebase
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            // Estado de carga: mientras se verifica si hay usuario
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              );
            }

            // Manejo de errores en el stream
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              );
            }

            // Si el usuario está autenticado (snapshot tiene datos)
            if (snapshot.hasData) {
              return const HomeScreen();
            }

            // Si no hay usuario autenticado
            return const LoginOrRegisterPage();
          },
        ),
      ),
    );
  }
}