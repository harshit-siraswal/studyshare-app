// StudyShare Flutter App - Environment Configuration (EXAMPLE).
// Copy this file to app_config.dart and fill in real values.

class AppConfig {
  static const String _defaultApiUrl = 'https://api.studyshare.in';
  static const String _defaultSupabaseUrl =
      'https://iayuwsvguwfqjgjsvjiy.supabase.co';
  static const String _defaultSupabaseAnonKey = '';
  static const String _defaultGiphyApiKey = '';
  static const String _defaultRemoveBgApiKey = '';
  static const String _defaultRecaptchaSiteKey = '';

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

  static const String recaptchaSiteKey = String.fromEnvironment(
    'RECAPTCHA_SITE_KEY',
    defaultValue: _defaultRecaptchaSiteKey,
  );

  static const String tenorApiKey = String.fromEnvironment(
    'TENOR_API_KEY',
    defaultValue: '',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static const int maxSessionAgeHours = int.fromEnvironment(
    'MAX_SESSION_AGE_HOURS',
    defaultValue: 168,
  );

  static const List<String> apiBaseUrls = [_defaultApiUrl];
}
