import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/app_config.dart';

/// Result of a successful Gmail OAuth authorization.
class GmailOAuthResult {
  const GmailOAuthResult({
    required this.emailAddress,
    required this.serverAuthCode,
  });

  /// The Gmail account the user authorized (may differ from StudyShare account).
  final String emailAddress;

  /// Server-side auth code — exchange this on the backend for a refresh token.
  /// It is a one-time-use value and should NOT be stored persistently on device.
  final String serverAuthCode;
}

/// Thin wrapper around [GoogleSignIn] scoped to [gmail.readonly] for the
/// attendance OTP email integration.
///
/// This is intentionally a **separate** [GoogleSignIn] instance from the one
/// used for StudyShare login in [AuthService]. The user may authorize a
/// completely different Gmail account here (e.g. their college email).
class GmailOAuthService {
  GmailOAuthService() {
    if (!kIsWeb) {
      _client = _buildClient();
    }
  }

  GoogleSignIn? _client;

  /// Gmail read-only scope — minimum permission needed to search inbox for OTPs.
  static const String _gmailReadonlyScope =
      'https://www.googleapis.com/auth/gmail.readonly';

  GoogleSignIn _buildClient() {
    final serverClientId = AppConfig.googleServerClientId.trim();
    if (serverClientId.isEmpty) {
      // Fall back to platform config if no server client ID configured.
      return GoogleSignIn(scopes: const [_gmailReadonlyScope]);
    }
    return GoogleSignIn(
      serverClientId: serverClientId,
      scopes: const [_gmailReadonlyScope],
    );
  }

  /// Opens the Google account picker and requests Gmail read-only consent.
  ///
  /// Returns a [GmailOAuthResult] on success, or `null` if the user cancelled.
  /// Throws on unexpected errors.
  ///
  /// The returned [GmailOAuthResult.serverAuthCode] must be sent to the backend
  /// immediately — it expires quickly and is single-use.
  Future<GmailOAuthResult?> signIn() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'GmailOAuthService: Gmail OAuth is only available on mobile.',
      );
    }

    final client = _client;
    if (client == null) {
      throw StateError('GmailOAuthService: client not initialized.');
    }

    // Sign out of any previous attendance Gmail session so the user always
    // sees the account picker (avoids silently reusing the StudyShare account).
    try {
      await client.signOut();
    } catch (_) {}

    GoogleSignInAccount? account;
    try {
      account = await client.signIn();
    } catch (e) {
      debugPrint('[GmailOAuthService] signIn error: $e');
      rethrow;
    }

    if (account == null) return null; // user cancelled

    final email = account.email.trim();
    if (email.isEmpty) {
      throw StateError('[GmailOAuthService] Sign-in succeeded but email is empty.');
    }

    final serverAuthCode = account.serverAuthCode;
    if (serverAuthCode == null || serverAuthCode.trim().isEmpty) {
      // serverAuthCode will be null when no serverClientId is configured.
      // In that mode, we still store the email locally (backend skips token exchange).
      debugPrint(
        '[GmailOAuthService] No serverAuthCode available (serverClientId not set). '
        'Email-only mode — OTP auto-read will not work without backend token exchange.',
      );
      return GmailOAuthResult(
        emailAddress: email,
        serverAuthCode: '', // empty signals backend to skip token exchange
      );
    }

    return GmailOAuthResult(
      emailAddress: email,
      serverAuthCode: serverAuthCode.trim(),
    );
  }

  /// Returns the currently signed-in Gmail email address, or null if none.
  Future<String?> getSignedInEmail() async {
    if (kIsWeb) return null;
    final client = _client;
    if (client == null) return null;
    try {
      final account = await client.signInSilently();
      return account?.email;
    } catch (_) {
      return null;
    }
  }

  /// Signs out of the attendance Gmail OAuth session only.
  /// Does NOT affect the StudyShare account session.
  Future<void> signOut() async {
    if (kIsWeb) return;
    final client = _client;
    if (client == null) return;
    try {
      await client.signOut();
    } catch (e) {
      debugPrint('[GmailOAuthService] signOut error (ignored): $e');
    }
  }
}
