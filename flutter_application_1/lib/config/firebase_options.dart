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

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static FirebaseOptions get web {
    return _validatedWeb;
  }

  static const FirebaseOptions _validatedWeb = FirebaseOptions(
    apiKey: 'AIzaSyDt_mnuBryHcssBjRSdnPlh9VIC58LKL9Q',
    appId: '1:28032445048:web:025624ffdb03cfd54b1b8d',
    messagingSenderId: '28032445048',
    projectId: 'studyspace-kiet',
    authDomain: 'studyspace-kiet.firebaseapp.com',
    storageBucket: 'studyspace-kiet.appspot.com',
  );

  static void validate() {
    if (kIsWeb) {
      if (_validatedWeb.apiKey.isEmpty ||
          _validatedWeb.appId.isEmpty ||
          _validatedWeb.messagingSenderId.isEmpty ||
          _validatedWeb.projectId.isEmpty) {
        throw ArgumentError(
          'Missing Firebase Web keys. Ensure --dart-define options are set.',
        );
      }
    }
  }
}
