import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'forgot_password_page.dart'; // Importa la página de restablecimiento

class LoginPage extends StatefulWidget {
  final VoidCallback? onTap; // Callback para ir a la página de registro

  const LoginPage({super.key, this.onTap});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordObscured = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Inicia sesión con Firebase Authentication
  Future<void> signIn() async {
    // Añadir comprobación extra por si se llama desde onSubmitted mientras ya carga
    if (!mounted || _isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showErrorSnackBar('Por favor, completa todos los campos.');
      return;
    }
    setState(() { _isLoading = true; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      print('Inicio de sesión exitoso: ${FirebaseAuth.instance.currentUser?.email}');
      // AuthGate manejará la navegación
    } on FirebaseAuthException catch (e) {
      print('Error de Firebase Auth al iniciar sesión: ${e.code}');
      _showErrorSnackBar(_getLoginAuthErrorMessage(e.code));
    } catch (e) {
      print('Error inesperado al iniciar sesión: $e');
      _showErrorSnackBar('Ocurrió un error inesperado.');
    } finally {
      // Asegurarse de que el estado de carga se quite solo si el widget sigue montado
      if (mounted) { setState(() { _isLoading = false; }); }
    }
  }

  // Muestra un SnackBar con el mensaje de error
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

  // Mapea códigos de error de Login
  String _getLoginAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
      case 'invalid-credential':
        return 'Correo o contraseña incorrectos.';
      case 'wrong-password':
        return 'Contraseña incorrecta.';
      case 'invalid-email':
        return 'El formato del correo electrónico no es válido.';
      case 'user-disabled':
        return 'Este usuario ha sido deshabilitado.';
      case 'too-many-requests':
        return 'Demasiados intentos fallidos. Intenta más tarde.';
      default:
        return 'Error al iniciar sesión ($code)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon( Icons.lock_open_rounded, size: 80, color: Colors.black, ),
                const SizedBox(height: 30),
                const Text( '¡Bienvenido de Nuevo!', style: TextStyle( fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black, ), ),
                const SizedBox(height: 10),
                Text( 'Inicia sesión para continuar', style: TextStyle(fontSize: 16, color: Colors.grey[700]), ),
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
                  // Acción para ir al siguiente campo (contraseña)
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: Colors.black),
                  // onSubmitted: (_){ // Opcional: mover foco al siguiente campo
                  //   FocusScope.of(context).nextFocus();
                  // },
                ),
                const SizedBox(height: 15),

                // Campo de contraseña
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.black),
                    border: OutlineInputBorder( borderRadius: BorderRadius.circular(12), ),
                    filled: true, fillColor: Colors.grey[100],
                    labelStyle: TextStyle(color: Colors.grey[700]), hintStyle: TextStyle(color: Colors.grey[500]),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordObscured ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey[600],
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordObscured = !_isPasswordObscured;
                        });
                      },
                    ),
                  ),
                  obscureText: _isPasswordObscured,
                  style: const TextStyle(color: Colors.black),
                  // --- NUEVO: Acción e Invocación al Enviar ---
                  textInputAction: TextInputAction.done, // Mostrar botón "listo/ir"
                  onSubmitted: (_) { // Se ejecuta al presionar la acción del teclado
                    if (!_isLoading) { // Solo si no está ya cargando
                      signIn(); // Llama a la misma función del botón
                    }
                  },
                  // --- FIN NUEVO ---
                ),
                const SizedBox(height: 10),

                // Enlace Olvidaste Contraseña
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () {
                          final email = _emailController.text.trim();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ForgotPasswordPage(
                                initialEmail: email,
                              ),
                            ),
                          );
                        },
                        child: Text(
                          '¿Olvidaste tu contraseña?',
                          style: TextStyle(
                            color: Colors.teal.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Botón de inicio de sesión
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : ElevatedButton(
                  onPressed: signIn, // Sigue funcionando al presionar el botón
                  child: const Text(
                    'Iniciar Sesión',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(55),
                    shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12), ),
                    backgroundColor: Colors.teal, foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 30),

                // Enlace a registro
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text( "¿No tienes cuenta? ", style: TextStyle(color: Colors.grey[700]), ),
                    GestureDetector(
                      onTap: widget.onTap,
                      child: const Text( "Regístrate ahora", style: TextStyle( color: Colors.teal, fontWeight: FontWeight.bold, ), ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}