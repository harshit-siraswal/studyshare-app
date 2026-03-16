// StudyShare Flutter App - Environment Configuration (EXAMPLE).
// Copy this file to app_config.dart and fill in real values.

class AppConfig {
  static const String _defaultApiUrl = 'https://api.studyshare.in';
  static const String _defaultSupabaseUrl =
      'https://iayuwsvguwfqjgjsvjiy.supabase.co';
  static const String _defaultSupabaseAnonKey =
      'YOUR_SUPABASE_ANON_KEY';
  static const String _defaultGiphyApiKey = '';
  static const String _defaultRemoveBgApiKey = '';

  static const String _supabaseUrlFromEnv = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultSupabaseUrl,
  );
  static const String _supabaseAnonKeyFromEnv = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _defaultSupabaseAnonKey,
  );

  static String get supabaseUrl {
    final trimmed = _supabaseUrlFromEnv.trim();
    if (trimmed.isEmpty || trimmed == 'https://your-project.supabase.co') {
      return _defaultSupabaseUrl;
    }
    return trimmed;
  }

  static String get supabaseAnonKey {
    final trimmed = _supabaseAnonKeyFromEnv.trim();
    if (trimmed.isEmpty || trimmed == 'your-anon-key') {
      return _defaultSupabaseAnonKey;
    }
    return trimmed;
  }

  static const String supportEmail = 'support@studyshare.me';

  static const String giphyApiKey = String.fromEnvironment(
    'GIPHY_API_KEY',
    defaultValue: _defaultGiphyApiKey,
  );

  static const String removeBgApiKey = String.fromEnvironment(
    'REMOVE_BG_API_KEY',
    defaultValue: _defaultRemoveBgApiKey,
  );

  static const String imgflipUsername = '';
  static const String imgflipPassword = '';
  static const String tenorApiKey = '';
  static const String telegramBotToken = '';

  static const List<String> apiBaseUrls = [_defaultApiUrl];
}
