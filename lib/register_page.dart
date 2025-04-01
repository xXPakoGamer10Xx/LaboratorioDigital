import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RegisterPage extends StatefulWidget {
  final VoidCallback? onTap; // Callback para ir a la página de login

  const RegisterPage({super.key, this.onTap});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  // --- NUEVO: Estados para visibilidad de contraseñas ---
  bool _isPasswordObscured = true;
  bool _isConfirmPasswordObscured = true;
  // --- FIN NUEVO ---

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Registra un nuevo usuario
  Future<void> signUp() async {
    // Añadir comprobación isLoading
    if (!mounted || _isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // Validaciones (sin cambios)
    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showErrorSnackBar('Por favor, completa todos los campos.');
      return;
    }
    // --- NUEVO: Validación de formato de email ---
    final emailRegExp = RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
    if (!emailRegExp.hasMatch(email)) {
      _showErrorSnackBar('Ingrese un correo electrónico válido.');
      return;
    }
    // --- FIN NUEVO ---
    if (password != confirmPassword) {
      _showErrorSnackBar('Las contraseñas no coinciden.');
      return;
    }
    if (password.length < 6) {
      _showErrorSnackBar('La contraseña debe tener al menos 6 caracteres.');
      return;
    }

    setState(() { _isLoading = true; });

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      print('Usuario registrado: ${FirebaseAuth.instance.currentUser?.email}');
      // AuthGate manejará la navegación
    } on FirebaseAuthException catch (e) {
      print('Error de Firebase Auth: ${e.code}');
      _showErrorSnackBar(_getAuthErrorMessage(e.code));
    } catch (e) {
      print('Error inesperado: $e');
      _showErrorSnackBar('Ocurrió un error inesperado.');
    } finally {
      if (mounted) { setState(() { _isLoading = false; }); }
    }
  }

  // Muestra un SnackBar con el mensaje de error
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Limpiar anteriores
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent, // Mejor color
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating, // Mejor estilo
      ),
    );
  }

  // Mapea códigos de error de Firebase
  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'weak-password':
        return 'La contraseña debe tener al menos 6 caracteres.';
      case 'email-already-in-use':
        return 'El correo electrónico ya está registrado.';
      case 'invalid-email':
        return 'El formato del correo electrónico no es válido.';
      case 'operation-not-allowed':
        return 'El registro por correo/contraseña no está habilitado.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde.';
      default:
        return 'Error al registrarse ($code)';
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
                const Icon( Icons.person_add_alt_1_rounded, size: 80, color: Colors.black, ),
                const SizedBox(height: 30),
                const Text( 'Crea tu Cuenta', style: TextStyle( fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black, ), ),
                const SizedBox(height: 10),
                Text( '¡Completa los datos para empezar!', style: TextStyle(fontSize: 16, color: Colors.grey[700]), ),
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
                  // --- NUEVO: Input Action ---
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(), // Mover foco
                  // --- FIN NUEVO ---
                ),
                const SizedBox(height: 15),

                // Campo de contraseña
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    hintText: 'Mínimo 6 caracteres',
                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.black),
                    border: OutlineInputBorder( borderRadius: BorderRadius.circular(12), ),
                    filled: true, fillColor: Colors.grey[100],
                    labelStyle: TextStyle(color: Colors.grey[700]), hintStyle: TextStyle(color: Colors.grey[500]),
                    // --- NUEVO: Icono ojo 1 ---
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordObscured ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey[600],
                      ),
                      onPressed: () {
                        setState(() { _isPasswordObscured = !_isPasswordObscured; });
                      },
                    ),
                    // --- FIN NUEVO ---
                  ),
                  obscureText: _isPasswordObscured, // Usar estado
                  style: const TextStyle(color: Colors.black),
                  // --- NUEVO: Input Action ---
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(), // Mover foco
                  // --- FIN NUEVO ---
                ),
                const SizedBox(height: 15),

                // Campo de confirmación de contraseña
                TextField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirmar Contraseña',
                    hintText: 'Repite tu contraseña',
                    prefixIcon: const Icon(Icons.lock_reset_outlined, color: Colors.black),
                    border: OutlineInputBorder( borderRadius: BorderRadius.circular(12), ),
                    filled: true, fillColor: Colors.grey[100],
                    labelStyle: TextStyle(color: Colors.grey[700]), hintStyle: TextStyle(color: Colors.grey[500]),
                    // --- NUEVO: Icono ojo 2 ---
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isConfirmPasswordObscured ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey[600],
                      ),
                      onPressed: () {
                        setState(() { _isConfirmPasswordObscured = !_isConfirmPasswordObscured; });
                      },
                    ),
                    // --- FIN NUEVO ---
                  ),
                  obscureText: _isConfirmPasswordObscured, // Usar estado
                  style: const TextStyle(color: Colors.black),
                  // --- NUEVO: Input Action y Submit ---
                  textInputAction: TextInputAction.done, // Acción final
                  onSubmitted: (_) { // Enviar al presionar "listo/ir"
                    if (!_isLoading) {
                      signUp(); // Llama a la función de registro
                    }
                  },
                  // --- FIN NUEVO ---
                ),
                const SizedBox(height: 25),

                // Botón de registro o indicador de carga
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : ElevatedButton(
                  onPressed: signUp, // Sigue funcionando con el botón
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(55),
                    shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12), ),
                    backgroundColor: Colors.teal, foregroundColor: Colors.white,
                  ),
                  child: const Text( 'Registrarse', style: TextStyle(fontSize: 16), ),
                ),
                const SizedBox(height: 30),

                // Enlace a login
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text( "¿Ya tienes cuenta? ", style: TextStyle(color: Colors.grey[700]), ),
                    GestureDetector(
                      onTap: widget.onTap,
                      child: const Text( "Inicia sesión ahora", style: TextStyle( color: Colors.teal, fontWeight: FontWeight.bold, ), ),
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