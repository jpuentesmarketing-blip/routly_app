import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../data/auth_repository.dart';
import '../../home/presentation/home_screen.dart';
import '../../../widgets/legal_footer.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  bool _isDriver = false;
  bool _obscurePassword = true;
  bool _dataPrivacyAccepted = false; // Variable obligatoria para la política de datos
  
  final _authRepository = AuthRepository();
  bool _isLoading = false;
  bool _isRegistering = false;

  Future<void> _handleAuth() async {
    setState(() => _isLoading = true);
    try {
      if (_isRegistering) {
        if (_fullNameController.text.trim().isEmpty ||
            _phoneController.text.trim().isEmpty ||
            _emailController.text.trim().isEmpty ||
            _passwordController.text.trim().isEmpty) {
          throw const AuthException('Por favor completa todos los campos.');
        }

        // Validación obligatoria de la política de tratamiento de datos (Ley 1581)
        if (!_dataPrivacyAccepted) {
          throw const AuthException('Debes aceptar la Política de Privacidad y el tratamiento de datos personales para registrarte.');
        }

        await _authRepository.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          fullName: _fullNameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          isDriver: _isDriver,
          dataPrivacyAccepted: _dataPrivacyAccepted,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Registro exitoso! Ya puedes iniciar sesión.'),
            backgroundColor: Colors.teal,
          ),
        );
        setState(() => _isRegistering = false);
      } else {
        await _authRepository.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Bienvenido a Routly!'),
            backgroundColor: Colors.teal,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error inesperado: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    final resetController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recuperar contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ingresa tu correo electrónico y te enviaremos las instrucciones.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: resetController,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final email = resetController.text.trim();
              if (email.isEmpty) return;
              final nav = Navigator.of(dialogContext);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await Supabase.instance.client.auth.resetPasswordForEmail(
                  email,
                  redirectTo: kIsWeb
                      ? 'http://localhost:3000/'
                      : 'io.supabase.routly://reset-password/',
                );
                nav.pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('¡Correo de recuperación enviado!'),
                    backgroundColor: Colors.teal,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.directions_car_rounded,
                size: 80,
                color: Colors.teal,
              ),
              const SizedBox(height: 16),
              const Text(
                'Routly',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              const Text(
                'Movilidad compartida para tu comunidad',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              if (_isRegistering) ...[
                TextField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                IntlPhoneField(
                  decoration: const InputDecoration(
                    labelText: 'Número de Teléfono',
                    border: OutlineInputBorder(),
                  ),
                  initialCountryCode: 'CO',
                  onChanged: (phone) {
                    _phoneController.text = phone.completeNumber;
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('¿Registrarse como Conductor?'),
                  subtitle: const Text('Podrás ofrecer viajes a tu comunidad'),
                  value: _isDriver,
                  activeThumbColor: Colors.teal,
                  onChanged: (bool value) {
                    setState(() => _isDriver = value);
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                  border: const OutlineInputBorder(),
                ),
                obscureText: _obscurePassword,
              ),
              const SizedBox(height: 8),
              
              // --- CHECKBOX DE POLÍTICA DE PRIVACIDAD Y DATOS (SÓLO EN REGISTRO) ---
              if (_isRegistering) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: CheckboxListTile(
                    value: _dataPrivacyAccepted,
                    activeColor: Colors.teal,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Acepto la Política de Privacidad y el tratamiento de datos personales según la ley (GENOLAB SAS).',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    onChanged: (bool? value) {
                      setState(() {
                        _dataPrivacyAccepted = value ?? false;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (!_isRegistering)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showForgotPasswordDialog,
                    child: const Text(
                      '¿Olvidaste tu contraseña?',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                ElevatedButton(
                  onPressed: _handleAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _isRegistering ? 'Completar Registro' : 'Iniciar Sesión',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    setState(() => _isRegistering = !_isRegistering);
                  },
                  child: Text(
                    _isRegistering
                        ? '¿Ya tienes cuenta? Inicia sesión aquí'
                        : '¿No tienes cuenta? Regístrate aquí',
                    style: const TextStyle(color: Colors.teal),
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              // --- FOOTER LEGAL DE GENOLAB SAS ---
              const LegalFooter(showSupport: true),
            ],
          ),
        ),
      ),
    );
  }
}