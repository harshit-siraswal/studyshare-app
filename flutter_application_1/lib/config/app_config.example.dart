// StudyShare Flutter App - Environment Configuration (EXAMPLE).
// Copy this file to app_config.dart and fill in real values.

class AppConfig {
  static const String _defaultApiUrl = 'https://api.studyshare.in';
  static const String _defaultSupabaseUrl =
      'https://iayuwsvguwfqjgjsvjiy.supabase.co';
  static const String _defaultSupabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
  static const String _defaultGiphyApiKey = '';
  static const String _defaultRemoveBgApiKey = '';
  static const String _defaultRecaptchaSiteKey = '';
  static const String _defaultTenorApiKey = '';
  static const String _defaultGoogleServerClientId = '';

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
    final effectiveValue = (trimmed.isEmpty || trimmed == 'your-anon-key')
        ? _defaultSupabaseAnonKey.trim()
        : trimmed;
    if (effectiveValue.isEmpty || effectiveValue == 'YOUR_SUPABASE_ANON_KEY') {
      throw StateError(
        'AppConfig.supabaseAnonKey is not configured. Set SUPABASE_ANON_KEY '
        'or update _defaultSupabaseAnonKey in app_config.dart.',
      );
    }
    return effectiveValue;
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

  static const String _tenorApiKeyFromEnv = String.fromEnvironment(
    'TENOR_API_KEY',
    defaultValue: _defaultTenorApiKey,
  );

  static const String _googleServerClientIdFromEnv = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: _defaultGoogleServerClientId,
  );

  static String get tenorApiKey {
    final trimmed = _tenorApiKeyFromEnv.trim();
    final effectiveValue = trimmed.isEmpty
        ? _defaultTenorApiKey.trim()
        : trimmed;
    if (effectiveValue.isEmpty) {
      throw StateError(
        'AppConfig.tenorApiKey is not configured. Set TENOR_API_KEY or '
        'update _defaultTenorApiKey in app_config.dart.',
      );
    }
    return effectiveValue;
  }

  static String get googleServerClientId {
    final trimmed = _googleServerClientIdFromEnv.trim();
    final effectiveValue = trimmed.isEmpty
        ? _defaultGoogleServerClientId.trim()
        : trimmed;
    if (effectiveValue.isEmpty) {
      throw StateError(
        'AppConfig.googleServerClientId is not configured. Set '
        'GOOGLE_SERVER_CLIENT_ID or update _defaultGoogleServerClientId '
        'in app_config.dart.',
      );
    }
    return effectiveValue;
  }

  static void validateRequiredConfig() {
    // Accessors enforce required runtime configuration.
    tenorApiKey;
    googleServerClientId;
  }

  static const int maxSessionAgeHours = int.fromEnvironment(
    'MAX_SESSION_AGE_HOURS',
    defaultValue: 168,
  );

  static const List<String> apiBaseUrls = [_defaultApiUrl];
}
