// StudyShare Flutter App - Environment Configuration.
// This file may contain public client-side config (for example Supabase anon key
// and Firebase/web-visible IDs). Do NOT commit true secrets here; inject secrets
// like REMOVE_BG_API_KEY and payment private keys via secure --dart-define/CI.

class AppConfig {
  static const String _defaultApiUrl = 'https://api.studyshare.in';
  static const String _defaultSupabaseUrl =
      'https://iayuwsvguwfqjgjsvjiy.supabase.co';
  static const String _defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlheXV3c3ZndXdmcWpnanN2aml5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYwNTE5MTEsImV4cCI6MjA4MTYyNzkxMX0.EQhiq-yv9QLBNL_kmT5P59AZPykQkEZwbNbilxquYOA';
  // Secrets must be injected at build time via --dart-define.
  static const String _defaultGiphyApiKey = '';
  static const String _defaultRemoveBgApiKey = '';

  // Supabase Configuration
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

  // Cloudinary Configuration
  static const String cloudinaryCloudName = 'dvttcyf7u';
  static const String cloudinaryUploadPreset = 'studyspace_uploads';

  // Backend API
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: _defaultApiUrl,
  );
  static const String apiFallbackUrlsRaw = String.fromEnvironment(
    'API_FALLBACK_URLS',
    defaultValue: '',
  );

  /// Ordered backend base URLs (primary first), normalized without trailing slash.
  static List<String>? _cachedApiBaseUrls;
  static List<String> get apiBaseUrls {
    if (_cachedApiBaseUrls != null) return _cachedApiBaseUrls!;

    final urls = <String>[];
    final seen = <String>{};

    void addUrl(String value) {
      final normalized = _normalizeBaseUrl(value);
      if (normalized == null) return;
      if (seen.add(normalized)) {
        urls.add(normalized);
      }
    }

    addUrl(apiUrl);
    for (final value in apiFallbackUrlsRaw.split(',')) {
      addUrl(value);
    }

    if (urls.isEmpty) {
      urls.add(_defaultApiUrl);
    }

    _cachedApiBaseUrls = List.unmodifiable(urls);
    return _cachedApiBaseUrls!;
  }

  static String? _normalizeBaseUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  // reCAPTCHA (v3 site key from Studyspace/.env)
  static const String recaptchaSiteKey =
      '6Ld7RUAsAAAAAKlJBKqsXHXnmP6PXRYvYhYjhsJF';

  // App Info
  static const String appName = 'StudyShare';
  static const String appVersion = '1.0.1';
  static const String webDomain = 'studyshare.me';
  static const String androidBundleId = 'me.studyshare.android';
  static const String iosBundleId = 'me.studyshare.ios';

  // Razorpay Live Key
  static const String razorpayKeyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: '',
  );
  // Support Email
  static const String supportEmail = 'support@studyshare.me';
  // Giphy API Key (Get from Giphy Developers Dashboard: developers.giphy.com)
  static const String giphyApiKey = String.fromEnvironment(
    'GIPHY_API_KEY',
    defaultValue: _defaultGiphyApiKey,
  );

  /// remove.bg API key for sticker background removal.
  static const String removeBgApiKey = String.fromEnvironment(
    'REMOVE_BG_API_KEY',
    defaultValue: _defaultRemoveBgApiKey,
  );

  static const String imgflipUsername = 'HarshitPal';
  static const String imgflipPassword = 'Kumar@1234';
  static const String tenorApiKey = 'AIzaSyAyimkuYQYF_FXVALexPzpFtfOMYBHJzks';

  static String get removeBgApiKeyOrThrow {
    if (removeBgApiKey.isEmpty) {
      throw Exception(
        'REMOVE_BG_API_KEY is not set. It is required for background removal. Setup your keys via .env or --dart-define',
      );
    }
    return removeBgApiKey;
  }

  // Google Sign-In Server Client ID (Web Client ID)
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    // Default web client id from Firebase project (public identifier, not a secret).
    defaultValue:
        '28032445048-kg3k969ha8c9kc88hta90tddf5178n1o.apps.googleusercontent.com',
  );

  /// Validates that critical environment variables are set.
  /// Call this at the start of the app (e.g. in main.dart).
  /// Returns a [ValidationResult] containing any errors or warnings.
  static ValidationResult validate() {
    final errors = <String>[];
    final warnings = <String>[];

    // Critical: Supabase
    if (_supabaseUrlFromEnv.trim() == 'https://your-project.supabase.co') {
      warnings.add(
        'SUPABASE_URL contains placeholder value; using fallback configuration.',
      );
    }
    if (_supabaseAnonKeyFromEnv.trim() == 'your-anon-key') {
      warnings.add(
        'SUPABASE_ANON_KEY contains placeholder value; using fallback configuration.',
      );
    }
    if (supabaseUrl.isEmpty) {
      errors.add('Supabase URL is not configured');
    }
    if (supabaseAnonKey.isEmpty) {
      errors.add('Supabase Anon Key is not configured');
    }

    if (apiUrl.isEmpty) {
      errors.add('API_URL is not configured');
    } else if (!apiUrl.startsWith('https://')) {
      warnings.add(
        'API_URL is using HTTP. Prefer HTTPS to avoid cleartext transport risks.',
      );
    }

    // Optional: GIPHY_API_KEY (backend proxy can also provide this capability)
    if (giphyApiKey.isEmpty) {
      warnings.add(
        'GIPHY_API_KEY not set locally; GIF features depend on backend capability.',
      );
    }

    // Optional: GOOGLE_SERVER_CLIENT_ID
    if (googleServerClientId.isEmpty) {
      warnings.add(
        'GOOGLE_SERVER_CLIENT_ID not set - Google Sign-In may not work',
      );
    }

    // Razorpay Check
    if (razorpayKeyId.isEmpty) {
      warnings.add(
        'RAZORPAY_KEY_ID not set - Payment features will be disabled',
      );
    }

    return ValidationResult(errors, warnings);
  }
}

class ValidationResult {
  final List<String> errors;
  final List<String> warnings;

  ValidationResult(List<String> errors, List<String> warnings)
    : errors = List.unmodifiable(errors),
      warnings = List.unmodifiable(warnings);

  bool get isValid => errors.isEmpty;
}
