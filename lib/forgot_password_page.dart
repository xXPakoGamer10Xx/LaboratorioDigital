import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordPage extends StatefulWidget {
  final String? initialEmail; // Email opcional recibido de LoginPage

  const ForgotPasswordPage({super.key, this.initialEmail});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-rellenar el campo si se recibió un email inicial
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // Función para enviar el correo de restablecimiento
  Future<void> sendPasswordResetEmail() async {
    // Evitar múltiples envíos si ya está cargando
    if (!mounted || _isLoading) return;
    final email = _emailController.text.trim();

    // 1. Validación de campo vacío
    if (email.isEmpty) {
      _showErrorSnackBar('Por favor, ingresa tu correo electrónico.');
      return;
    }

    // 2. Validación de formato básico de email
    final emailRegExp = RegExp(
        r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
    if (!emailRegExp.hasMatch(email)) {
      _showErrorSnackBar('Ingrese un correo electrónico válido.');
      return; // Detener si el formato no es válido
    }

    // Si pasa las validaciones, continuar
    setState(() { _isLoading = true; });

    try {
      // 3. Llamada a Firebase (que internamente valida si el usuario existe)
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      // 4. Éxito: Mostrar diálogo y cerrar pantalla
      if(mounted) {
        _showConfirmationDialog(
            'Enlace Enviado',
            'Se ha enviado un enlace para restablecer tu contraseña a $email. Revisa tu bandeja de entrada (y spam).',
            onOkPressed: () {
              if (mounted) {
                // Usar pop consecutivamente es seguro aquí porque el diálogo
                // siempre estará encima de ForgotPasswordPage
                Navigator.of(context).pop(); // Cerrar diálogo
                Navigator.of(context).pop(); // Cerrar pantalla ForgotPasswordPage
              }
            }
        );
        // No quitamos isLoading aquí, se quita antes de mostrar el diálogo
      }

    } on FirebaseAuthException catch (e) { // 5. Error específico de Firebase
      print('Error al enviar correo de restablecimiento: ${e.code}');
      _showErrorSnackBar(_getResetPasswordErrorMessage(e.code));
      // Quitar isLoading en caso de error de Firebase
      if (mounted) { setState(() { _isLoading = false; }); }
    } catch (e) { // 6. Error genérico
      print('Error inesperado en restablecimiento: $e');
      _showErrorSnackBar('Ocurrió un error inesperado.');
      if (mounted) { setState(() { _isLoading = false; }); }
    }
    // No poner finally para quitar isLoading aquí
  }

  // Diálogo de Confirmación
  void _showConfirmationDialog(String title, String content, {VoidCallback? onOkPressed}) {
    if (!mounted) return;
    // Quitar el loading ANTES de mostrar el diálogo de éxito
    if (_isLoading) {
      setState(() { _isLoading = false; });
    }
    showDialog(
      context: context,
      barrierDismissible: false, // Evitar cierre accidental
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: onOkPressed ?? () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // SnackBar de Error
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Mapeo de Errores de Restablecimiento
  String _getResetPasswordErrorMessage(String code) {
    switch (code) {
    // Firebase usa 'user-not-found' si el email no está registrado
      case 'user-not-found':
        return 'No se encontró un usuario con ese correo electrónico.';
    // Firebase usa 'invalid-email' si el formato es inválido en el servidor
      case 'invalid-email':
        return 'El correo electrónico proporcionado no es válido.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde.';
      default:
        return 'Error al enviar correo de restablecimiento ($code)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Restablecer Contraseña'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        // Añadir un leading explícito si se quiere asegurar el botón atrás
        // leading: IconButton(
        //   icon: Icon(Icons.arrow_back, color: Colors.black),
        //   onPressed: () => Navigator.of(context).pop(),
        // ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon( Icons.email_outlined, size: 80, color: Colors.black, ),
                const SizedBox(height: 30),
                const Text( 'Recibe un Enlace', style: TextStyle( fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black, ), ),
                const SizedBox(height: 15),
                Text( 'Ingresa tu correo electrónico registrado y te enviaremos un enlace para restablecer tu contraseña.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey[700]), ),
                const SizedBox(height: 40),

                // Campo de correo
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Correo Electrónico',
                    hintText: 'tu.correo@ejemplo.com',
                    prefixIcon: const Icon(Icons.email_outlined, color: Colors.black),
                    border: OutlineInputBorder( borderRadius: BorderRadius.circular(12), ),
                    filled: true, fillColor: Colors.grey[100],
                    labelStyle: TextStyle(color: Colors.grey[700]), hintStyle: TextStyle(color: Colors.grey[500]),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.black),
                  // Acción del teclado y envío
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!_isLoading) {
                      sendPasswordResetEmail();
                    }
                  },
                ),
                const SizedBox(height: 25),

                // Botón de enviar enlace o indicador de carga
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : ElevatedButton(
                  onPressed: sendPasswordResetEmail,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(55),
                    shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12), ),
                    backgroundColor: Colors.teal, foregroundColor: Colors.white,
                  ),
                  child: const Text( 'Enviar Enlace', style: TextStyle(fontSize: 16), ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}