import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  // Only create GoogleSignIn for mobile platforms
  GoogleSignIn? _googleSignIn;
  SupabaseClient get _supabase => Supabase.instance.client;
  
  AuthService() {
    // Only initialize GoogleSignIn on mobile (not web)
    if (!kIsWeb) {
      // CRITICAL: serverClientId is the Web Client ID from google-services.json
      // This is required for Android to work with Firebase Auth
      _googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: '28032445048-kg3k969ha8c9kc88hta90tddf5178n1o.apps.googleusercontent.com',
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

  /// Sign in with Google
  Future<firebase_auth.UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = firebase_auth.GoogleAuthProvider();
        provider.addScope('email');
        provider.addScope('profile');
        
        final userCredential = await _auth.signInWithPopup(provider);
        
        if (userCredential.user != null) {
          await _saveUserToDatabase(userCredential.user!);
        }
        
        return userCredential;
      }
      
      if (_googleSignIn == null) {
        debugPrint('GoogleSignIn not initialized (web platform?)');
        throw Exception('Google Sign-In is not available on this platform');
      }
      
      final GoogleSignInAccount? googleUser = await _googleSignIn!.signIn();
      if (googleUser == null) return null;
      
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
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
  Future<firebase_auth.UserCredential> signInWithEmail(String email, String password) async {
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
  Future<Map<String, dynamic>?> checkBanStatus(String email, String? collegeId) async {
    try {
      final globalBan = await _supabase
          .from('banned_users')
          .select()
          .eq('user_email', email)
          .isFilter('college_id', null)
          .maybeSingle();
      
      if (globalBan != null) {
        return {
          'isBanned': true,
          'reason': globalBan['reason'] ?? 'You have been banned.',
          'isGlobal': true,
        };
      }
      
      if (collegeId != null) {
        final collegeBan = await _supabase
            .from('banned_users')
            .select()
            .eq('user_email', email)
            .eq('college_id', collegeId)
            .maybeSingle();
        
        if (collegeBan != null) {
          return {
            'isBanned': true,
            'reason': collegeBan['reason'] ?? 'You have been banned from this college.',
            'isGlobal': false,
          };
        }
      }
      
      return {'isBanned': false};
    } catch (e) {
      debugPrint('Error checking ban status: $e');
      return {'isBanned': false};
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

      // Ensure Supabase is initialized
      try {
           // We can't easily check 'mounted' on singleton in this context without BuildContext,
           // but we can check if client is accessible.
           // However, _supabase is initialized in member variable.
      } catch (e) {
          debugPrint('Supabase not initialized: $e');
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
        await _supabase.from('users').insert({
          'email': email,
          'display_name': user.displayName ?? email.split('@')[0],
          'profile_photo_url': user.photoURL,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).timeout(const Duration(seconds: 5));
        debugPrint('User saved to database: $email');
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
        debugPrint('User updated in database: $email');
      }
    } on TimeoutException {
      debugPrint('Database save timeout - user sign-in will proceed');
      // Don't throw - allow sign-in to proceed
    } on PostgrestException catch (e) {
      debugPrint('Supabase database error: ${e.message}');
      // Check if it's a constraint violation (user might already exist)
      if (e.code == '23505') { // Unique violation
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
