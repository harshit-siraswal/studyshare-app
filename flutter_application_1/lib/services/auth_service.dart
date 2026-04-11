import 'dart:async';
import 'dart:developer' as developer;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/user_identity.dart' as app_identity;
import 'analytics_service.dart';
import 'backend_api_service.dart';
import 'push_notification_service.dart';
import 'supabase_service.dart';

class LocalRateLimitException implements Exception {
  const LocalRateLimitException({
    required this.message,
    required this.retryAfter,
  });

  final String message;
  final Duration retryAfter;

  @override
  String toString() => message;
}

class AuthService {
  static final ValueNotifier<app_identity.UserIdentity?> identityNotifier =
      ValueNotifier<app_identity.UserIdentity?>(null);

  int _banCheckFailureCount = 0;
  DateTime? _lastBanCheckFailureAt;
  DateTime? _lastBanCheckAlertAt;
  bool _banCheckAlertSent = false;
  static const Duration _banCheckRetryWindow = Duration(seconds: 30);
  static const Duration _banCheckAlertCooldown = Duration(minutes: 5);
  static const int _banCheckAlertThreshold = 3;
  static const Duration _emailLoginRateLimitWindow = Duration(minutes: 15);
  static const Duration _googleLoginRateLimitWindow = Duration(minutes: 15);
  static const Duration _signupRateLimitWindow = Duration(hours: 1);
  static const Duration _passwordResetRateLimitWindow = Duration(hours: 1);
  static const Duration _verificationEmailRateLimitWindow = Duration(hours: 1);
  static const int _emailLoginRateLimitMaxAttempts = 5;
  static const int _googleLoginRateLimitMaxAttempts = 8;
  static const int _signupRateLimitMaxAttempts = 3;
  static const int _passwordResetRateLimitMaxAttempts = 3;
  static const int _verificationEmailRateLimitMaxAttempts = 5;

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
      _googleSignIn = _buildGoogleSignIn();
    }
  }

  GoogleSignIn _buildGoogleSignIn({bool preferPlatformConfig = false}) {
    final serverClientId = AppConfig.googleServerClientId.trim();
    final usePlatformConfig = preferPlatformConfig || serverClientId.isEmpty;
    if (usePlatformConfig) {
      return GoogleSignIn(scopes: const ['email', 'profile']);
    }
    return GoogleSignIn(
      serverClientId: serverClientId,
      scopes: const ['email', 'profile'],
    );
  }

  Future<bool> _hasMobileNetworkConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult.any((item) => item != ConnectivityResult.none);
  }

  Future<void> _resetGoogleSignInClient({
    bool preferPlatformConfig = false,
  }) async {
    final client = _googleSignIn;
    if (client != null) {
      try {
        await client.disconnect();
      } catch (e) {
        debugPrint('GoogleSignIn disconnect error (ignored): $e');
      }
      try {
        await client.signOut();
      } catch (e) {
        debugPrint('GoogleSignIn signOut error (ignored): $e');
      }
    }
    _googleSignIn = _buildGoogleSignIn(
      preferPlatformConfig: preferPlatformConfig,
    );
  }

  Future<firebase_auth.UserCredential?> _performMobileGoogleSignIn() async {
    final googleUser = await _googleSignIn!.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final accessToken = googleAuth.accessToken;
    final idToken = googleAuth.idToken;
    if ((accessToken == null || accessToken.isEmpty) &&
        (idToken == null || idToken.isEmpty)) {
      throw Exception(
        'Google Sign-In did not return a valid authentication token. Please try again.',
      );
    }

    final credential = firebase_auth.GoogleAuthProvider.credential(
      accessToken: accessToken,
      idToken: idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);

    if (userCredential.user != null) {
      _backgroundSaveUser(userCredential.user!);
    }

    return userCredential;
  }

  /// Fire-and-forget save of user data to the backend database.
  void _backgroundSaveUser(firebase_auth.User user) {
    unawaited(
      _saveUserToDatabase(user).catchError((e) {
        debugPrint('Background save error: $e');
      }),
    );
  }

  /// Logs Google config details and throws a user-facing config error.
  Never _throwGoogleConfigError() {
    debugPrint(
      'Google Sign-In config error: '
      'Android=${AppConfig.androidBundleId}, iOS=${AppConfig.iosBundleId}. '
      'Ensure signing SHA fingerprint is registered in Firebase.',
    );
    throw Exception(
      'Google Sign-In configuration error. Please contact support.',
    );
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

  app_identity.UserIdentity? get currentIdentity => identityNotifier.value;

  void setIdentityFromMap(Map<String, dynamic>? rawIdentity) {
    if (rawIdentity == null || rawIdentity.isEmpty) {
      clearIdentity();
      return;
    }

    try {
      final parsed = app_identity.UserIdentity.fromJson(rawIdentity);
      final existing = identityNotifier.value;
      if (existing != null && existing.equivalentTo(parsed)) {
        return;
      }
      identityNotifier.value = parsed;
    } catch (e) {
      debugPrint('Failed to parse identity payload: $e');
      clearIdentity();
    }
  }

  void clearIdentity() {
    if (identityNotifier.value != null) {
      identityNotifier.value = null;
    }
  }

  bool get requiresEmailVerificationForCurrentUser {
    final user = currentUser;
    if (user == null) return false;
    return _requiresEmailVerification(user);
  }

  bool _requiresEmailVerification(firebase_auth.User user) {
    final hasPasswordProvider = user.providerData.any(
      (provider) => provider.providerId == 'password',
    );
    return hasPasswordProvider && !user.emailVerified;
  }

  DateTime? _coerceDateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  Future<DateTime?> _getAuthenticationTime(firebase_auth.User user) async {
    final fromMetadata = _coerceDateTime(user.metadata.lastSignInTime);
    if (fromMetadata != null) {
      return fromMetadata.toUtc();
    }

    try {
      final tokenResult = await user.getIdTokenResult(true);
      final fromToken = _coerceDateTime(tokenResult.authTime);
      if (fromToken != null) {
        return fromToken.toUtc();
      }
    } catch (error, stackTrace) {
      developer.log(
        'Unable to resolve auth_time for session validation.',
        name: 'auth.session',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  Future<String?> getCurrentSessionBlockingReason() async {
    final user = currentUser;
    if (user == null) {
      return 'Your session expired. Please sign in again.';
    }

    try {
      await user.reload();
    } catch (error, stackTrace) {
      developer.log(
        'Failed to refresh auth session state.',
        name: 'auth.session',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final refreshedUser = currentUser;
    if (refreshedUser == null) {
      return 'Your session expired. Please sign in again.';
    }

    if (_requiresEmailVerification(refreshedUser)) {
      return 'Verify your email before continuing.';
    }

    final authenticatedAt = await _getAuthenticationTime(refreshedUser);
    if (authenticatedAt == null) {
      return null;
    }

    final sessionAge = DateTime.now().toUtc().difference(authenticatedAt);
    if (sessionAge > AppConfig.maxSessionAge) {
      developer.log(
        'session_expired age_hours=${sessionAge.inHours}',
        name: 'auth.session',
        level: 1000,
      );
      return 'Your session expired. Please sign in again.';
    }

    return null;
  }

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

  String _classifyAuthError(Object error) {
    if (error is firebase_auth.FirebaseAuthException) {
      final code = error.code.trim().toLowerCase().replaceAll('-', '_');
      if (code.isNotEmpty) return code;
    }
    final lowered = error.toString().toLowerCase();
    if (lowered.contains('network')) return 'network';
    if (lowered.contains('timeout')) return 'timeout';
    if (lowered.contains('developer_error') ||
        lowered.contains('status code 10') ||
        lowered.contains('configuration')) {
      return 'config';
    }
    return 'unknown';
  }

  String _rateLimitKey({required String scope, required String subject}) {
    final normalizedSubject = subject.trim().toLowerCase();
    return 'security_rate_limit::$scope::${normalizedSubject.isEmpty ? 'device' : normalizedSubject}';
  }

  Future<void> _consumeRateLimit({
    required String scope,
    required String subject,
    required int maxAttempts,
    required Duration window,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final thresholdMs = nowMs - window.inMilliseconds;
    final key = _rateLimitKey(scope: scope, subject: subject);
    final timestamps =
        (prefs.getStringList(key) ?? const <String>[])
            .map(int.tryParse)
            .whereType<int>()
            .where((timestamp) => timestamp >= thresholdMs)
            .toList()
          ..sort();

    if (timestamps.length >= maxAttempts) {
      await prefs.setStringList(
        key,
        timestamps.map((timestamp) => timestamp.toString()).toList(),
      );
      final oldestAttempt = timestamps.first;
      final retryAfterMs =
          window.inMilliseconds -
          (nowMs - oldestAttempt).clamp(0, window.inMilliseconds);
      final retryAfter = Duration(milliseconds: retryAfterMs);
      developer.log(
        'rate_limit_blocked scope=$scope subject=${subject.trim().toLowerCase()}',
        name: 'auth.abuse',
        level: 1000,
      );
      throw LocalRateLimitException(
        message: 'Too many attempts. Please wait and try again.',
        retryAfter: retryAfter,
      );
    }

    timestamps.add(nowMs);
    await prefs.setStringList(
      key,
      timestamps.map((timestamp) => timestamp.toString()).toList(),
    );
  }

  Future<void> _clearRateLimit({
    required String scope,
    required String subject,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rateLimitKey(scope: scope, subject: subject));
  }

  String _normalizeAndValidateEmail(String email) {
    final normalized = email.trim().toLowerCase();
    final emailPattern = RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    );
    if (normalized.isEmpty || !emailPattern.hasMatch(normalized)) {
      throw Exception('Please enter a valid email address.');
    }
    if (normalized.length > 254) {
      throw Exception('Email address is too long.');
    }
    return normalized;
  }

  void _validatePassword({required String password, required bool isSignup}) {
    final trimmed = password.trim();
    if (trimmed.isEmpty) {
      throw Exception('Password is required.');
    }
    if (password.length > 128) {
      throw Exception('Password is too long.');
    }
    if (isSignup) {
      final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
      final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
      final hasDigit = RegExp(r'\d').hasMatch(password);
      if (password.length < 12 || !hasUppercase || !hasLowercase || !hasDigit) {
        throw Exception(
          'Password must be at least 12 characters and include upper-case, lower-case, and a number.',
        );
      }
    }
  }

  String _normalizeDisplayName(String displayName) {
    final normalized = displayName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length < 2) {
      throw Exception('Display name must be at least 2 characters.');
    }
    if (normalized.length > 80) {
      throw Exception('Display name must be 80 characters or fewer.');
    }
    if (RegExp(r'[\u0000-\u001F\u007F]').hasMatch(normalized)) {
      throw Exception('Display name contains invalid characters.');
    }
    return normalized;
  }

  void _logAuthAudit({
    required String action,
    required String outcome,
    String? email,
    String? method,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      'action=$action outcome=$outcome method=${method ?? 'unknown'} '
      'email=${email == null || email.trim().isEmpty ? '[unknown]' : _maskEmail(email)}',
      name: 'auth.audit',
      level: outcome == 'success' ? 800 : 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void incrementBanCheckFailure() {
    final now = DateTime.now();
    _banCheckFailureCount += 1;
    _lastBanCheckFailureAt = now;
    developer.log(
      'metric=ban_check_failure count=$_banCheckFailureCount',
      name: 'auth.metrics',
      level: 900,
    );
    final canSendAlert =
        !_banCheckAlertSent ||
        _lastBanCheckAlertAt == null ||
        now.difference(_lastBanCheckAlertAt!) >= _banCheckAlertCooldown;
    if (_banCheckFailureCount >= _banCheckAlertThreshold && canSendAlert) {
      _logBanCheckFailureAlert();
      _banCheckAlertSent = true;
      _lastBanCheckAlertAt = now;
    }
  }

  bool shouldAllowBanCheckRetry() {
    final lastFailure = _lastBanCheckFailureAt;
    if (lastFailure == null) return true;
    return DateTime.now().difference(lastFailure) > _banCheckRetryWindow;
  }

  void _logBanCheckFailureAlert() {
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
      await _consumeRateLimit(
        scope: 'google_login',
        subject: 'device',
        maxAttempts: _googleLoginRateLimitMaxAttempts,
        window: _googleLoginRateLimitWindow,
      );
      _logAuthAudit(action: 'login', outcome: 'attempt', method: 'google');

      if (kIsWeb) {
        final provider = firebase_auth.GoogleAuthProvider();
        provider.addScope('email');
        provider.addScope('profile');

        final userCredential = await _auth.signInWithPopup(provider);

        if (userCredential.user != null) {
          _backgroundSaveUser(userCredential.user!);
        }

        await AnalyticsService.instance.logEvent(
          'auth_login',
          parameters: const <String, Object?>{'method': 'google'},
        );
        _logAuthAudit(action: 'login', outcome: 'success', method: 'google');

        return userCredential;
      }

      if (_googleSignIn == null) {
        debugPrint('GoogleSignIn not initialized (web platform?)');
        throw Exception('Google Sign-In is not available on this platform');
      }

      final hasNetwork = await _hasMobileNetworkConnection();
      if (!hasNetwork) {
        throw Exception(
          'No internet connection. Google Sign-In requires Wi-Fi or mobile data.',
        );
      }

      PlatformException? lastPlatformError;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          if (attempt > 0) {
            await _resetGoogleSignInClient(preferPlatformConfig: true);
            await Future<void>.delayed(const Duration(milliseconds: 350));
          }
          final userCredential = await _performMobileGoogleSignIn();
          if (userCredential?.user != null) {
            await AnalyticsService.instance.logEvent(
              'auth_login',
              parameters: const <String, Object?>{'method': 'google'},
            );
            _logAuthAudit(
              action: 'login',
              outcome: 'success',
              method: 'google',
              email: userCredential?.user?.email,
            );
          }
          return userCredential;
        } on PlatformException catch (e) {
          final errorMessage = '${e.code} ${e.message ?? ''}'.toLowerCase();
          debugPrint(
            'Google Sign-In platform error (attempt ${attempt + 1}): $e',
          );
          if (_looksLikeGoogleConfigIssue(errorMessage)) {
            _throwGoogleConfigError();
          }
          lastPlatformError = e;
          if (!_looksLikeGoogleNetworkIssue(errorMessage) || attempt > 0) {
            break;
          }
        }
      }

      if (lastPlatformError != null) {
        final errorMessage =
            '${lastPlatformError.code} ${lastPlatformError.message ?? ''}'
                .toLowerCase();
        if (_looksLikeGoogleNetworkIssue(errorMessage)) {
          final stillOnline = await _hasMobileNetworkConnection();
          if (!stillOnline) {
            throw Exception(
              'No internet connection. Check Wi-Fi or mobile data and try again.',
            );
          }
          throw Exception(
            'Google Sign-In temporarily could not reach Google services. '
            'Try again in a few seconds or switch network once.',
          );
        }
        throw lastPlatformError;
      }

      return null;
    } on PlatformException catch (e) {
      final errorMessage = '${e.code} ${e.message ?? ''}'.toLowerCase();
      debugPrint('Google Sign-In platform error: $e');
      await AnalyticsService.instance.logEvent(
        'auth_login_error',
        parameters: <String, Object?>{
          'method': 'google',
          'reason': _classifyAuthError(e),
        },
      );
      if (_looksLikeGoogleConfigIssue(errorMessage)) {
        _throwGoogleConfigError();
      }
      _logAuthAudit(
        action: 'login',
        outcome: 'failure',
        method: 'google',
        error: e,
      );
      rethrow;
    } catch (e) {
      debugPrint('Error signing in with Google: $e');
      await AnalyticsService.instance.logEvent(
        'auth_login_error',
        parameters: <String, Object?>{
          'method': 'google',
          'reason': _classifyAuthError(e),
        },
      );
      _logAuthAudit(
        action: 'login',
        outcome: 'failure',
        method: 'google',
        error: e,
      );
      rethrow;
    }
  }

  bool _looksLikeGoogleConfigIssue(String message) {
    return message.contains('developer_error') ||
        message.contains('apiexception: 10') ||
        message.contains('status code 10') ||
        message.contains('12500');
  }

  bool _looksLikeGoogleNetworkIssue(String message) {
    return message.contains('network_error') ||
        message.contains('apiexception: 7') ||
        message.contains('status code 7');
  }

  /// Sign in with email and password
  Future<firebase_auth.UserCredential> signInWithEmail(
    String email,
    String password,
  ) async {
    final normalizedEmail = _normalizeAndValidateEmail(email);
    _validatePassword(password: password, isSignup: false);
    try {
      await _consumeRateLimit(
        scope: 'email_login',
        subject: normalizedEmail,
        maxAttempts: _emailLoginRateLimitMaxAttempts,
        window: _emailLoginRateLimitWindow,
      );
      _logAuthAudit(
        action: 'login',
        outcome: 'attempt',
        method: 'email',
        email: normalizedEmail,
      );
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      if (userCredential.user != null &&
          _requiresEmailVerification(userCredential.user!)) {
        var verificationEmailSent = false;
        String? verificationErrorMessage;
        try {
          await userCredential.user!.sendEmailVerification();
          verificationEmailSent = true;
        } catch (error, stackTrace) {
          verificationErrorMessage = error is firebase_auth.FirebaseAuthException
              ? error.message?.trim()
              : error.toString().trim();
          debugPrint(
            'AuthService.signInWithEmail sendEmailVerification failed: $error\n$stackTrace',
          );
        }
        await _auth.signOut();
        final contextualMessage = verificationErrorMessage == null ||
                verificationErrorMessage.isEmpty
            ? ''
            : ' $verificationErrorMessage';
        throw firebase_auth.FirebaseAuthException(
          code: 'email-not-verified',
          message: verificationEmailSent
              ? 'Please verify your email before signing in. A new verification email has been sent.$contextualMessage'
              : verificationErrorMessage == null || verificationErrorMessage.isEmpty
              ? 'Please verify your email before signing in. We could not send a new verification email right now.'
              : 'Please verify your email before signing in.$contextualMessage',
        );
      }

      // Save/update user in database (non-blocking)
      if (userCredential.user != null) {
        _backgroundSaveUser(userCredential.user!);
      }
      await _clearRateLimit(scope: 'email_login', subject: normalizedEmail);

      await AnalyticsService.instance.logEvent(
        'auth_login',
        parameters: const <String, Object?>{'method': 'email'},
      );
      _logAuthAudit(
        action: 'login',
        outcome: 'success',
        method: 'email',
        email: normalizedEmail,
      );

      return userCredential;
    } catch (e) {
      debugPrint('Error signing in with email: $e');
      await AnalyticsService.instance.logEvent(
        'auth_login_error',
        parameters: <String, Object?>{
          'method': 'email',
          'reason': _classifyAuthError(e),
        },
      );
      _logAuthAudit(
        action: 'login',
        outcome: 'failure',
        method: 'email',
        email: normalizedEmail,
        error: e,
      );
      rethrow;
    }
  }

  /// Create account with email and password
  Future<firebase_auth.UserCredential> createAccountWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final normalizedEmail = _normalizeAndValidateEmail(email);
    final normalizedDisplayName = _normalizeDisplayName(displayName);
    _validatePassword(password: password, isSignup: true);
    try {
      await _consumeRateLimit(
        scope: 'email_signup',
        subject: normalizedEmail,
        maxAttempts: _signupRateLimitMaxAttempts,
        window: _signupRateLimitWindow,
      );
      _logAuthAudit(
        action: 'signup',
        outcome: 'attempt',
        method: 'email',
        email: normalizedEmail,
      );
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      await userCredential.user?.updateDisplayName(normalizedDisplayName);
      await userCredential.user?.sendEmailVerification();
      await userCredential.user?.reload();

      if (userCredential.user != null) {
        _backgroundSaveUser(userCredential.user!);
      }
      await _auth.signOut();
      await AnalyticsService.instance.logEvent(
        'auth_signup',
        parameters: const <String, Object?>{'method': 'email'},
      );
      _logAuthAudit(
        action: 'signup',
        outcome: 'success',
        method: 'email',
        email: normalizedEmail,
      );
      return userCredential;
    } catch (e) {
      debugPrint('Error creating account: $e');
      await AnalyticsService.instance.logEvent(
        'auth_signup_error',
        parameters: <String, Object?>{
          'method': 'email',
          'reason': _classifyAuthError(e),
        },
      );
      _logAuthAudit(
        action: 'signup',
        outcome: 'failure',
        method: 'email',
        email: normalizedEmail,
        error: e,
      );
      rethrow;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    final normalizedEmail = _normalizeAndValidateEmail(email);
    try {
      await _consumeRateLimit(
        scope: 'password_reset',
        subject: normalizedEmail,
        maxAttempts: _passwordResetRateLimitMaxAttempts,
        window: _passwordResetRateLimitWindow,
      );
      _logAuthAudit(
        action: 'password_reset',
        outcome: 'attempt',
        method: 'email',
        email: normalizedEmail,
      );
      await _auth.sendPasswordResetEmail(email: normalizedEmail);
      await AnalyticsService.instance.logEvent(
        'auth_password_reset',
        parameters: const <String, Object?>{'method': 'email'},
      );
      _logAuthAudit(
        action: 'password_reset',
        outcome: 'success',
        method: 'email',
        email: normalizedEmail,
      );
    } catch (e) {
      debugPrint('Error sending password reset email: $e');
      await AnalyticsService.instance.logEvent(
        'auth_password_reset_error',
        parameters: <String, Object?>{'reason': _classifyAuthError(e)},
      );
      _logAuthAudit(
        action: 'password_reset',
        outcome: 'failure',
        method: 'email',
        email: normalizedEmail,
        error: e,
      );
      rethrow;
    }
  }

  /// Resend verification email
  Future<void> resendVerificationEmail() async {
    try {
      final user = currentUser;
      final rawEmail = user?.email?.trim() ?? '';
      if (rawEmail.isEmpty) {
        throw firebase_auth.FirebaseAuthException(
          code: 'missing-email',
          message: 'Unable to resend verification: no email on account.',
        );
      }
      final email = _normalizeAndValidateEmail(rawEmail);
      await _consumeRateLimit(
        scope: 'verification_email',
        subject: email,
        maxAttempts: _verificationEmailRateLimitMaxAttempts,
        window: _verificationEmailRateLimitWindow,
      );
      await user?.sendEmailVerification();
      _logAuthAudit(
        action: 'verification_email',
        outcome: 'success',
        method: 'email',
        email: email,
      );
    } catch (e) {
      debugPrint('Error resending verification email: $e');
      _logAuthAudit(
        action: 'verification_email',
        outcome: 'failure',
        method: 'email',
        email: currentUser?.email,
        error: e,
      );
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
        prefs = await SharedPreferences.getInstance();
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
      await AnalyticsService.instance.logEvent('auth_logout');
      // Always sign out of Firebase
      await _auth.signOut();
      clearIdentity();
      SupabaseService().clearSessionCachesOnSignOut();
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
      final rpcResult = await _checkBanStatusViaRpc(
        normalizedCollegeId: normalizedCollegeId,
      );
      if (rpcResult != null) {
        _resetBanCheckFailureState();
        return rpcResult;
      }

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

  String _buildUsernameBase(String normalizedEmail) {
    final localPart = normalizedEmail.split('@').first.trim().toLowerCase();
    var normalized = localPart
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (normalized.isEmpty) {
      normalized = 'user';
    }

    if (normalized.length < 3) {
      normalized = '${normalized}user';
    }

    if (normalized.length > 24) {
      normalized = normalized.substring(0, 24).replaceAll(RegExp(r'_+$'), '');
    }

    if (normalized.isEmpty) {
      normalized = 'user';
    }

    return normalized;
  }

  String _buildUsernameFallback(String baseUsername, String userId) {
    final normalizedId = userId
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final suffix = normalizedId.isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString().substring(8)
        : normalizedId.substring(0, normalizedId.length < 6 ? normalizedId.length : 6);
    final maxBaseLength = (30 - suffix.length - 1).clamp(3, baseUsername.length);
    var safeBase = baseUsername;
    if (safeBase.length > maxBaseLength) {
      safeBase = safeBase
          .substring(0, maxBaseLength)
          .replaceAll(RegExp(r'_+$'), '');
    }
    if (safeBase.length < 3) {
      safeBase = 'user';
    }
    return '${safeBase}_$suffix';
  }

  bool _isUsernameColumnMissingError(PostgrestException error) {
    final details = '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
        .toLowerCase();
    return error.code == '42703' ||
        (details.contains('column') && details.contains('username'));
  }

  Future<String?> _resolveUsernameForUser({
    required String userId,
    required String normalizedEmail,
  }) async {
    final baseUsername = _buildUsernameBase(normalizedEmail);
    final fallbackUsername = _buildUsernameFallback(baseUsername, userId);

    try {
      final existingRow = await _supabase
          .from('users')
          .select('username')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));

      final existingUsername = existingRow == null
          ? ''
          : (existingRow['username']?.toString().trim() ?? '');
      if (existingUsername.isNotEmpty) {
        return existingUsername;
      }
    } on TimeoutException {
      return fallbackUsername;
    } on PostgrestException catch (e) {
      if (_isUsernameColumnMissingError(e)) {
        return null;
      }
      debugPrint('Unable to resolve existing username: ${e.message}');
    } catch (e) {
      debugPrint('Unable to resolve existing username: $e');
    }

    try {
      final collision = await _supabase
          .from('users_safe')
          .select('id')
          .eq('username', baseUsername)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 4));
      final collisionId = collision == null
          ? ''
          : (collision['id']?.toString().trim() ?? '');
      if (collisionId.isEmpty || collisionId == userId) {
        return baseUsername;
      }
    } on TimeoutException {
      return fallbackUsername;
    } catch (e) {
      debugPrint('Username availability check skipped: $e');
      return fallbackUsername;
    }

    return fallbackUsername;
  }

  /// Save user to Supabase database
  Future<void> _saveUserToDatabase(firebase_auth.User user) async {
    try {
      final email = user.email;
      if (email == null) {
        debugPrint('User email is null, skipping database save');
        return;
      }
      final normalizedEmail = email.trim().toLowerCase();
      final userId = user.uid.trim();
      if (userId.isEmpty) {
        debugPrint('User id is empty, skipping database save');
        return;
      }

      final resolvedUsername = await _resolveUsernameForUser(
        userId: userId,
        normalizedEmail: normalizedEmail,
      );

      final now = DateTime.now().toIso8601String();
      final payload = <String, dynamic>{
        'id': userId,
        'email': normalizedEmail,
        'display_name': user.displayName ?? normalizedEmail.split('@')[0],
        'profile_photo_url': user.photoURL,
        'updated_at': now,
        if (resolvedUsername != null && resolvedUsername.isNotEmpty)
          'username': resolvedUsername,
      };

      Future<void> runUpsert(Map<String, dynamic> data) {
        return _supabase
            .from('users')
            .upsert(data, onConflict: 'id')
            .timeout(const Duration(seconds: 5));
      }

      try {
        await runUpsert(payload);
      } on PostgrestException catch (e) {
        if (_isUsernameColumnMissingError(e) && payload.containsKey('username')) {
          payload.remove('username');
          await runUpsert(payload);
          debugPrint('User saved to database without username column.');
          return;
        }

        if (e.code == '23505' && payload.containsKey('username')) {
          final fallbackUsername = _buildUsernameFallback(
            _buildUsernameBase(normalizedEmail),
            userId,
          );
          final currentUsername = payload['username']?.toString().trim() ?? '';
          if (fallbackUsername != currentUsername) {
            final retryPayload = <String, dynamic>{
              ...payload,
              'username': fallbackUsername,
            };
            await runUpsert(retryPayload);
            debugPrint('User saved to database using fallback username.');
            return;
          }
        }

        rethrow;
      }

      debugPrint('User saved to database.');
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
    if (error is PlatformException) {
      final message = '${error.code} ${error.message ?? ''}'.toLowerCase();
      if (_looksLikeGoogleConfigIssue(message)) {
        return 'Google Sign-In configuration error. Please update the app or contact support.';
      }
      if (_looksLikeGoogleNetworkIssue(message)) {
        return 'Google Sign-In could not reach Google services. Check internet and try again.';
      }
      if (message.contains('sign_in_canceled') ||
          message.contains('canceled')) {
        return 'Google sign-in was cancelled';
      }
      return error.message ?? error.toString();
    }
    if (error is LocalRateLimitException) {
      final seconds = error.retryAfter.inSeconds.clamp(1, 3600);
      return 'Too many attempts. Try again in about $seconds second${seconds == 1 ? '' : 's'}.';
    }
    if (error is firebase_auth.FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No account found with this email';
        case 'wrong-password':
          return 'Invalid password';
        case 'email-already-in-use':
          return 'Email is already registered';
        case 'weak-password':
          return 'Password must be at least 12 characters and include upper-case, lower-case, and a number.';
        case 'invalid-email':
          return 'Invalid email address';
        case 'email-not-verified':
          return error.message?.trim().isNotEmpty == true
              ? error.message!.trim()
              : 'Please verify your email before signing in. A new verification email has been sent.';
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

  Future<Map<String, dynamic>?> _checkBanStatusViaRpc({
    required String? normalizedCollegeId,
  }) async {
    try {
      final payload = normalizedCollegeId == null
          ? await _supabase.rpc('get_my_ban_status')
          : await _supabase.rpc(
              'get_my_ban_status',
              params: {'target_college_id': normalizedCollegeId},
            );

      Map<String, dynamic>? row;
      if (payload is Map<String, dynamic>) {
        row = Map<String, dynamic>.from(payload);
      } else if (payload is Map) {
        row = Map<String, dynamic>.from(payload);
      } else if (payload is List && payload.isNotEmpty) {
        final first = payload.first;
        if (first is Map<String, dynamic>) {
          row = Map<String, dynamic>.from(first);
        } else if (first is Map) {
          row = Map<String, dynamic>.from(first);
        }
      }

      if (row == null) return null;
      return {
        'isBanned': row['is_banned'] == true,
        'reason': row['reason'],
        'isGlobal': row['is_global'] == true,
        'banCheckSkipped': false,
      };
    } catch (error) {
      final lowered = error.toString().toLowerCase();
      final missingFunction =
          lowered.contains('get_my_ban_status') &&
          (lowered.contains('does not exist') || lowered.contains('42883'));
      if (missingFunction) {
        return null;
      }
      developer.log(
        'Ban status RPC failed; falling back to direct query.',
        name: 'auth.ban_check',
        level: 900,
        error: error,
      );
      return null;
    }
  }
}
