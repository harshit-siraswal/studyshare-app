import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../services/attendance_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/gmail_oauth_service.dart';

class AttendanceSettingsTile extends StatefulWidget {
  const AttendanceSettingsTile({
    super.key,
    required this.collegeId,
    required this.collegeName,
    this.userEmail,
    this.onSettingsChanged,
  });

  final String collegeId;
  final String collegeName;
  final String? userEmail;
  final VoidCallback? onSettingsChanged;

  @override
  State<AttendanceSettingsTile> createState() => _AttendanceSettingsTileState();
}

class _AttendanceSettingsTileState extends State<AttendanceSettingsTile> {
  final AttendanceService _attendanceService = AttendanceService();
  final BackendApiService _backendApiService = BackendApiService();
  final GmailOAuthService _gmailOAuthService = GmailOAuthService();

  bool _isLoading = true;
  bool _isEmailConnected = false;
  String? _connectedEmail;
  bool _isCybervidyaConnected = false;
  String? _savedRegNo;
  DateTime? _lastSyncTime;
  bool _isConnectingEmail = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsState();
  }

  Future<void> _loadSettingsState() async {
    setState(() => _isLoading = true);
    final emailConn = await _attendanceService.isCollegeEmailConnected();
    final email = await _attendanceService.getConnectedCollegeEmail();
    final cvConn = await _attendanceService.isCybervidyaAccountConnected();
    final regNo = await _attendanceService.getSavedRegistrationNumber();
    final lastSync = await _attendanceService.getLastSyncTime();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isEmailConnected = emailConn;
      _connectedEmail = email;
      _isCybervidyaConnected = cvConn;
      _savedRegNo = regNo;
      _lastSyncTime = lastSync;
    });
  }

  /// Drives the real Gmail OAuth flow from the Settings page.
  Future<void> _connectEmail() async {
    setState(() => _isConnectingEmail = true);
    try {
      final result = await _gmailOAuthService.signIn();
      if (result == null) {
        // user cancelled
        if (!mounted) return;
        setState(() => _isConnectingEmail = false);
        return;
      }

      // Best-effort backend token exchange.
      if (result.serverAuthCode.isNotEmpty) {
        try {
          await _backendApiService.connectCollegeEmail(
            emailAddress: result.emailAddress,
            serverAuthCode: result.serverAuthCode,
            provider: 'google',
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Email authorized but server could not store the token. '
                  'OTP auto-read may not work until reconnected.',
                ),
              ),
            );
          }
        }
      }

      await _attendanceService.saveCollegeEmailConnection(
        emailAddress: result.emailAddress,
        provider: 'google',
      );

      await _loadSettingsState();
      widget.onSettingsChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gmail sign-in failed: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnectingEmail = false);
    }
  }

  Future<void> _disconnectEmail() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect College Email'),
        content: const Text(
          'Are you sure you want to disconnect your college email? Automated OTP retrieval will be paused until re-connected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _attendanceService.disconnectCollegeEmail();
      await _loadSettingsState();
      widget.onSettingsChanged?.call();
    }
  }

  Future<void> _disconnectCybervidya() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect CyberVidya Account'),
        content: const Text(
          'Are you sure you want to log out and delete stored CyberVidya credentials? You will need to log in again to sync attendance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _attendanceService.disconnectCybervidyaAccount(
        widget.collegeId,
        userEmail: widget.userEmail,
      );
      await _loadSettingsState();
      widget.onSettingsChanged?.call();
    }
  }

  Future<void> _triggerManualSync() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Triggering background attendance sync...')),
    );
    await _attendanceService.updateLastSyncTime();
    await _loadSettingsState();
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.school_rounded,
                  color: AppTheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  'CyberVidya Attendance Integration',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // --- College Email Section ---
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.mark_email_read_outlined,
                color: _isEmailConnected ? Colors.green : Colors.grey,
              ),
              title: Text(
                'College Email',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              subtitle: Text(
                _isEmailConnected
                    ? 'Connected: ${_connectedEmail ?? widget.userEmail ?? "Mailbox"}'
                    : 'Not Connected',
                style: GoogleFonts.inter(fontSize: 12),
              ),
              trailing: _isEmailConnected
                  ? TextButton(
                      onPressed: _disconnectEmail,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                      child: const Text('Unsync'),
                    )
                  : ElevatedButton(
                      onPressed: _isConnectingEmail ? null : _connectEmail,
                      child: _isConnectingEmail
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Connect'),
                    ),
            ),
            const Divider(height: 16),

            // --- CyberVidya Account Section ---
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.account_box_outlined,
                color: _isCybervidyaConnected ? Colors.green : Colors.grey,
              ),
              title: Text(
                'CyberVidya Account',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              subtitle: Text(
                _isCybervidyaConnected
                    ? 'Connected (Reg: ${_savedRegNo ?? "Saved"})'
                    : 'Not Connected',
                style: GoogleFonts.inter(fontSize: 12),
              ),
              trailing: _isCybervidyaConnected
                  ? TextButton(
                      onPressed: _disconnectCybervidya,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                      child: const Text('Log Out'),
                    )
                  : ElevatedButton(
                      onPressed: () {
                        // Launch setup flow
                      },
                      child: const Text('Setup'),
                    ),
            ),
            const Divider(height: 16),

            // --- Sync Status Section ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last Synchronized',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _lastSyncTime != null
                          ? '${_lastSyncTime!.day}/${_lastSyncTime!.month}/${_lastSyncTime!.year} at ${_lastSyncTime!.hour}:${_lastSyncTime!.minute.toString().padLeft(2, '0')}'
                          : 'Never synchronized',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: _isCybervidyaConnected ? _triggerManualSync : null,
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('Sync Now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
