// StudySpace Flutter App - Environment Configuration
// Keep this file secure and do not commit to version control

class AppConfig {
  // Supabase Configuration
  static const String supabaseUrl = 'https://iayuwsvguwfqjgjsvjiy.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlheXV3c3ZndXdmcWpnanN2aml5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYwNTE5MTEsImV4cCI6MjA4MTYyNzkxMX0.EQhiq-yv9QLBNL_kmT5P59AZPykQkEZwbNbilxquYOA';
  
  // Cloudinary Configuration
  static const String cloudinaryCloudName = 'dvttcyf7u';
  static const String cloudinaryUploadPreset = 'studyspace_uploads';
  
  // Backend API
  static const String apiUrl = 'https://studyspace-backend.onrender.com';

  // reCAPTCHA (v3 site key from Studyspace/.env)
  static const String recaptchaSiteKey = '6Ld7RUAsAAAAAKlJBKqsXHXnmP6PXRYvYhYjhsJF';
  
  // App Info
  static const String appName = 'MyStudySpace';
  static const String appVersion = '1.0.0';
  static const String webDomain = 'mystudyspace.me';
  
  // Razorpay Live Key
  static const String razorpayKeyId = 'rzp_live_S9IWIDxf81JDDM';
}
