import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static bool get hasRequiredWebOptions =>
      _webOptions.apiKey.isNotEmpty &&
      _webOptions.appId.isNotEmpty &&
      _webOptions.messagingSenderId.isNotEmpty &&
      _webOptions.projectId.isNotEmpty;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      validate();
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static FirebaseOptions get web {
    return _webOptions;
  }

  static const FirebaseOptions _webOptions = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: ''),
    appId: String.fromEnvironment('FIREBASE_APP_ID', defaultValue: ''),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '',
    ),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: ''),
    authDomain: String.fromEnvironment(
      'FIREBASE_AUTH_DOMAIN',
      defaultValue: '',
    ),
    storageBucket: String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
      defaultValue: '',
    ),
  );

  static void validate() {
    if (kIsWeb) {
      if (!hasRequiredWebOptions) {
        throw ArgumentError(
          'Missing Firebase Web keys. Ensure --dart-define options are set for:\n'
          'FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID, FIREBASE_PROJECT_ID',
        );
      }
    }
  }
}
