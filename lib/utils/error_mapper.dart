import 'package:supabase_flutter/supabase_flutter.dart';

class ErrorMapper {
  ErrorMapper._();

  static String map(dynamic error) {
    if (error is AuthException) {
      return error.message;
    }
    
    if (error is PostgrestException) {
      switch (error.code) {
        case 'PGRST303':
          return 'Authentication sync issue. Please ensure your phone time is set to "Automatic".';
        case 'PGRST205':
          return 'Database schema mismatch. Please run the setup script in Supabase.';
        case '42P01':
          return 'Required tables are missing. Did you run the SQL script?';
        default:
          return 'Database error (${error.code}): ${error.message}';
      }
    }

    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('socketexception') || errorStr.contains('failed host lookup')) {
      return 'No internet connection. Please check your network.';
    }

    if (errorStr.contains('timeout')) {
      return 'The request timed out. The server might be busy.';
    }

    return 'An unexpected error occurred. Please try again.';
  }
}
