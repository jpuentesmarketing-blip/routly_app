import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SmsService {
  static final _supabase = Supabase.instance.client;

  /// Método para enviar un SMS llamando a la Edge Function de Supabase
  static Future<void> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'send-sms',
        body: {
          'to': phoneNumber,
          'message': message,
        },
      );

      debugPrint('✅ SMS enviado con éxito: ${response.data}');
    } on FunctionException catch (e) {
      debugPrint('❌ Error de la Edge Function (${e.status}): ${e.details}');
    } catch (e) {
      debugPrint('⚠️ Excepción inesperada al enviar SMS: $e');
    }
  }
}