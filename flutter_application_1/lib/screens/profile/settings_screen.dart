
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

  const SettingsScreen({
    super.key,
    required this.onLogout,
    required this.userEmail,
    this.displayName,
    this.photoUrl,
    this.bio,
    required this.themeProvider,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const double _kSwitchFallbackOffsetRight = 40.0;

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
    final prefs = await SharedPreferences.getInstance();
    final isPremium = await _subscriptionService.isPremium();
    final packageInfo = await PackageInfo.fromPlatform();
    
    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
        _isPremium = isPremium;
        _appVersion = packageInfo.version;
        _isLoading = false;
      });
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear cache: $e')),
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

        return Scaffold(
          backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
          appBar: AppBar(
            title: Text(
              'Settings',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Account', textColor),
                _buildSettingsTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Edit Profile',
                  subtitle: 'Change name, bio, and photo',
                  onTap: () async {
                    final updatedFn = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(
                          initialName: _displayName ?? '',
                          initialPhotoUrl: _photoUrl,
                          initialBio: _bio,
                        ),
                      ),
                    );
                    
                    if (updatedFn != null && updatedFn is Map<String, dynamic> && mounted) {
                       setState(() {
                         _displayName = updatedFn['display_name']?.toString();
                         _photoUrl = updatedFn['profile_photo_url']?.toString();
                         _bio = updatedFn['bio']?.toString();
                       });
                    }
                  },
                  isDark: isDark,
                ),
                _buildSettingsTile(
                  icon: Icons.bookmark_outline_rounded,
                  title: 'Saved Posts',
                  subtitle: 'View your bookmarked discussions',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SavedPostsScreen(userEmail: widget.userEmail),
                      ),
                    );
                  },
                  isDark: isDark,
                ),
                _buildSettingsTile(
                  icon: _isPremium ? Icons.star_rounded : Icons.star_outline_rounded,
                  title: _isPremium ? 'Premium Membership' : 'Upgrade to Premium',
                  subtitle: _isPremium ? 'Active' : 'Unlock exclusive features',
                  iconColor: const Color(0xFFFFD700),
                  onTap: () {
                     showModalBottomSheet(
                       context: context, 
                       isScrollControlled: true,
                       backgroundColor: Colors.transparent,
                       builder: (_) => PaywallDialog(
                         onSuccess: () => _loadSettings(), // Refresh premium status
                       ),
                     );
                  },
                  isDark: isDark,
                ),
                
                const SizedBox(height: 24),
                _buildSectionHeader('App Settings', textColor),
                _buildSettingsTile(
                  icon: Icons.brightness_6,
                  customLeading: Lottie.asset(
                    'assets/animations/theme_toggle.json',
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                    animate: false, // In a real app we'd control the animation properly based on state transition
                  ),
                  title: 'Appearance',
                  subtitle: isDark ? 'Dark Mode' : 'Light Mode',
                  trailing: Builder(
                    builder: (switchContext) {
                      return Switch(
                        value: isDark,
                        activeTrackColor: AppTheme.primary,
                        onChanged: (val) {
                          final box = switchContext.findRenderObject() as RenderBox?;
                          final offset = box != null 
                              ? box.localToGlobal(box.size.center(Offset.zero)) 
                              : Offset(MediaQuery.of(context).size.width - _kSwitchFallbackOffsetRight, MediaQuery.of(context).size.height / 2);
                          
                          animateThemeTransition(context, () {
                            themeProvider.toggleTheme();
                          });
                        },
                      );
                    }
                  ),
                  isDark: isDark,
                ),
                _buildSettingsTile(
                  icon: Icons.notifications_none_rounded,
                  title: 'Notifications',
                  subtitle: 'Manage push notifications',
                  trailing: Switch(
                    value: _notificationsEnabled,
                    activeTrackColor: AppTheme.primary,
                    onChanged: _toggleNotifications,
                  ),
                   isDark: isDark,
                ),
                _buildSettingsTile(
                  icon: Icons.cleaning_services_outlined,
                  title: 'Clear Cache',
                  subtitle: 'Free up storage space',
                  onTap: _clearCache,
                  isDark: isDark,
                ),

                const SizedBox(height: 24),
                _buildSectionHeader('Legal', textColor),
                _buildSettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () => _showLegalDialog('Privacy Policy', 'This is a placeholder for the Privacy Policy.\n\nWe value your privacy...'),
                  isDark: isDark,
                ),
                _buildSettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of Service',
                  onTap: () => _showLegalDialog('Terms of Service', 'This is a placeholder for the Terms of Service.\n\nBy using this app...'),
                  isDark: isDark,
                ),

                const SizedBox(height: 24),
                _buildSectionHeader('Support', textColor),
                _buildSettingsTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Help & Support',
                  subtitle: 'FAQs and contact us',
                  onTap: () {
                     Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
                    );
                  },
                  isDark: isDark,
                ),
                _buildSettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: 'About MyStudySpace',
                  subtitle: 'Version $_appVersion',
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'MyStudySpace',
                      applicationVersion: _appVersion,
                      applicationIcon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.school, color: Colors.white),
                      ),
                      children: [
                        const Text('MyStudySpace is a college-centric educational platform.'),
                        const SizedBox(height: 10),
                        const Text('Developed by the MyStudySpace Team.'),
                      ],
                    );
                  },
                  isDark: isDark,
                ),

                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextButton(
                    onPressed: _handleLogout,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppTheme.error.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.logout_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Log Out',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                      ],
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

  Widget _buildSectionHeader(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppTheme.textMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    Widget? customLeading,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    required bool isDark,
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: customLeading ?? Icon(icon, color: iconColor ?? AppTheme.primary, size: 22),
        ),
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
            fontSize: 15,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 13,
                ),
              )
            : null,
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      ),
    );
  }
}
