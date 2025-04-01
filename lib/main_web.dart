import 'package:flutter/material.dart';
import 'dart:async'; // Para usar Timer
import 'HomeScreen.dart';

void main() {
  // Asegura que Flutter esté inicializado antes de ejecutar la app
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyWebApp());
}

class MyWebApp extends StatelessWidget {
  const MyWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Laboratorio Digital',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[100],
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
          titleLarge: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 5,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/Logo.jpg',
              width: 200,
              height: 200,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                    Icons.error, size: 200, color: Colors.black);
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'xXPakoGamer10Xx',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}