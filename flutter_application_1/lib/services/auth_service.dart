import 'dart:async';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'backend_api_service.dart';
import 'push_notification_service.dart';

class AuthService {
  firebase_auth.FirebaseAuth get _auth => firebase_auth.FirebaseAuth.instance;

  // Only create GoogleSignIn for mobile platforms
  GoogleSignIn? _googleSignIn;
  SupabaseClient get _supabase => Supabase.instance.client;
  final BackendApiService _backendApi;
  final PushNotificationService _pushService;

  AuthService({
    BackendApiService? backendApi,
    PushNotificationService? pushService,
  }) : _backendApi = backendApi ?? BackendApiService(),
       _pushService = pushService ?? PushNotificationService() {
    // Only initialize GoogleSignIn on mobile (not web)
    if (!kIsWeb) {
      _googleSignIn = GoogleSignIn(
        // CRITICAL: serverClientId is the Web Client ID from google-services.json
        // This is required for Android to work with Firebase Auth
        serverClientId: AppConfig.googleServerClientId,
      );
    }
  }

  // Current user stream
  Stream<firebase_auth.User?> get authStateChanges => _auth.authStateChanges();

  // Current user
  firebase_auth.User? get currentUser => _auth.currentUser;

  // Check if user is signed in
  bool get isSignedIn => currentUser != null;

  // Check if email is verified
  bool get isEmailVerified => currentUser?.emailVerified ?? false;

  // Get user email
  String? get userEmail => currentUser?.email;

  // Get display name
  String? get displayName => currentUser?.displayName;

  // Get photo URL
  String? get photoUrl => currentUser?.photoURL;
  int _banCheckFailureCount = 0;
  DateTime? _lastBanCheckFailureAt;
  DateTime? _lastBanCheckAlertAt;
  bool _banCheckAlertSent = false;
  static const Duration _banCheckRetryWindow = Duration(seconds: 30);
  static const Duration _banCheckAlertCooldown = Duration(minutes: 5);
  static const int _banCheckAlertThreshold = 3;

  String _maskEmail(String email) {
    final trimmed = email.trim().toLowerCase();
    final atIndex = trimmed.indexOf('@');
    if (atIndex <= 0 || atIndex >= trimmed.length - 1) {
      return '[redacted_email]';
    }
    final local = trimmed.substring(0, atIndex);
    final domain = trimmed.substring(atIndex + 1);
    final first = local[0];
    final maskedLocal = '$first***';
    return '$maskedLocal@$domain';
  }

  void incrementBanCheckFailure() {
    _banCheckFailureCount += 1;
    _lastBanCheckFailureAt = DateTime.now();
    developer.log(
      'metric=ban_check_failure count=$_banCheckFailureCount',
      name: 'auth.metrics',
      level: 900,
    );
    final now = DateTime.now();
    final canSendAlert =
        !_banCheckAlertSent ||
        _lastBanCheckAlertAt == null ||
        now.difference(_lastBanCheckAlertAt!) >= _banCheckAlertCooldown;
    if (_banCheckFailureCount >= _banCheckAlertThreshold && canSendAlert) {
      sendBanCheckFailureAlert();
      _banCheckAlertSent = true;
      _lastBanCheckAlertAt = now;
    }
  }

  bool shouldAllowBanCheckRetry() {
    final lastFailure = _lastBanCheckFailureAt;
    if (lastFailure == null) return true;
    return DateTime.now().difference(lastFailure) > _banCheckRetryWindow;
  }

  void sendBanCheckFailureAlert() {
    developer.log(
      'alert=ban_check_failures_exceeded threshold=$_banCheckAlertThreshold '
      'current=$_banCheckFailureCount',
      name: 'auth.alerts',
      level: 1000,
    );
  }

  void _resetBanCheckFailureState() {
    _banCheckFailureCount = 0;
    _lastBanCheckFailureAt = null;
    _lastBanCheckAlertAt = null;
    _banCheckAlertSent = false;
  }

  void _emitBanCheckSkippedEvent({
    required String reason,
    required String normalizedEmail,
    String? normalizedCollegeId,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final maskedEmail = _maskEmail(normalizedEmail);
    developer.log(
      'ban_check_skipped reason=$reason email=$maskedEmail '
      'collegeId=${normalizedCollegeId ?? 'global'}',
      name: 'auth.ban_check',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
    developer.log(
      'metric=ban_check_skipped reason=$reason',
      name: 'auth.metrics',
      level: 900,
    );
  }

  /// Sign in with Google
  Future<firebase_auth.UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = firebase_auth.GoogleAuthProvider();
        provider.addScope('email');
        provider.addScope('profile');

        final userCredential = await _auth.signInWithPopup(provider);

        if (userCredential.user != null) {
          _saveUserToDatabase(userCredential.user!).catchError((e) {
            debugPrint('Background save error: $e');
          });
        }

        return userCredential;
      }

      if (_googleSignIn == null) {
        debugPrint('GoogleSignIn not initialized (web platform?)');
        throw Exception('Google Sign-In is not available on this platform');
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn!.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        // Save to database without blocking navigation
        _saveUserToDatabase(userCredential.user!).catchError((e) {
          debugPrint('Background save error: $e');
        });
      }

      return userCredential;
    } catch (e) {
      debugPrint('Error signing in with Google: $e');
      rethrow;
    }
  }

  /// Sign in with email and password
  Future<firebase_auth.UserCredential> signInWithEmail(
    String email,
    String password,
  ) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save/update user in database (non-blocking)
      if (userCredential.user != null) {
        _saveUserToDatabase(userCredential.user!).catchError((e) {
          debugPrint('Background save error: $e');
        });
      }

      return userCredential;
    } catch (e) {
      debugPrint('Error signing in with email: $e');
      rethrow;
    }
  }

  /// Create account with email and password
  Future<firebase_auth.UserCredential> createAccountWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCredential.user?.updateDisplayName(displayName);
      await userCredential.user?.sendEmailVerification();
      await userCredential.user?.reload();

      if (userCredential.user != null) {
        // Save to database (non-blocking)
        _saveUserToDatabase(userCredential.user!).catchError((e) {
          debugPrint('Background save error: $e');
        });
      }
      return userCredential;
    } catch (e) {
      debugPrint('Error creating account: $e');
      rethrow;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint('Error sending password reset email: $e');
      rethrow;
    }
  }

  /// Resend verification email
  Future<void> resendVerificationEmail() async {
    try {
      await currentUser?.sendEmailVerification();
    } catch (e) {
      debugPrint('Error resending verification email: $e');
      rethrow;
    }
  }

  /// Reload user to check email verification status
  Future<void> reloadUser() async {
    await currentUser?.reload();
  }

  /// Sign out - FIXED: Skip GoogleSignIn on web
  Future<void> signOut() async {
    try {
      SharedPreferences? prefs;
      if (!kIsWeb) {
        final token =
            _pushService.fcmToken ?? await _pushService.getSavedToken();
        if (token != null && token.isNotEmpty) {
          try {
            await _backendApi.deleteFcmToken(token);
            debugPrint('FCM token unregistered before sign out.');
          } catch (e) {
            debugPrint('Failed to unregister FCM token before sign out: $e');
          }
        }
      }
      try {
        prefs ??= await SharedPreferences.getInstance();
        await prefs.remove('fcm_token_owner_email');
        await prefs.remove('premium_until');
        await prefs.remove('premium_tier');
        await prefs.remove('premium_email');
      } catch (e) {
        debugPrint('Failed to clear sign-out caches: $e');
      }

      // Only sign out of GoogleSignIn on mobile
      if (!kIsWeb && _googleSignIn != null) {
        try {
          await _googleSignIn!.signOut();
        } catch (e) {
          debugPrint('GoogleSignIn signOut error (ignored): $e');
        }
      }
      // Always sign out of Firebase
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error signing out: $e');
      rethrow;
    }
  }

  /// Check if user is banned
  Future<Map<String, dynamic>?> checkBanStatus(
    String email,
    String? collegeId,
  ) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedCollegeId = collegeId != null && collegeId.trim().isNotEmpty
        ? collegeId.trim()
        : null;

    if (!shouldAllowBanCheckRetry()) {
      _emitBanCheckSkippedEvent(
        reason: 'retry_throttled',
        normalizedEmail: normalizedEmail,
        normalizedCollegeId: normalizedCollegeId,
      );
      return {'isBanned': false, 'reason': null, 'banCheckSkipped': true};
    }

    try {
      bool schemaQueryable = false;

      Future<Map<String, dynamic>> findBan({
        required String column,
        required String normalizedEmail,
        String? scopedCollegeId,
      }) async {
        try {
          var query = _supabase
              .from('banned_users')
              .select()
              .eq(column, normalizedEmail);

          if (scopedCollegeId == null) {
            query = query.isFilter('college_id', null);
          } else {
            query = query.eq('college_id', scopedCollegeId);
          }

          final mappedRow = await query.maybeSingle();
          return {'row': mappedRow, 'schemaQueryable': true};
        } on PostgrestException catch (e) {
          final message = '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'
              .toLowerCase();
          final missingColumn =
              e.code == '42703' ||
              e.code == 'PGRST204' ||
              (message.contains('column') &&
                  message.contains(column.toLowerCase()) &&
                  message.contains('does not exist'));
          if (missingColumn) {
            return {'row': null, 'schemaQueryable': false};
          }
          rethrow;
        }
      }

      final banColumns = ['email', 'user_email'];

      for (final column in banColumns) {
        final globalResult = await findBan(
          column: column,
          normalizedEmail: normalizedEmail,
        );
        schemaQueryable =
            schemaQueryable || (globalResult['schemaQueryable'] == true);
        final globalBan = globalResult['row'] as Map<String, dynamic>?;
        if (globalBan != null) {
          _resetBanCheckFailureState();
          return {
            'isBanned': true,
            'reason': globalBan['reason'] ?? 'You have been banned.',
            'isGlobal': true,
          };
        }
      }

      if (normalizedCollegeId != null) {
        for (final column in banColumns) {
          final collegeResult = await findBan(
            column: column,
            normalizedEmail: normalizedEmail,
            scopedCollegeId: normalizedCollegeId,
          );
          schemaQueryable =
              schemaQueryable || (collegeResult['schemaQueryable'] == true);
          final collegeBan = collegeResult['row'] as Map<String, dynamic>?;
          if (collegeBan != null) {
            _resetBanCheckFailureState();
            return {
              'isBanned': true,
              'reason':
                  collegeBan['reason'] ??
                  'You have been banned from this college.',
              'isGlobal': false,
            };
          }
        }
      }

      if (!schemaQueryable) {
        developer.log(
          'banned_users schema not queryable for ban checks.',
          name: 'auth.ban_check',
          level: 1000,
        );
        incrementBanCheckFailure();
        _emitBanCheckSkippedEvent(
          reason: 'schema_not_queryable',
          normalizedEmail: normalizedEmail,
          normalizedCollegeId: normalizedCollegeId,
        );
        return {'isBanned': false, 'reason': null, 'banCheckSkipped': true};
      }

      _resetBanCheckFailureState();
      return {'isBanned': false, 'reason': null, 'banCheckSkipped': false};
    } catch (e, st) {
      developer.log(
        'ban status check failed',
        name: 'auth.ban_check',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      incrementBanCheckFailure();
      _emitBanCheckSkippedEvent(
        reason: 'exception',
        normalizedEmail: normalizedEmail,
        normalizedCollegeId: normalizedCollegeId,
        error: e,
        stackTrace: st,
      );
      return {'isBanned': false, 'reason': null, 'banCheckSkipped': true};
    }
  }

  /// Determine user role based on email domain
  String getUserRole(String email, String? collegeDomain) {
    if (collegeDomain == null) return 'READ_ONLY';

    final emailDomain = email.split('@').last.toLowerCase();
    if (emailDomain == collegeDomain.toLowerCase()) {
      return 'COLLEGE_USER';
    }
    return 'READ_ONLY';
  }

  /// Save user to Supabase database
  Future<void> _saveUserToDatabase(firebase_auth.User user) async {
    try {
      final email = user.email;
      if (email == null) {
        debugPrint('User email is null, skipping database save');
        return;
      }

      // Check if user already exists
      final existingUser = await _supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle()
          .timeout(const Duration(seconds: 5)); // Add timeout

      if (existingUser == null) {
        // Create new user record
        final now = DateTime.now().toIso8601String();
        await _supabase
            .from('users')
            .insert({
              'email': email,
              'display_name': user.displayName ?? email.split('@')[0],
              'profile_photo_url': user.photoURL,
              'created_at': now,
              'updated_at': now,
            })
            .timeout(const Duration(seconds: 5));
        debugPrint('User saved to database.');
      } else {
        // Update existing user
        await _supabase
            .from('users')
            .update({
              'display_name': user.displayName ?? email.split('@')[0],
              'profile_photo_url': user.photoURL,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('email', email)
            .timeout(const Duration(seconds: 5));
        debugPrint('User updated in database.');
      }
    } on TimeoutException {
      debugPrint('Database save timeout - user sign-in will proceed');
      // Don't throw - allow sign-in to proceed
    } on PostgrestException catch (e) {
      debugPrint('Supabase database error: ${e.message}');
      // Check if it's a constraint violation (user might already exist)
      if (e.code == '23505') {
        // Unique violation
        debugPrint('User already exists in database');
      } else {
        debugPrint('Database error code: ${e.code}');
      }
      // Don't throw - allow sign-in to proceed
    } catch (e) {
      debugPrint('Unexpected error saving user to database: $e');
      // Don't throw - allow sign-in to proceed even if DB save fails
    }
  }

  /// Get Firebase error message
  String getErrorMessage(dynamic error) {
    if (error is firebase_auth.FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No account found with this email';
        case 'wrong-password':
          return 'Invalid password';
        case 'email-already-in-use':
          return 'Email is already registered';
        case 'weak-password':
          return 'Password should be at least 6 characters';
        case 'invalid-email':
          return 'Invalid email address';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'network-request-failed':
          return 'Network error. Please check your connection.';
        default:
          return error.message ?? 'Authentication failed';
      }
    }
    return error.toString();
  }
}
