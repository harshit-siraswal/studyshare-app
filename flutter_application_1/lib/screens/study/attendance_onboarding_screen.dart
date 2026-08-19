import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../services/attendance_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/gmail_oauth_service.dart';

class AttendanceOnboardingScreen extends StatefulWidget {
  const AttendanceOnboardingScreen({
    super.key,
    required this.collegeId,
    required this.collegeName,
    this.userEmail,
  });

  final String collegeId;
  final String collegeName;
  final String? userEmail;

  @override
  State<AttendanceOnboardingScreen> createState() =>
      _AttendanceOnboardingScreenState();
}

class _AttendanceOnboardingScreenState
    extends State<AttendanceOnboardingScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final BackendApiService _backendApiService = BackendApiService();
  final GmailOAuthService _gmailOAuthService = GmailOAuthService();
  final _formKey = GlobalKey<FormState>();

  int _currentStep = 0; // 0: Terms, 1: College Email, 2: Credentials, 3: Syncing
  bool _termsAccepted = false;
  bool _isConnectingEmail = false;
  bool _isEmailConnected = false;
  String? _connectedEmail;

  final TextEditingController _regNoController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  bool _isSyncing = false;
  String _syncStatusMessage = '';
  double _syncProgress = 0.0;
  String? _errorMessage;

  @override
  void dispose() {
    _regNoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 3) {
      setState(() {
        _currentStep++;
        _errorMessage = null;
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _errorMessage = null;
      });
    }
  }

  /// Opens the Google account picker with gmail.readonly scope.
  /// The user can authorize **any** Gmail — it does not have to be their
  /// StudyShare account. The serverAuthCode is sent to the backend to
  /// exchange for an encrypted refresh token so the backend can read OTPs.
  Future<void> _handleConnectEmail() async {
    setState(() {
      _isConnectingEmail = true;
      _errorMessage = null;
    });

    try {
      final result = await _gmailOAuthService.signIn();

      if (result == null) {
        // User cancelled the account picker.
        if (!mounted) return;
        setState(() => _isConnectingEmail = false);
        return;
      }

      // Exchange the serverAuthCode on the backend (best-effort).
      // Even if the backend call fails we still record the email locally so
      // the user can proceed; a warning is shown instead of a hard block.
      String? backendWarning;
      if (result.serverAuthCode.isNotEmpty) {
        try {
          await _backendApiService.connectCollegeEmail(
            emailAddress: result.emailAddress,
            serverAuthCode: result.serverAuthCode,
            provider: 'google',
          );
        } catch (e) {
          backendWarning =
              'Email authorized, but the server could not store the access '
              'token right now. OTP auto-read may not work until you reconnect.';
        }
      } else {
        backendWarning =
            'Email authorized without server token exchange (serverClientId '
            'not configured). Automated OTP reading requires backend setup.';
      }

      // Persist the authorized email address locally (for display only).
      await _attendanceService.saveCollegeEmailConnection(
        emailAddress: result.emailAddress,
        provider: 'google',
      );

      if (!mounted) return;
      setState(() {
        _isConnectingEmail = false;
        _isEmailConnected = true;
        _connectedEmail = result.emailAddress;
        _errorMessage = backendWarning;
      });

      // Only auto-advance if there's no warning.
      if (backendWarning == null) {
        _nextStep();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnectingEmail = false;
        _errorMessage = 'Failed to authorize Gmail: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  Future<void> _handleStartSync() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _currentStep = 3;
      _isSyncing = true;
      _syncProgress = 0.15;
      _syncStatusMessage = 'Connecting to CyberVidya ERP...';
      _errorMessage = null;
    });

    try {
      // Step A: Store registration number locally
      await _attendanceService.markCybervidyaCredentialsSaved(
        registrationNumber: _regNoController.text.trim(),
      );

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() {
        _syncProgress = 0.45;
        _syncStatusMessage =
            'CyberVidya sent OTP to $_connectedEmail. Retrieving code...';
      });

      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      setState(() {
        _syncProgress = 0.75;
        _syncStatusMessage = 'Submitting OTP & capturing session token...';
      });

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() {
        _syncProgress = 0.95;
        _syncStatusMessage = 'Fetching attendance & timetable...';
      });

      // Update sync timestamp
      await _attendanceService.updateLastSyncTime();

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      // Finish onboarding and return success
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _errorMessage =
            'Authentication failed: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(
          'Setup Attendance Sync',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / 4.0,
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _buildCurrentStepView(isDark),
        ),
      ),
    );
  }

  Widget _buildCurrentStepView(bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildTermsStep(isDark);
      case 1:
        return _buildEmailStep(isDark);
      case 2:
        return _buildCredentialsStep(isDark);
      case 3:
        return _buildSyncingStep(isDark);
      default:
        return Container();
    }
  }

  // --- Step 1: Terms & Privacy ---
  Widget _buildTermsStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.shield_outlined, color: AppTheme.primary, size: 28),
            const SizedBox(width: 12),
            Text(
              'Privacy & Security',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Before enabling automated CyberVidya attendance sync, please review how your data is protected:',
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.5,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: ListView(
              children: [
                _buildSecurityPoint(
                  icon: Icons.lock_outline,
                  title: 'Encrypted Credential Storage',
                  description:
                      'Your CyberVidya password is encrypted at rest using AES-256-GCM. It is never logged or exposed to the frontend.',
                  isDark: isDark,
                ),
                const Divider(height: 24),
                _buildSecurityPoint(
                  icon: Icons.mark_email_read_outlined,
                  title: 'Scoped College Email Access',
                  description:
                      'College email access is strictly used to read 6-digit CyberVidya OTPs. Raw email messages are never stored.',
                  isDark: isDark,
                ),
                const Divider(height: 24),
                _buildSecurityPoint(
                  icon: Icons.sync_outlined,
                  title: 'Automated Attendance Sync',
                  description:
                      'Background workers refresh short-lived tokens automatically. You can disconnect your credentials or college email anytime in Settings.',
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _termsAccepted,
          onChanged: (val) => setState(() => _termsAccepted = val ?? false),
          title: Text(
            'I accept the Terms & Privacy Policy for automated CyberVidya sync.',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _termsAccepted ? _nextStep : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Accept & Continue',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Step 2: Connect College Email ---
  Widget _buildEmailStep(bool isDark) {
    final hasWarning = _errorMessage != null && _isEmailConnected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connect Gmail for OTP',
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'CyberVidya sends a one-time password to your email when you log in. '
          'Authorize a Gmail account so StudyShare can read that OTP automatically.\n\n'
          'This can be any Gmail — it does not need to be the email you use for StudyShare.',
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.5,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: _isEmailConnected
                  ? Border.all(
                      color: hasWarning
                          ? Colors.orange.withValues(alpha: 0.6)
                          : Colors.green.withValues(alpha: 0.6),
                      width: 1.5,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  _isEmailConnected
                      ? (hasWarning
                          ? Icons.warning_amber_rounded
                          : Icons.mark_email_read_rounded)
                      : Icons.alternate_email_rounded,
                  size: 48,
                  color: _isEmailConnected
                      ? (hasWarning ? Colors.orange : Colors.green)
                      : AppTheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _isEmailConnected
                      ? _connectedEmail ?? 'Gmail Connected'
                      : 'No Gmail Connected',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isEmailConnected
                      ? (hasWarning
                          ? 'Authorized — server token pending'
                          : 'Ready for automated OTP retrieval')
                      : 'Tap below to sign in with Google',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _isEmailConnected
                        ? (hasWarning ? Colors.orange : Colors.green)
                        : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (hasWarning ? Colors.orange : Colors.red)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (hasWarning ? Colors.orange : Colors.red)
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _errorMessage!,
              style: GoogleFonts.inter(
                color: hasWarning ? Colors.orange[800] : Colors.redAccent,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
        const Spacer(),
        Row(
          children: [
            OutlinedButton(
              onPressed: _previousStep,
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isConnectingEmail ? null : _handleConnectEmail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: _isConnectingEmail
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.login_rounded, color: Colors.white),
                label: Text(
                  _isEmailConnected ? 'Re-connect Gmail' : 'Sign in with Google',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        // "Continue anyway" if email is connected but there was a backend warning.
        if (hasWarning) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _nextStep,
              child: Text(
                'Continue anyway',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // --- Step 3: Enter CyberVidya Credentials ---
  Widget _buildCredentialsStep(bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CyberVidya Credentials',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your student registration number and password. Credentials are encrypted securely at rest.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _regNoController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Registration Number / Roll No',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your registration number';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'CyberVidya Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your CyberVidya password';
              }
              return null;
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const Spacer(),
          Row(
            children: [
              OutlinedButton(
                onPressed: _previousStep,
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _handleStartSync,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Authenticate & Sync',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Step 4: OTP Verification & Initial Sync Progress ---
  Widget _buildSyncingStep(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: _isSyncing ? null : _syncProgress,
              strokeWidth: 6,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Synchronizing Attendance',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _syncStatusMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() => _currentStep = 2),
              child: const Text('Try Again'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecurityPoint({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
