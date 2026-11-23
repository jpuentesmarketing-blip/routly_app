import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Registrar usuario pasando datos adicionales a la metadata, constancia de políticas y calificación inicial de 5.0
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required bool isDriver,
    required bool dataPrivacyAccepted,
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'phone_number': phoneNumber,
        'is_driver': isDriver,
        'data_privacy_accepted': dataPrivacyAccepted,
        'privacy_accepted_at': DateTime.now().toIso8601String(),
        'rating': 5.0,       // Calificación inicial por defecto
        'total_ratings': 0,  // Conteo inicial de calificaciones
      },
    );
  }

  // Iniciar sesión
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Enviar correo de recuperación de contraseña
  Future<void> resetPassword({required String email}) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  // Cerrar sesión
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // Obtener usuario actual
  User? get currentUser => _supabase.auth.currentUser;
}