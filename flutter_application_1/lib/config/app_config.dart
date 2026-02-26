// StudySpace Flutter App - Environment Configuration
// Keep this file secure and do not commit to version control

class AppConfig {
  // Supabase Configuration
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://iayuwsvguwfqjgjsvjiy.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlheXV3c3ZndXdmcWpnanN2aml5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYwNTE5MTEsImV4cCI6MjA4MTYyNzkxMX0.EQhiq-yv9QLBNL_kmT5P59AZPykQkEZwbNbilxquYOA',
  );

  // Cloudinary Configuration
  static const String cloudinaryCloudName = 'dvttcyf7u';
  static const String cloudinaryUploadPreset = 'studyspace_uploads';

  // Backend API
  static const String apiUrl = 'http://13.48.57.16';

  // reCAPTCHA (v3 site key from Studyspace/.env)
  static const String recaptchaSiteKey =
      '6Ld7RUAsAAAAAKlJBKqsXHXnmP6PXRYvYhYjhsJF';

  // App Info
  static const String appName = 'MyStudySpace';
  static const String appVersion = '1.0.0';
  static const String webDomain = 'mystudyspace.me';

  // Razorpay Live Key
  static const String razorpayKeyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: 'rzp_live_S9IWIDxf81JDDM',
  );
  // Support Email
  static const String supportEmail = 'support@mystudyspace.me';
  // Giphy API Key (Get from Giphy Developers Dashboard: developers.giphy.com)
  static const String giphyApiKey = String.fromEnvironment('GIPHY_API_KEY');

  /// remove.bg API key for sticker background removal.
  static const String removeBgApiKey = String.fromEnvironment('REMOVE_BG_API_KEY');

  static String get removeBgApiKeyOrThrow {
    if (removeBgApiKey.isEmpty) {
      throw Exception('REMOVE_BG_API_KEY is not set. It is required for background removal.');
    }
    return removeBgApiKey;
  }

  // Google Sign-In Server Client ID (Web Client ID)
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// Validates that critical environment variables are set.
  /// Call this at the start of the app (e.g. in main.dart).
  /// Returns a [ValidationResult] containing any errors or warnings.
  static ValidationResult validate() {
    final errors = <String>[];
    final warnings = <String>[];

    // Critical: Supabase
    if (supabaseUrl.isEmpty ||
        supabaseUrl == 'https://your-project.supabase.co') {
      errors.add('Supabase URL is not configured');
    }
    if (supabaseAnonKey.isEmpty || supabaseAnonKey == 'your-anon-key') {
      errors.add('Supabase Anon Key is not configured');
    }

    // Optional: GIPHY_API_KEY - GIF picker won't work without it
    if (giphyApiKey.isEmpty) {
      warnings.add('GIPHY_API_KEY not set - GIF features will be disabled');
    }

    if (removeBgApiKey.isEmpty) {
      warnings.add(
        'REMOVE_BG_API_KEY not set - sticker background removal disabled',
      );
    }

    // Optional: GOOGLE_SERVER_CLIENT_ID
    if (googleServerClientId.isEmpty) {
      warnings.add(
        'GOOGLE_SERVER_CLIENT_ID not set - Google Sign-In may not work',
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
