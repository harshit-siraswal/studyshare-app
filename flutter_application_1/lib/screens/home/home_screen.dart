import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../study/study_screen.dart';
import '../chatroom/chatroom_list_screen.dart';
import '../notices/notices_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/upload_resource_dialog.dart';
import '../../widgets/study_timer_widget.dart';
import '../../widgets/global_timer_overlay.dart';
import '../chatroom/discover_rooms_screen.dart';
import '../../widgets/help_overlay.dart';
import '../../providers/theme_provider.dart';
import '../../services/supabase_service.dart';
import '../../services/incoming_share_service.dart';
import '../../services/sticker_service.dart';
import '../../widgets/success_overlay.dart';

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
  final IncomingShareService _incomingShareService =
      IncomingShareService.instance;
  final StickerService _stickerService = StickerService();
  int _currentIndex = 0;
  bool _showHelpOverlay = false;
  StreamSubscription<IncomingSharePayload>? _shareSubscription;
  bool _isHandlingIncomingShare = false;

  @override
  void initState() {
    super.initState();

    // Provide a context for reCAPTCHA flows used by SupabaseService -> BackendApiService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _supabaseService.attachContext(context);
    });
    _checkHelpOverlay();
    _initializeIncomingShareHandling();
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
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

  void _handleLogout() async {
    try {
      await _authService.signOut();
      widget.onLogout();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error signing out: $e')));
      }
    }
  }

  void _onNavTapped(int index) {
    setState(() => _currentIndex = index);
  }

  Future<void> _showUpload({PlatformFile? prefilledFile}) async {
    await showUploadDialog(
      context,
      widget.collegeDomain,
      _authService.userEmail ?? '',
      prefilledFile: prefilledFile,
    );
  }

  Future<void> _initializeIncomingShareHandling() async {
    await _incomingShareService.start();

    _shareSubscription = _incomingShareService.stream.listen(
      _handleIncomingSharePayload,
    );

    final initialPayload = await _incomingShareService.consumeInitialShare();
    if (initialPayload != null) {
      await _handleIncomingSharePayload(initialPayload);
    }
  }

  Future<void> _handleIncomingSharePayload(IncomingSharePayload payload) async {
    if (!mounted || _isHandlingIncomingShare) return;
    _isHandlingIncomingShare = true;

    try {
      if (payload.isStickerPackCandidate) {
        await _installIncomingStickerPack(payload);
        return;
      }

      final resourceFile = payload.resourceFile;
      if (resourceFile != null) {
        if (_currentIndex != 0 && mounted) {
          setState(() => _currentIndex = 0);
        }

        final prefilledFile = PlatformFile(
          name: resourceFile.name,
          path: resourceFile.pathValue,
          size: resourceFile.sizeBytes,
        );

        await _showUpload(prefilledFile: prefilledFile);
        return;
      }

      final stickerFiles = payload.stickerFiles;
      if (stickerFiles.isNotEmpty) {
        await _installIncomingStickerPack(payload);
        return;
      }

      final sharedText = payload.text?.toLowerCase() ?? '';
      if (sharedText.contains('addstickers') ||
          sharedText.contains('sticker') ||
          sharedText.contains('telegram')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Share sticker files (.webp/.png/.gif) to install them in MyStudySpace.',
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Shared file type is not supported yet for auto-import.',
            ),
          ),
        );
      }
    } finally {
      _isHandlingIncomingShare = false;
    }
  }

  Future<void> _installIncomingStickerPack(IncomingSharePayload payload) async {
    final paths = payload.stickerFiles.map((file) => file.pathValue).toList();
    if (paths.isEmpty) return;

    final importResult = await _stickerService.importPackFromPaths(
      paths: paths,
      packName: 'Shared Sticker Pack',
    );
    if (!mounted) return;

    if (importResult.importedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid stickers found in shared files.'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => SuccessOverlay(
        variant: SuccessOverlayVariant.stickerImport,
        title: 'Sticker Pack Installed',
        message:
            '${importResult.importedCount} stickers were added to your library.',
        badgeLabel: importResult.skippedCount > 0
            ? '${importResult.skippedCount} skipped'
            : null,
        onDismiss: () => Navigator.pop(dialogContext),
      ),
    );
  }

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return StudyScreen(
          collegeId: widget.collegeDomain,
          collegeName: widget.collegeName,
          userEmail: _authService.userEmail ?? '',
          onChangeCollege: widget.onChangeCollege,
        );
      case 1:
        return ChatroomListScreen(
          collegeId: widget.collegeDomain,
          collegeDomain: widget.collegeDomain,
          userEmail: _authService.userEmail ?? '',
        );
      case 2:
        return NoticesScreen(collegeId: widget.collegeDomain);
      case 3:
        return ProfileScreen(
          collegeName: widget.collegeName,
          collegeDomain: widget.collegeDomain,
          onLogout: _handleLogout,
          onChangeCollege: widget.onChangeCollege,
          themeProvider: widget.themeProvider,
        );
      default:
        return StudyScreen(
          collegeId: widget.collegeDomain,
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

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      resizeToAvoidBottomInset:
          false, // Prevent floating nav from rising with keyboard
      extendBody: true,
      extendBodyBehindAppBar: true,
      // Drawer with timer - when closed, triggers wind swirl animation
      onDrawerChanged: (isOpen) {
        // Inform overlay about sidebar state to manage bubble visibility
        GlobalTimerOverlay.setSidebarOpen(isOpen);

        if (!isOpen && GlobalTimerOverlay.timerController?.isRunning == true) {
          // Drawer closed with timer running - trigger swirl animation
          // Start position is center-left of screen (where drawer edge is)
          final screenSize = MediaQuery.of(context).size;
          GlobalTimerOverlay.triggerSwirl(Offset(0, screenSize.height / 2));
        }
      },
      drawer: Drawer(
        width: 280,
        child: GlobalTimerOverlay.timerController != null
            ? StudyTimerWidget(
                controller: GlobalTimerOverlay.timerController!,
                onMinimize: () {
                  Navigator.pop(
                    context,
                  ); // Close drawer - this triggers onDrawerChanged
                },
              )
            : const Center(child: CircularProgressIndicator()),
      ),
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.1,
      body: Stack(
        children: [
          // Main content - padding adjusted to match floating nav height (72) + spacing (16) + system padding
          SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _getScreen(_currentIndex),
            ),
          ),

          // Timer is handled globally by GlobalTimerOverlay in main.dart

          // Help Overlay (shows on first launch)
          if (_showHelpOverlay) HelpOverlay(onDismiss: _dismissHelpOverlay),

          // Floating Bottom Navigation Bar
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPadding + 16,
            child: _buildFloatingBottomNav(isDark),
          ),

          // Animated FAB
          _buildAnimatedFab(context, isDark, bottomPadding),
        ],
      ),
    );
  }

  // Floating Bottom Navigation Bar with Frosted Glass Effect
  Widget _buildFloatingBottomNav(bool isDark) {
    // Colors for frosted glass effect

    return ClipRRect(
      borderRadius: BorderRadius.circular(36),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25), // Stronger blur
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.6), // More transparent
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(
                      alpha: 0.4,
                    ), // Distinct subtle border
              width: 1.5, // Slightly thicker for the "glass edge" look
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: isDark ? 0.5 : 0.2,
                ), // Deeper shadow for pop
                blurRadius: 32, // Softer, larger shadow
                offset: const Offset(0, 10),
                spreadRadius: -4,
              ),
              // Inner light reflection simulation (top highlight)
              if (isDark)
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.1),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                  spreadRadius: 0,
                  blurStyle: BlurStyle
                      .inner, // Inset feel if supported, otherwise just a top border effect via border
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
                    _buildNavItem(
                      0,
                      Icons.home_outlined,
                      Icons.home_rounded,
                      'Home',
                    ),
                    _buildNavItem(
                      1,
                      Icons.chat_bubble_outline_rounded,
                      Icons.chat_bubble_rounded,
                      'Chats',
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 56),

              // Right side - 2 tabs
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(
                      2,
                      Icons.campaign_outlined,
                      Icons.campaign_rounded,
                      'Notices',
                    ),
                    _buildNavItem(
                      3,
                      Icons.person_outline_rounded,
                      Icons.person_rounded,
                      'Profile',
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

  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
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
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                fontSize: 10, // Reduced font size
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? activeColor : inactiveColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedFab(
    BuildContext context,
    bool isDark,
    double bottomPadding,
  ) {
    // Show on all tabs
    // 0: Resources, 1: Rooms, 2: Notices, 3: Profile

    // Position Calculations (Centered by default per user request "remain at bottom bar")
    // Show on all tabs
    // 0: Resources, 1: Rooms, 2: Notices, 3: Profile

    // FAB is center-docked on all tabs; repositions to bottom-right only within individual room screens

    final screenWidth = MediaQuery.of(context).size.width;
    final double left =
        (screenWidth - 56) / 2; // Center horizontally (56 = FAB width)
    final double bottom = bottomPadding + 16 + 8; // Above the floating nav bar

    return Positioned(
      left: left,
      bottom: bottom,
      child: Hero(
        tag: 'fab_main', // Static tag
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            // Handle actions based on index
            if (_currentIndex == 0) {
              // Resources: Upload
              _showUpload();
            } else if (_currentIndex == 1) {
              // Rooms: Create/Discover
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DiscoverRoomsScreen(
                    collegeId: widget.collegeDomain,
                    collegeDomain: widget.collegeDomain,
                    userEmail: _authService.userEmail ?? '',
                  ),
                ),
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
                  color: AppTheme.primary.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
