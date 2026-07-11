import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduce errores de Supabase Auth a mensajes en español amigables.
///
/// Los errores de Supabase vienen en inglés (ej. "over_email_send_rate_limit")
/// y esta función los convierte a mensajes claros para el usuario final.
String translateAuthError(Object error) {
  if (error is AuthApiException) {
    final code = error.code;
    final message = error.message;

    // Rate limit de email (registro, recuperación, magic link)
    if (code == 'over_email_send_rate_limit') {
      // El mensaje dice algo como "For security purposes, you can only
      // request this after 54 seconds." Extraemos los segundos.
      final seconds = _extractSeconds(message);
      if (seconds != null) {
        return 'Por seguridad, debes esperar $seconds segundos antes de '
            'solicitar otro correo.';
      }
      return 'Por seguridad, debes esperar antes de solicitar otro correo. '
          'Intenta de nuevo en un minuto.';
    }

    // Credenciales inválidas
    if (code == 'invalid_credentials' ||
        message.contains('Invalid login credentials')) {
      return 'Email o contraseña incorrectos. Verifica tus datos e intenta de nuevo.';
    }

    // Email ya registrado
    if (message.contains('already registered') ||
        message.contains('already exists') ||
        message.contains('User already')) {
      return 'Ya existe una cuenta con este email. Si olvidaste tu contraseña, '
          'puedes recuperarla.';
    }

    // Email no confirmado
    if (message.contains('Email not confirmed') ||
        message.contains('email not confirmed')) {
      return 'Debes confirmar tu email antes de iniciar sesión. '
          'Revisa tu bandeja de entrada (y spam).';
    }

    // Contraseña muy débil
    if (message.contains('password') &&
        (message.contains('weak') || message.contains('strong'))) {
      return 'La contraseña es muy débil. Usa al menos 8 caracteres con '
          'mayúsculas, minúsculas y números.';
    }

    // Límite de intentos de login
    if (code == 'over_request_rate_limit' ||
        message.contains('rate limit') ||
        message.contains('too many requests')) {
      return 'Demasiados intentos. Espera un momento y vuelve a intentarlo.';
    }

    // Error de red / conexión
    if (message.contains('network') ||
        message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('host')) {
      return 'Error de conexión. Revisa tu internet y vuelve a intentarlo.';
    }

    // Si no es un código conocido, devolvemos el mensaje original
    // pero al menos sabemos que es un AuthApiException
    return message;
  }

  // Para cualquier otro tipo de error, devolvemos el mensaje original
  final str = error.toString();

  // Traducciones adicionales por coincidencia de texto
  if (str.contains('over_email_send_rate_limit')) {
    final seconds = _extractSeconds(str);
    if (seconds != null) {
      return 'Por seguridad, debes esperar $seconds segundos antes de '
          'solicitar otro correo.';
    }
    return 'Por seguridad, debes esperar antes de solicitar otro correo.';
  }

  return str;
}

/// Extrae el número de segundos de un mensaje como
/// "...after 54 seconds."
RegExp _secondsRe = RegExp(r'after\s+(\d+)\s+seconds?', caseSensitive: false);

int? _extractSeconds(String message) {
  final match = _secondsRe.firstMatch(message);
  if (match != null && match.groupCount >= 1) {
    return int.tryParse(match.group(1)!);
  }
  return null;
}
