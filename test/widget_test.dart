import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powerguard_iot/config.dart';

void main() {
  test('Config.isConfigured is false without Supabase env values', () {
    dotenv.testLoad(fileInput: '');
    expect(Config.isConfigured, isFalse);
  });

  test('Config.isConfigured is true with valid Supabase env values', () {
    dotenv.testLoad(fileInput: '''
SUPABASE_URL=https://example.supabase.co
SUPABASE_ANON_KEY=some-anon-key
''');
    expect(Config.isConfigured, isTrue);
  });
}
