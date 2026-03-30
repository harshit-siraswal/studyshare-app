import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  final String collegeName;
  final String collegeDomain;
  final String collegeId;
  final VoidCallback onChangeCollege;
  final String? initialErrorMessage;
  final bool startInEmailVerificationMode;
  final String? initialEmail;
  final Future<void> Function()? onUseDifferentEmail;

  const LoginScreen({
    super.key,
    required this.collegeName,
    required this.collegeDomain,
    required this.collegeId,
    required this.onChangeCollege,
    this.initialErrorMessage,
    this.startInEmailVerificationMode = false,
    this.initialEmail,
    this.onUseDifferentEmail,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showEmailVerification = false;
  bool _isResendingVerification = false;
  bool _isVerifyingEmail = false;
  bool _isChangingEmail = false;

  String _normalizeDisplayName(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  void initState() {
    super.initState();
    final initialEmail = widget.initialEmail?.trim();
    if (initialEmail != null && initialEmail.isNotEmpty) {
      _emailController.text = initialEmail;
    }
    _showEmailVerification = widget.startInEmailVerificationMode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialError = widget.initialErrorMessage?.trim();
      if (!mounted || initialError == null || initialError.isEmpty) return;
      _showError(initialError);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _formKey.currentState?.reset();
    });
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return; // Prevent double-tap

    setState(() => _isLoading = true);
    try {
      final result = await _authService.signInWithGoogle();
      if (result == null) {
        if (mounted) {
          _showError('Google sign-in was cancelled');
        }
        return;
      }

      final allowed = await _validateBanAfterLogin();
      if (!allowed) {
        return;
      }
      // Navigation handled by StreamBuilder in main.dart
    } catch (e, stackTrace) {
      debugPrint('Google Sign-In Error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        _showError(_authService.getErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitForm() async {
    if (_isLoading) return; // Prevent double-tap
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        debugPrint('Starting Email Sign-In...');
        await _authService.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
        debugPrint('Email Sign-In completed');
        if (_authService.requiresEmailVerificationForCurrentUser) {
          if (mounted) {
            setState(() => _showEmailVerification = true);
            _showWarning('Verify your email before continuing.');
          }
          return;
        }
        final allowed = await _validateBanAfterLogin();
        if (!allowed) {
          return;
        }
        // Navigation handled by StreamBuilder in main.dart
      } else {
        debugPrint('Starting Account Creation...');
        await _authService.createAccountWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _normalizeDisplayName(_nameController.text),
        );
        debugPrint('Account Creation completed');
        if (mounted) {
          setState(() => _showEmailVerification = true);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Email Auth Error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (!mounted) return;
      if (e is firebase_auth.FirebaseAuthException &&
          e.code == 'email-not-verified') {
        setState(() => _showEmailVerification = true);
      } else {
        _showError(_authService.getErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Please enter your email address');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      _showSuccess('Password reset email sent! Check your inbox.');
    } catch (e) {
      if (!mounted) return;
      _showError(_authService.getErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _validateBanAfterLogin() async {
    final email = _authService.userEmail?.trim();
    if (email == null || email.isEmpty) {
      await _authService.signOut();
      if (mounted) {
        _showError('Unable to validate your account. Please sign in again.');
      }
      return false;
    }

    try {
      final banResult = await _authService.checkBanStatus(
        email,
        widget.collegeId,
      );
      if (banResult?['banCheckSkipped'] == true) {
        debugPrint(
          'Ban check skipped after login for $email in ${widget.collegeId}; allowing session and relying on backend enforcement.',
        );
        return true;
      }
      if (banResult?['isBanned'] == true) {
        final reason =
            (banResult?['reason'] ??
                    'Your account has been restricted by an administrator.')
                .toString();
        await _authService.signOut();
        if (mounted) {
          _showError(reason);
        }
        return false;
      }

      return true;
    } catch (e) {
      debugPrint(
        'Ban check failed after login for $email in ${widget.collegeId}; allowing session and relying on backend enforcement. Error: $e',
      );
      return true;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.success),
    );
  }

  void _showWarning(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.warning,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showEmailVerification) {
      return _buildEmailVerificationScreen();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.darkBackground
          : AppTheme.lightSurface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              TextButton.icon(
                onPressed: widget.onChangeCollege,
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppTheme.textMuted,
                  size: 20,
                ),
                label: Text(
                  'Change college',
                  style: GoogleFonts.inter(color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 24),

              // Logo and header
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.school_rounded,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _isLogin ? 'Welcome back' : 'Create account',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.textOnDark
                      : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              // College name badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  widget.collegeName,
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Google Sign-in button
              _buildGoogleButton(),
              const SizedBox(height: 24),

              // Divider
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkBorder
                          : AppTheme.lightBorder,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Or continue with email',
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkBorder
                          : AppTheme.lightBorder,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Name field (signup only)
                    if (!_isLogin) ...[
                      _buildTextField(
                        controller: _nameController,
                        hint: 'Full name',
                        icon: Icons.person_outline_rounded,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your name';
                          }
                          final normalized = _normalizeDisplayName(value);
                          if (normalized.length < 2) {
                            return 'Name must be at least 2 characters';
                          }
                          if (normalized.length > 80) {
                            return 'Name must be 80 characters or fewer';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Email field
                    _buildTextField(
                      controller: _emailController,
                      hint: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        final emailPattern = RegExp(
                          r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
                        );
                        if (!emailPattern.hasMatch(value.trim())) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password field
                    _buildTextField(
                      controller: _passwordController,
                      hint: 'Password',
                      icon: Icons.lock_outline_rounded,
                      obscureText: _obscurePassword,
                      suffix: IconButton(
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (!_isLogin) {
                          final hasUppercase = RegExp(r'[A-Z]').hasMatch(value);
                          final hasLowercase = RegExp(r'[a-z]').hasMatch(value);
                          final hasDigit = RegExp(r'\d').hasMatch(value);
                          if (value.length < 12 ||
                              !hasUppercase ||
                              !hasLowercase ||
                              !hasDigit) {
                            return 'Use at least 12 characters with upper-case, lower-case, and a number.';
                          }
                        }
                        if (value.length > 128) {
                          return 'Password must be 128 characters or fewer';
                        }
                        return null;
                      },
                    ),

                    // Forgot password link
                    if (_isLogin) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _sendPasswordReset,
                          child: Text(
                            'Forgot password?',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitForm,
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                _isLogin ? 'Sign in' : 'Create account',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Toggle login/signup
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isLogin
                        ? "Don't have an account? "
                        : "Already have an account? ",
                    style: GoogleFonts.inter(color: AppTheme.textMuted),
                  ),
                  TextButton(
                    onPressed: _toggleMode,
                    child: Text(
                      _isLogin ? 'Sign up' : 'Sign in',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              // Role info
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.darkCard
                      : AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.darkBorder
                        : AppTheme.lightBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppTheme.primary.withValues(alpha: 0.7),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                          ),
                          children: [
                            const TextSpan(text: 'Use '),
                            TextSpan(
                              text: '@${widget.collegeDomain}',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const TextSpan(text: ' email for full access'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Google icon - Use local SVG asset for reliability
            SvgPicture.asset(
              'assets/images/google_logo.svg',
              width: 24,
              height: 24,
            ),
            const SizedBox(width: 12),
            Text(
              'Continue with Google',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(
        color: isDark ? AppTheme.textOnDark : AppTheme.textPrimary,
      ),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
        prefixIcon: Icon(icon, color: AppTheme.textMuted),
        suffixIcon: suffix,
        filled: true,
        fillColor: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.error),
        ),
      ),
    );
  }

  Widget _buildEmailVerificationScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    const wiseGreen = Color(0xFF9FE870); // Wise-like lime green

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () {
            setState(() => _showEmailVerification = false);
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // 3D-style Email Icon (Container with gradient/shadow to mock it)
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF00B2FF),
                      Color(0xFF0066FF),
                    ], // Blue gradient like Wise envelope
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0066FF).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.alternate_email_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // Huge Bold Title
              Text(
                'CHECK YOUR\nEMAIL',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 36,
                  fontWeight: FontWeight.w900, // Black weight
                  height: 0.9,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Instruction
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 16,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(
                      text: 'Follow the link in the email we sent to\n',
                    ),
                    TextSpan(
                      text: _emailController.text,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const TextSpan(text: '. The email can take up to '),
                    TextSpan(
                      text: '1 minute',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ' to arrive.'),
                  ],
                ),
              ),

              const Spacer(),

              // Primary Action (Lime Green)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isVerifyingEmail
                      ? null
                      : () async {
                          setState(() => _isVerifyingEmail = true);
                          try {
                            await _authService.reloadUser();
                            if (!mounted) return;
                            final isVerified = _authService.isEmailVerified;
                            if (isVerified) {
                              _showSuccess('Email verified successfully.');
                              setState(() => _showEmailVerification = false);
                            } else {
                              _showError(
                                'Email is not verified yet. Please open the verification link and try again.',
                              );
                            }
                          } catch (e) {
                            if (!mounted) return;
                            _showError(_authService.getErrorMessage(e));
                          } finally {
                            if (mounted) {
                              setState(() => _isVerifyingEmail = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: wiseGreen,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isVerifyingEmail
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.black,
                            ),
                          ),
                        )
                      : Text(
                          'I verified my email',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Secondary Action (Resend)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: _isResendingVerification
                      ? null
                      : () async {
                          setState(() => _isResendingVerification = true);
                          try {
                            await _authService.resendVerificationEmail();
                            _showSuccess('Verification email sent!');
                          } catch (e) {
                            _showError(_authService.getErrorMessage(e));
                          } finally {
                            if (mounted) {
                              setState(() => _isResendingVerification = false);
                            }
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : Colors.black,
                    side: BorderSide(
                      color: isDark ? Colors.white24 : Colors.black12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isResendingVerification
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        )
                      : Text(
                          'Resend email',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),

              // Back/Change email option
              TextButton(
                onPressed: _isChangingEmail
                    ? null
                    : () async {
                        if (_isChangingEmail) return;
                        if (mounted) {
                          setState(() => _isChangingEmail = true);
                        }
                        try {
                          final callback = widget.onUseDifferentEmail;
                          if (callback != null) {
                            await callback();
                          }
                          if (mounted) {
                            setState(() => _showEmailVerification = false);
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isChangingEmail = false);
                          }
                        }
                      },
                child: Text(
                  'Use a different email',
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
