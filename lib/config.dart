import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  Config._();

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  
  static bool get isConfigured {
    return supabaseUrl.isNotEmpty && 
           supabaseAnonKey.isNotEmpty && 
           !supabaseUrl.contains('your-project-ref') && 
           supabaseAnonKey != 'your-anon-key';
  }
}
