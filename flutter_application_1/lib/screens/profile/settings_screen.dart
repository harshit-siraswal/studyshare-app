import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:ui';
import '../../config/app_config.dart';
import '../../config/legal_documents.dart';
import '../../config/theme.dart';
import '../../providers/theme_provider.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import 'help_support_screen.dart';
import 'saved_posts_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../services/push_notification_service.dart';
import '../../services/subscription_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../widgets/paywall_dialog.dart';
import '../../utils/theme_animator.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final String userEmail;
  final String? displayName;
  final String? photoUrl;
  final String? bio;
  final ThemeProvider themeProvider;
  final String userRole;
  final String? semester;
  final String? branch;
  final AuthService authService;
  final SubscriptionService subscriptionService;
  final PushNotificationService pushNotificationService;

  SettingsScreen({
    super.key,
    required this.onLogout,
    required this.userEmail,
    this.displayName,
    this.photoUrl,
    this.bio,
    required this.themeProvider,
    this.userRole = 'READ_ONLY',
    this.semester,
    this.branch,
    AuthService? authService,
    SubscriptionService? subscriptionService,
    PushNotificationService? pushNotificationService,
  }) : authService = authService ?? AuthService(),
       subscriptionService = subscriptionService ?? SubscriptionService(),
       pushNotificationService =
           pushNotificationService ?? PushNotificationService();

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color darkCardBackground = Color(0xFF1C1C1E);
  static const Color lightSystemBackground = Color(0xFFF2F2F7);
  static const Color darkSystemBackground = Color(0xFF000000);

  late final AuthService _authService;
  final BackendApiService _backendApiService = BackendApiService();
  late final SubscriptionService _subscriptionService;
  late final PushNotificationService _pushNotificationService;
  bool _notificationsEnabled = true;
  bool _isLoading = true;
  bool _isPremium = false;
  bool _isDeletingAccount = false;
  String _appVersion = '...';

  @override
  void initState() {
    super.initState();
    _authService = widget.authService;
    _subscriptionService = widget.subscriptionService;
    _pushNotificationService = widget.pushNotificationService;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final (prefs, isPremium, packageInfo) = await (
        SharedPreferences.getInstance()
            .then<SharedPreferences?>((v) => v)
            .catchError((e, st) {
              debugPrint('Error loading SharedPreferences: $e\n$st');
              return null;
            }),
        _subscriptionService.isPremium().then<bool?>((v) => v).catchError((
          e,
          st,
        ) {
          debugPrint('Error loading premium status: $e\n$st');
          return null;
        }),
        PackageInfo.fromPlatform().then<PackageInfo?>((v) => v).catchError((
          e,
          st,
        ) {
          debugPrint('Error loading package info: $e\n$st');
          return null;
        }),
      ).wait;

      if (mounted) {
        setState(() {
          if (prefs != null) {
            _notificationsEnabled =
                prefs.getBool('notifications_enabled') ?? true;
          }
          if (isPremium != null) _isPremium = isPremium;
          if (packageInfo != null) _appVersion = packageInfo.version;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    final previousValue = _notificationsEnabled;
    setState(() => _notificationsEnabled = value);
    try {
      await _pushNotificationService.setNotificationsEnabled(value);
    } catch (e) {
      debugPrint('Failed to update notification settings: $e');
      if (mounted) {
        setState(() => _notificationsEnabled = previousValue);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update notification settings'),
          ),
        );
      }
    }
  }

  Future<void> _clearCache() async {
    try {
      // Clear image cache
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // Clear disk cache
      await DefaultCacheManager().emptyCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared successfully')),
        );
      }
    } catch (e, st) {
      debugPrint('Clear cache failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to clear cache. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor:
              Theme.of(dialogContext).dialogTheme.backgroundColor ??
              Theme.of(dialogContext).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppTheme.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Sign Out',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(dialogContext).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to sign out of your account?',
            style: GoogleFonts.inter(
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext); // Close dialog
                await _authService.signOut();
                if (mounted) {
                  Navigator.pop(context); // Close settings using State context
                  widget.onLogout();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleDeleteAccount() async {
    if (_isDeletingAccount) return;

    final confirmationController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
          title: Text(
            'Delete account?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently removes your account and your app access. '
                'Type DELETE to confirm.',
                style: GoogleFonts.inter(fontSize: 13.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmationController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final isMatch =
                    confirmationController.text.trim().toUpperCase() ==
                    'DELETE';
                Navigator.pop(dialogContext, isMatch);
              },
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    confirmationController.dispose();

    if (confirmed != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deletion cancelled or not confirmed.'),
          ),
        );
      }
      return;
    }

    setState(() => _isDeletingAccount = true);
    try {
      await _backendApiService.deleteAccount(confirmation: 'DELETE');
      await _authService.signOut();
      if (!mounted) return;
      Navigator.pop(context);
      widget.onLogout();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', '').trim().isNotEmpty
                ? e.toString().replaceFirst('Exception: ', '').trim()
                : 'Failed to delete account.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
      }
    }
  }

  Future<void> _openExternalLink(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid link for this legal document.')),
      );
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open legal document link.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open legal document link.')),
      );
    }
  }

  void _showLegalDialog(
    String title,
    String content, {
    String? onlineUrl,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkSurface
            : Colors.white,
        title: Text(
          title,
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Text(content, style: GoogleFonts.inter()),
        ),
        actions: [
          if (onlineUrl != null)
            TextButton(
              onPressed: () => _openExternalLink(onlineUrl),
              child: const Text('View Online'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.themeProvider,
      builder: (context, child) {
        final themeProvider = widget.themeProvider;
        final isDark = themeProvider.isDarkMode;
        final textColor = isDark ? Colors.white : Colors.black;
        final bgColor = isDark
            ? _SettingsScreenState.darkSystemBackground
            : _SettingsScreenState.lightSystemBackground;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: Text(
              'Settings',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            backgroundColor: bgColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Account', isDark),
                      _buildSettingsGroup(
                        isDark: isDark,
                        children: [
                          _buildGroupedTile(
                            icon: Icons.bookmark_outline_rounded,
                            iconBgColor: Colors.green.shade500,
                            title: 'Saved Posts',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SavedPostsScreen(
                                    userEmail: widget.userEmail,
                                  ),
                                ),
                              );
                            },
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildGroupedTile(
                            icon: _isPremium
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            iconBgColor: Colors.orange.shade500,
                            title: _isPremium
                                ? 'Premium Membership'
                                : 'Upgrade to Premium',
                            subtitle: _isPremium ? 'Active' : null,
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => PaywallDialog(
                                  onSuccess: () => _loadSettings(),
                                ),
                              );
                            },
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildGroupedTile(
                            icon: Icons.delete_forever_outlined,
                            iconBgColor: Colors.red.shade600,
                            title: 'Delete Account',
                            subtitle: _isDeletingAccount
                                ? 'Removing your account...'
                                : 'Permanently remove your account',
                            onTap: _isDeletingAccount
                                ? null
                                : _handleDeleteAccount,
                            isDark: isDark,
                            titleColor: Colors.red.shade600,
                            trailing: _isDeletingAccount
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                      _buildSectionHeader('App Settings', isDark),
                      _buildSettingsGroup(
                        isDark: isDark,
                        children: [
                          _buildGroupedTile(
                            icon: Icons.brightness_6_outlined,
                            iconBgColor: Colors.indigo.shade500,
                            title: 'Appearance',
                            trailing: Switch.adaptive(
                              value: isDark,
                              activeThumbColor: AppTheme.primary,
                              onChanged: (_) {
                                animateThemeTransition(context, () {
                                  themeProvider.toggleTheme();
                                });
                              },
                            ),
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildGroupedTile(
                            icon: Icons.notifications_none_rounded,
                            iconBgColor: Colors.red.shade400,
                            title: 'Notifications',
                            trailing: Switch.adaptive(
                              value: _notificationsEnabled,
                              activeThumbColor: AppTheme.primary,
                              onChanged: _toggleNotifications,
                            ),
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildGroupedTile(
                            icon: Icons.cleaning_services_outlined,
                            iconBgColor: Colors.teal.shade500,
                            title: 'Clear Cache',
                            onTap: _clearCache,
                            isDark: isDark,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                      _buildSectionHeader('About', isDark),
                      _buildSettingsGroup(
                        isDark: isDark,
                        children: [
                          _buildGroupedTile(
                            icon: Icons.privacy_tip_outlined,
                            iconBgColor: Colors.grey.shade600,
                            title: 'Privacy Policy',
                            onTap: () => _showLegalDialog(
                              'Privacy Policy',
                              LegalDocuments.privacyPolicy(
                                supportEmail: AppConfig.supportEmail,
                              ),
                              onlineUrl: LegalDocuments.privacyPolicyUrl,
                            ),
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildGroupedTile(
                            icon: Icons.description_outlined,
                            iconBgColor: Colors.blueGrey.shade500,
                            title: 'Terms of Use',
                            onTap: () => _showLegalDialog(
                              'Terms of Use',
                              LegalDocuments.termsOfUse(
                                supportEmail: AppConfig.supportEmail,
                              ),
                              onlineUrl: LegalDocuments.termsOfUseUrl,
                            ),
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildGroupedTile(
                            icon: Icons.groups_2_outlined,
                            iconBgColor: Colors.indigo.shade500,
                            title: 'Community Guidelines',
                            onTap: () => _showLegalDialog(
                              'Community Guidelines',
                              LegalDocuments.communityGuidelines(
                                supportEmail: AppConfig.supportEmail,
                              ),
                              onlineUrl: LegalDocuments.communityGuidelinesUrl,
                            ),
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildGroupedTile(
                            icon: Icons.delete_sweep_outlined,
                            iconBgColor: Colors.red.shade500,
                            title: 'Account & Data Deletion',
                            onTap: () => _showLegalDialog(
                              'Account & Data Deletion',
                              LegalDocuments.accountDeletionPolicy(
                                supportEmail: AppConfig.supportEmail,
                              ),
                              onlineUrl: LegalDocuments.accountDeletionUrl,
                            ),
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildGroupedTile(
                            icon: Icons.help_outline_rounded,
                            iconBgColor: Colors.deepPurple.shade400,
                            title: 'Help & Support',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HelpSupportScreen(),
                                ),
                              );
                            },
                            isDark: isDark,
                          ),
                          _buildDivider(isDark),
                          _buildGroupedTile(
                            icon: Icons.info_outline_rounded,
                            iconBgColor: Colors.brown.shade400,
                            title: 'About StudyShare',
                            subtitle: 'Version $_appVersion',
                            onTap: () {
                              showAboutDialog(
                                context: context,
                                applicationName: 'StudyShare',
                                applicationVersion: _appVersion,
                                applicationIcon: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.school,
                                    color: Colors.white,
                                  ),
                                ),
                              );
                            },
                            isDark: isDark,
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 20),
                        child: TextButton(
                          onPressed: _handleLogout,
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: isDark
                                ? _SettingsScreenState.darkCardBackground
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            'Sign Out',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 16),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white60 : Colors.black54,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup({
    required List<Widget> children,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? _SettingsScreenState.darkCardBackground : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 56,
      color: isDark ? Colors.white12 : Colors.grey.shade200,
    );
  }

  Widget _buildGroupedTile({
    required IconData icon,
    required Color iconBgColor,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    Color? titleColor,
    required bool isDark,
  }) {
    VoidCallback? fallbackTap = onTap;
    if (fallbackTap == null && trailing is Switch) {
      final switchTrailing = trailing;
      if (switchTrailing.onChanged != null) {
        fallbackTap = () => switchTrailing.onChanged!(!switchTrailing.value);
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: fallbackTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w500,
                        color:
                            titleColor ??
                            (isDark ? Colors.white : Colors.black),
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    // Keep trailing chevron compact to match dense tile layout.
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white38 : Colors.black38,
                    size: 20,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
