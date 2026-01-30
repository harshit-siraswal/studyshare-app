import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../study/study_screen.dart';
import '../chatroom/chatroom_list_screen.dart';
import '../chatroom/discover_rooms_screen.dart';
import '../notices/notices_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/upload_resource_dialog.dart';
import '../../widgets/study_timer_widget.dart';
import '../../widgets/help_overlay.dart';
import '../../providers/theme_provider.dart';
import '../../services/supabase_service.dart';

class HomeScreen extends StatefulWidget {
  final String collegeId;
  final String collegeName;
  final String collegeDomain;
  final VoidCallback onLogout;
  final VoidCallback onChangeCollege;
  final ThemeProvider themeProvider;

  const HomeScreen({
    super.key,
    required this.collegeId,
    required this.collegeName,
    required this.collegeDomain,
    required this.onLogout,
    required this.onChangeCollege,
    required this.themeProvider,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  int _currentIndex = 0;
  bool _showTimer = false;
  bool _showHelpOverlay = false;
  
  late AnimationController _timerAnimController;

  @override
  void initState() {
    super.initState();
    _timerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200), // Faster animation
    );
    // Provide a context for reCAPTCHA flows used by SupabaseService -> BackendApiService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _supabaseService.attachContext(context);
    });
    _checkHelpOverlay();
  }

  Future<void> _checkHelpOverlay() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenHelp = prefs.getBool('hasSeenHomeHelp') ?? false;
    if (!hasSeenHelp) {
      // Small delay to let the screen render first
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() => _showHelpOverlay = true);
      }
    }
  }

  void _dismissHelpOverlay() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenHomeHelp', true);
    if (mounted) {
      setState(() => _showHelpOverlay = false);
    }
  }

  @override
  void dispose() {
    _timerAnimController.dispose();
    super.dispose();
  }

  void _handleLogout() async {
    try {
      await _authService.signOut();
      widget.onLogout();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  void _onNavTapped(int index) {
    setState(() => _currentIndex = index);
  }

  void _showUpload() {
    showUploadDialog(
      context,
      widget.collegeId,
      _authService.userEmail ?? '',
    );
  }

  void _toggleTimer() {
    setState(() => _showTimer = !_showTimer);
    if (_showTimer) {
      _timerAnimController.forward();
    } else {
      _timerAnimController.reverse();
    }
  }

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return StudyScreen(
          collegeId: widget.collegeId,
          collegeName: widget.collegeName,
          userEmail: _authService.userEmail ?? '',
          onChangeCollege: widget.onChangeCollege,
        );
      case 1:
        return ChatroomListScreen(
          collegeId: widget.collegeId,
          collegeDomain: widget.collegeDomain,
          userEmail: _authService.userEmail ?? '',
        );
      case 2:
        return NoticesScreen(collegeId: widget.collegeId);
      case 3:
        return ProfileScreen(
          collegeId: widget.collegeId,
          collegeName: widget.collegeName,
          collegeDomain: widget.collegeDomain,
          onLogout: _handleLogout,
          onChangeCollege: widget.onChangeCollege,
          themeProvider: widget.themeProvider,
        );
      default:
        return StudyScreen(
          collegeId: widget.collegeId,
          collegeName: widget.collegeName,
          userEmail: _authService.userEmail ?? '',
          onChangeCollege: widget.onChangeCollege,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // FAB Logic removed as per new requirements

    
    final email = _authService.userEmail;
    final isAllowed = email != null && widget.collegeDomain.isNotEmpty && email.endsWith(widget.collegeDomain);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Main content with swipe gesture to open timer - extends full screen
          SafeArea(
            bottom: false,
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                // Swipe right to open timer (if closed)
                if (!_showTimer && details.primaryVelocity != null && details.primaryVelocity! > 200) {
                  _toggleTimer();
                }
              },
              child: Padding(
                // Add bottom padding to prevent content from being hidden under floating nav
                padding: EdgeInsets.only(bottom: 90 + bottomPadding),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _getScreen(_currentIndex),
                ),
              ),
            ),
          ),
          // Study Timer Panel (swipe-only; no fixed button)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: _showTimer ? 0 : -300,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  // Swipe left to close timer (if open)
                  if (_showTimer && details.primaryVelocity != null && details.primaryVelocity! < -200) {
                    _toggleTimer();
                  }
                },
                child: const StudyTimerWidget(),
              ),
            ),
          ),
          // Dimmed overlay when timer is open
          if (_showTimer)
            Positioned.fill(
              left: 280,
              child: GestureDetector(
                onTap: _toggleTimer,
                child: Container(color: Colors.black.withOpacity(0.3)),
              ),
            ),
          // Help Overlay (shows on first launch)
          if (_showHelpOverlay)
            HelpOverlay(onDismiss: _dismissHelpOverlay),
          
          // Floating Bottom Navigation Bar
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPadding + 16,
            child: _buildFloatingBottomNav(isDark),
          ),
          

        ],
      ),
    );
  }

  // Floating Bottom Navigation Bar with Frosted Glass Effect
  Widget _buildFloatingBottomNav(bool isDark) {
    // Colors for frosted glass effect
    final glassBg = isDark 
        ? Colors.black.withOpacity(0.6)
        : Colors.white.withOpacity(0.75);
    final borderColor = isDark 
        ? Colors.white.withOpacity(0.1)
        : Colors.black.withOpacity(0.05);
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: glassBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // Left side - 2 tabs
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
                    _buildNavItem(1, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chats'),
                  ],
                ),
              ),
              
              // Center FAB (integrated into the floating bar)
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  final email = _authService.userEmail;
                  final isAllowed = email != null && widget.collegeDomain.isNotEmpty && email.endsWith(widget.collegeDomain);
                  
                  if (isAllowed) {
                    _showUpload();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Upload is restricted to verified students.')),
                    );
                  }
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.primary, AppTheme.primaryDark],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ), 
              
              // Right side - 2 tabs
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(2, Icons.campaign_outlined, Icons.campaign_rounded, 'Notices'),
                    _buildNavItem(3, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isActive = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Active color: Primary red/brand color. Inactive: Grey.
    final activeColor = AppTheme.primary;
    final inactiveColor = isDark ? Colors.grey[400] : Colors.grey[600];
    
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        _onNavTapped(index);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? activeColor : inactiveColor,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
