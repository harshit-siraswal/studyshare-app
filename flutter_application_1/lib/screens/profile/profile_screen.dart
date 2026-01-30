import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../services/backend_api_service.dart';
import '../../providers/theme_provider.dart';
import '../study/bookmarks_screen.dart';
import 'following_screen.dart';
import 'help_support_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String collegeId;
  final String collegeName;
  final String collegeDomain;
  final VoidCallback onLogout;
  final VoidCallback onChangeCollege;
  final ThemeProvider themeProvider;

  const ProfileScreen({
    super.key,
    required this.collegeId,
    required this.collegeName,
    required this.collegeDomain,
    required this.onLogout,
    required this.onChangeCollege,
    required this.themeProvider,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  final BackendApiService _api = BackendApiService();
  late AnimationController _controller;

  bool _isLoggingOut = false;
  bool _profileLoading = true;
  String? _profilePhotoUrl;
  String? _profileDisplayName;
  String? _profileBio;
  
  // Real stats
  int _uploadCount = 0;
  int _bookmarkCount = 0;
  int _followingCount = 0;
  int _followersCount = 0;
  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500)
    );
    
    _loadStats();
    _loadProfile();
    _controller.forward();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _api.getProfile();
      final profile = (data['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      if (!mounted) return;
      setState(() {
        _profileDisplayName = profile['display_name']?.toString();
        _profilePhotoUrl = profile['profile_photo_url']?.toString();
        _profileBio = profile['bio']?.toString();
        _profileLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _loadStats() async {
    if (_authService.userEmail == null) return;
    try {
      final stats = await _supabaseService.getUserStats(_authService.userEmail!);
      final followingCount = await _supabaseService.getFollowingCount(_authService.userEmail!);
      final followersCount = await _supabaseService.getFollowersCount(_authService.userEmail!);
      if (mounted) {
        setState(() {
          _uploadCount = stats['uploads'] ?? 0;
          _bookmarkCount = stats['bookmarks'] ?? 0;
          _followingCount = followingCount;
          _followersCount = followersCount;
          _statsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  String get _userEmail => _authService.userEmail ?? 'guest@example.com';
  String get _displayName => _profileDisplayName ?? _authService.displayName ?? 'User';
  String? get _photoUrl => _profilePhotoUrl ?? _authService.photoUrl;
  
  String get _role {
    final email = _userEmail;
    if (email.endsWith(widget.collegeDomain)) {
      return 'VERIFIED STUDENT';
    }
    return 'READ ONLY';
  }
  
  bool get _isVerified => _role == 'VERIFIED STUDENT';

  Future<void> _handleLogout() async {
    setState(() => _isLoggingOut = true);
    
    try {
      await _authService.signOut();
      if (mounted) {
        widget.onLogout();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoggingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sign out: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
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
                  color: AppTheme.error.withOpacity(0.2),
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
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: AppTheme.textMuted),
              ),
            ),
            ElevatedButton(
              onPressed: _isLoggingOut ? null : () {
                Navigator.pop(context);
                _handleLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
              ),
              child: _isLoggingOut 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = true; // Force dark mode for Cyberpunk look
    
    return Scaffold(
      backgroundColor: const Color(0xFF050510), // Deep space black
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAnimatedItem(0, _buildHeaderRow(isDark)),
              const SizedBox(height: 40),
              
              // 1. Future/Cyberpunk Avatar Section
              _buildAnimatedItem(1, Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Glow
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                           BoxShadow(color: const Color(0xFF00F0FF).withOpacity(0.4), blurRadius: 40, spreadRadius: -10),
                           BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.4), blurRadius: 40, spreadRadius: -10, offset: const Offset(10, 10)),
                        ],
                      ),
                    ),
                    // Rotating Ring (Animated Builder)
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _controller.value * 2 * 3.14159,
                          child: SizedBox(
                            width: 128,
                            height: 128,
                            child: CircularProgressIndicator(
                              value: 0.75,
                              strokeWidth: 4,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF00F0FF)), // Cyan Neon
                            ),
                          ),
                        );
                      },
                    ),
                    // Avatar Image
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        image: _photoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(_photoUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                        color: Colors.black,
                      ),
                      child: _photoUrl == null
                          ? Center(
                              child: Text(
                                _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U',
                                style: GoogleFonts.orbitron(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            )
                          : null,
                    ),
                    // Level Badge
                    Positioned(
                      bottom: 0,
                      child: Container(
                         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                         decoration: BoxDecoration(
                           gradient: const LinearGradient(colors: [Color(0xFF00F0FF), Color(0xFF00A3FF)]),
                           borderRadius: BorderRadius.circular(20),
                           boxShadow: [
                             BoxShadow(color: const Color(0xFF00F0FF).withOpacity(0.5), blurRadius: 10),
                           ],
                         ),
                         child: Text('LVL 12', style: GoogleFonts.orbitron(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                      ),
                    ),
                  ],
                ),
              )),
              
              const SizedBox(height: 24),
              
              // Name & Cyber Tag
              _buildAnimatedItem(2, Center(
                child: Column(
                  children: [
                    Text(
                      _displayName,
                      style: GoogleFonts.orbitron(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [Shadow(color: const Color(0xFF00F0FF).withOpacity(0.6), blurRadius: 15)],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFF7C3AED).withOpacity(0.1),
                      ),
                      child: Text(
                        'NETRUNNER', 
                        style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF7C3AED), letterSpacing: 2),
                      ),
                    ),
                  ],
                ),
              )),
              
              const SizedBox(height: 40),
              
              // 2. Neon Stats Grid
              _buildAnimatedItem(3, _buildNeonStatsGrid()),
              
              const SizedBox(height: 30),
              
              // 3. Holographic Menu
              _buildAnimatedItem(4, _buildHoloMenu()),
              
              const SizedBox(height: 40),
              // Sign out
              _buildAnimatedItem(5, Center(
                child: TextButton.icon(
                  onPressed: _isLoggingOut ? null : _showLogoutDialog,
                  icon: Icon(Icons.logout, color: AppTheme.error.withOpacity(0.8), size: 20),
                  label: Text(
                    'Sign Out',
                    style: GoogleFonts.inter(
                      color: AppTheme.error.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(bool isDark) {
    return Row(
      children: [
        Text(
          'Profile',
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: () {
             // Settings placeholder or nav
          },
          icon: Icon(Icons.settings_outlined, color: isDark ? Colors.white70 : Colors.black54),
        ),
        IconButton(
          onPressed: () async {
            if (_profileLoading) return;
            final updated = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditProfileScreen(
                  initialName: _displayName,
                  initialPhotoUrl: _photoUrl,
                  initialBio: _profileBio,
                ),
              ),
            );
            if (updated != null && mounted) {
              await _loadProfile();
            }
          },
          icon: Icon(Icons.edit_outlined, color: isDark ? Colors.white70 : Colors.black54),
        ),
      ],
    );
  }

  Widget _buildNeonStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildNeonStatCard('UPLOADS', _uploadCount.toString(), Icons.cloud_upload_outlined, const Color(0xFF00F0FF)),
        _buildNeonStatCard('BOOKMARKS', _bookmarkCount.toString(), Icons.bookmark_outline, const Color(0xFFFF00FF)),
        _buildNeonStatCard('FOLLOWERS', _followersCount.toString(), Icons.people_outline, const Color(0xFF00FF99)),
        _buildNeonStatCard('REPUTATION', '95%', Icons.star_outline, const Color(0xFFFFD700)),
      ],
    );
  }

  Widget _buildNeonStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, spreadRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.orbitron(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 10, color: Colors.white54, letterSpacing: 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHoloMenu() {
    return Column(
      children: [
        _buildHoloMenuItem('My Profile details', Icons.person_outline),
        const SizedBox(height: 12),
        _buildHoloMenuItem('Payment Methods', Icons.credit_card),
        const SizedBox(height: 12),
        _buildHoloMenuItem('Notification Settings', Icons.notifications_none),
         const SizedBox(height: 12),
        _buildHoloMenuItem('Log Out', Icons.logout, isDestructive: true),
      ],
    );
  }

  Widget _buildHoloMenuItem(String title, IconData icon, {bool isDestructive = false}) {
    return Container(
       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
       decoration: BoxDecoration(
         color: Colors.white.withOpacity(0.03),
         borderRadius: BorderRadius.circular(12),
         border: Border(left: BorderSide(color: isDestructive ? Colors.red : Colors.white24, width: 2)),
       ),
       child: Row(
         children: [
           Icon(icon, color: isDestructive ? Colors.red : Colors.white70, size: 20),
           const SizedBox(width: 16),
           Text(
             title,
             style: GoogleFonts.inter(
               color: isDestructive ? Colors.red : Colors.white,
               fontSize: 14,
               fontWeight: FontWeight.w500
             ),
           ),
           const Spacer(),
           Icon(Icons.chevron_right, color: Colors.white24, size: 18),
         ],
       ),
    );
  }

  Widget _buildAnimatedItem(int index, Widget child) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.2),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Interval(index * 0.1, 1.0, curve: Curves.easeOutCubic),
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _controller,
          curve: Interval(index * 0.1, 1.0, curve: Curves.easeOut),
        ),
        child: child,
      ),
    );
  }
}
