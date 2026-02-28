
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:ui';
import '../../config/theme.dart';
import '../../providers/theme_provider.dart';
import '../../services/auth_service.dart';
import 'edit_profile_screen.dart';
import 'help_support_screen.dart';
import 'saved_posts_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../services/subscription_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../widgets/paywall_dialog.dart';
import '../../utils/theme_animator.dart';
import 'package:lottie/lottie.dart';

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
  final String? adminKey;

  const SettingsScreen({
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
    this.adminKey,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const double _kSwitchFallbackOffsetRight = 40.0;
  
  static const Color darkCardBackground = Color(0xFF1C1C1E);
  static const Color lightSystemBackground = Color(0xFFF2F2F7);
  static const Color darkSystemBackground = Color(0xFF000000);

  final AuthService _authService = AuthService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  String? _displayName;
  String? _photoUrl;
  String? _bio;
  bool _notificationsEnabled = true;
  bool _isLoading = true;
  bool _isPremium = false;
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _displayName = widget.displayName;
    _photoUrl = widget.photoUrl;
    _bio = widget.bio;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final (prefs, isPremium, packageInfo) = await (
        SharedPreferences.getInstance().then<SharedPreferences?>((v) => v).catchError((e, st) {
          debugPrint('Error loading SharedPreferences: $e\n$st');
          return null;
        }),
        _subscriptionService.isPremium().then<bool?>((v) => v).catchError((e, st) {
          debugPrint('Error loading premium status: $e\n$st');
          return null;
        }),
        PackageInfo.fromPlatform().then<PackageInfo?>((v) => v).catchError((e, st) {
          debugPrint('Error loading package info: $e\n$st');
          return null;
        }),
      ).wait;

      if (mounted) {
        setState(() {
          if (prefs != null) {
            _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', value);
    } catch (e) {
      if (mounted) {
        setState(() => _notificationsEnabled = previousValue);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update notification settings')),
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
          const SnackBar(content: Text('Failed to clear cache. Please try again.')),
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
          backgroundColor: AppTheme.darkSurface,
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
                child: const Icon(Icons.logout_rounded, color: AppTheme.error, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Sign Out',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to sign out of your account?',
            style: GoogleFonts.inter(color: AppTheme.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: AppTheme.textMuted),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
              ),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLegalDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? AppTheme.darkSurface 
            : Colors.white,
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Text(content, style: GoogleFonts.inter()),
        ),
        actions: [
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
        final bgColor = isDark ? _SettingsScreenState.darkSystemBackground : _SettingsScreenState.lightSystemBackground;

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
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Header Card
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? _SettingsScreenState.darkCardBackground : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _photoUrl != null && _photoUrl!.isNotEmpty
                            ? Image.network(
                                _photoUrl!,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Text(
                                      _displayName?.isNotEmpty == true ? _displayName![0].toUpperCase() : 'U',
                                      style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  );
                                },
                              )
                            : Center(
                                child: Text(
                                  _displayName?.isNotEmpty == true ? _displayName![0].toUpperCase() : 'U',
                                  style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName ?? 'User',
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.userEmail,
                              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                _buildSectionHeader('Account', isDark),
                _buildSettingsGroup(
                  isDark: isDark,
                  children: [
                    _buildGroupedTile(
                      icon: Icons.bookmark_outline_rounded,
                      iconBgColor: Colors.green.shade500,
                      title: 'Saved Posts',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => SavedPostsScreen(userEmail: widget.userEmail)));
                      },
                      isDark: isDark,
                    ),
                    _buildDivider(isDark),
                    _buildGroupedTile(
                      icon: _isPremium ? Icons.star_rounded : Icons.star_outline_rounded,
                      iconBgColor: Colors.orange.shade500,
                      title: _isPremium ? 'Premium Membership' : 'Upgrade to Premium',
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
                        activeColor: AppTheme.primary,
                        onChanged: (val) {
                          themeProvider.toggleTheme();
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
                        activeColor: AppTheme.primary,
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
                      onTap: () => _showLegalDialog('Privacy Policy', 'This is a placeholder for the Privacy Policy.\n\nWe value your privacy...'),
                      isDark: isDark,
                    ),
                    _buildDivider(isDark),
                    _buildGroupedTile(
                      icon: Icons.description_outlined,
                      iconBgColor: Colors.blueGrey.shade500,
                      title: 'Terms of Service',
                      onTap: () => _showLegalDialog('Terms of Service', 'This is a placeholder for the Terms of Service.\n\nBy using this app...'),
                      isDark: isDark,
                    ),
                    _buildDivider(isDark),
                    _buildGroupedTile(
                      icon: Icons.help_outline_rounded,
                      iconBgColor: Colors.deepPurple.shade400,
                      title: 'Help & Support',
                      onTap: () {
                         Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportScreen()));
                      },
                      isDark: isDark,
                    ),
                    _buildDivider(isDark),
                    _buildGroupedTile(
                      icon: Icons.info_outline_rounded,
                      iconBgColor: Colors.brown.shade400,
                      title: 'About MyStudySpace',
                      subtitle: 'Version $_appVersion',
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'MyStudySpace',
                          applicationVersion: _appVersion,
                          applicationIcon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.school, color: Colors.white),
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
                      backgroundColor: isDark ? _SettingsScreenState.darkCardBackground : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text('Sign Out', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16)),
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

  Widget _buildSettingsGroup({required List<Widget> children, required bool isDark}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? _SettingsScreenState.darkCardBackground : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1, 
      thickness: 0.5, 
      indent: 56, 
      color: isDark ? Colors.white12 : Colors.grey.shade200
    );
  }

  Widget _buildGroupedTile({
    required IconData icon,
    required Color iconBgColor,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    required bool isDark,
  }) {
    VoidCallback? fallbackTap = onTap;
    if (fallbackTap == null && trailing is Switch) {
      final switchTrailing = trailing as Switch;
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // Reduced vertical padding
          child: Row(
            children: [
              Container(
                width: 28, // Reduced from 30
                height: 28, // Reduced from 30
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 16), // Reduced from 18
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
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 15, // Reduced from 16
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 12, // Reduced from 13
                        ),
                      ),
                    ]
                  ],
                ),
              ),
              trailing ?? Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white38 : Colors.black38, size: 20), // Added fixed smaller size
            ],
          ),
        ),
      ),
    );
  }
}
