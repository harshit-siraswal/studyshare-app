import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'package:animations/animations.dart';
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
import '../../services/subscription_service.dart';
import '../../widgets/success_overlay.dart';
import '../../widgets/post_notice_dialog.dart';
import '../../widgets/paywall_dialog.dart';
import '../../models/user.dart';
import '../../data/departments_data.dart';
import '../../data/academic_subjects_data.dart';
import '../study/syllabus_upload_screen.dart';

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
  final SubscriptionService _subscriptionService = SubscriptionService();
  int _currentIndex = 0;
  bool _showHelpOverlay = false;
  bool _canPostNotices = false;
  bool _roleLoading = true;
  int _noticesRefreshToken = 0;
  StreamSubscription<IncomingSharePayload>? _shareSubscription;
  bool _isHandlingIncomingShare = false;
  bool _isStudySyllabusTab = false;
  bool _canUploadSyllabusFromStudy = false;

  String get _effectiveUserEmail {
    final authEmail = (_authService.userEmail ?? '').trim();
    if (authEmail.isNotEmpty) return authEmail;
    return (_supabaseService.currentUserEmail ?? '').trim();
  }

  @override
  void initState() {
    super.initState();

    // Provide a context for reCAPTCHA flows used by SupabaseService -> BackendApiService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _supabaseService.attachContext(context);
    });
    _checkHelpOverlay();
    _loadComposerAccess();
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
    setState(() {
      _currentIndex = index;
      if (index != 0) {
        _isStudySyllabusTab = false;
      }
    });
  }

  Future<void> _loadComposerAccess() async {
    try {
      final role = await _supabaseService.getCurrentUserRole();
      if (!mounted) return;
      setState(() {
        _canPostNotices =
            role == AppRoles.teacher ||
            role == AppRoles.admin ||
            role == AppRoles.moderator;
        _roleLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to resolve composer access: $e');
      if (!mounted) return;
      setState(() {
        _canPostNotices = false;
        _roleLoading = false;
      });
    }
  }

  Future<void> _showUpload({PlatformFile? prefilledFile}) async {
    await showUploadDialog(
      context,
      widget.collegeId,
      _effectiveUserEmail,
      prefilledFile: prefilledFile,
    );
  }

  void _onStudySyllabusContextChanged(
    bool isSyllabusTab,
    bool canUploadSyllabus,
  ) {
    if (!mounted) return;
    if (_isStudySyllabusTab == isSyllabusTab &&
        _canUploadSyllabusFromStudy == canUploadSyllabus) {
      return;
    }
    setState(() {
      _isStudySyllabusTab = isSyllabusTab;
      _canUploadSyllabusFromStudy = canUploadSyllabus;
    });
  }

  Future<DepartmentData?> _showSyllabusDepartmentPicker(
    List<DepartmentData> departments,
    bool isDark,
  ) async {
    if (departments.isEmpty) return null;

    DepartmentData? profileDepartment;
    try {
      final profile = await _supabaseService.getCurrentUserProfile(
        maxAttempts: 1,
      );
      final branchCode = normalizeBranchCode(profile['branch']?.toString());
      if (branchCode.isNotEmpty) {
        for (final dept in departments) {
          if (dept.name.toLowerCase() == branchCode.toLowerCase()) {
            profileDepartment = dept;
            break;
          }
        }
      }
    } catch (_) {
      profileDepartment = null;
    }

    final sortedDepartments = List<DepartmentData>.from(departments);
    if (profileDepartment != null) {
      sortedDepartments.remove(profileDepartment);
      sortedDepartments.insert(0, profileDepartment);
    }
    if (!mounted) return null;

    final recommendedDepartmentName = profileDepartment?.name;

    return showModalBottomSheet<DepartmentData>(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Upload Syllabus',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a department to compose syllabus upload.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sortedDepartments.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final dept = sortedDepartments[i];
                  final isRecommended = recommendedDepartmentName != null &&
                      dept.name == recommendedDepartmentName;
                  return ListTile(
                    tileColor: isDark ? AppTheme.darkBackground : Colors.grey[50],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: dept.color.withValues(alpha: 0.16),
                      child: Text(
                        dept.name,
                        style: GoogleFonts.inter(
                          color: dept.color,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    title: Text(
                      dept.full,
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: isRecommended
                        ? Text(
                            'Recommended for your profile',
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 11,
                            ),
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, dept),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSyllabusUploadFlowFromFab() async {
    if (!_canUploadSyllabusFromStudy) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only admins/teachers can upload syllabus.'),
        ),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final departments = await DepartmentsProvider.getDepartments();
    if (!mounted) return;

    if (departments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No departments available right now.')),
      );
      return;
    }

    final department = await _showSyllabusDepartmentPicker(departments, isDark);
    if (!mounted || department == null) return;

    await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => SyllabusUploadScreen(
          collegeId: widget.collegeId,
          department: department.name,
          departmentName: department.full,
          departmentColor: department.color,
        ),
      ),
    );
  }

  Future<void> _initializeIncomingShareHandling() async {
    await _incomingShareService.start();
    if (!mounted) return;

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
                'Share sticker files (.webp/.png/.gif) to install them in StudyShare.',
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
    final hasStickerAccess = await _ensurePremiumStickerAccess();
    if (!hasStickerAccess) return;

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

  Future<bool> _ensurePremiumStickerAccess() async {
    final hasPremium = await _subscriptionService.isPremium();
    if (hasPremium) return true;
    if (!mounted) return false;

    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => PaywallDialog(
        onSuccess: () {
          Navigator.of(dialogContext).pop(true);
        },
      ),
    );

    if (result == true && mounted) {
      // Re-check premium status after successful purchase
      final isPremium = await _subscriptionService.isPremium();
      if (isPremium) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Premium unlocked! Sticker feature enabled.'),
          ),
        );
      }
      return isPremium;
    }

    if (!mounted) return false;
    return _subscriptionService.isPremium();
  }

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return StudyScreen(
          collegeId: widget.collegeId,
          collegeDomain: widget.collegeDomain,
          collegeName: widget.collegeName,
          userEmail: _effectiveUserEmail,
          onChangeCollege: widget.onChangeCollege,
          onSyllabusContextChanged: _onStudySyllabusContextChanged,
        );
      case 1:
        return ChatroomListScreen(
          collegeId: widget.collegeId,
          collegeDomain: widget.collegeDomain,
          userEmail: _effectiveUserEmail,
        );
      case 2:
        return NoticesScreen(
          collegeId: widget.collegeId,
          refreshToken: _noticesRefreshToken,
        );
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
          collegeId: widget.collegeId,
          collegeDomain: widget.collegeDomain,
          collegeName: widget.collegeName,
          userEmail: _effectiveUserEmail,
          onChangeCollege: widget.onChangeCollege,
          onSyllabusContextChanged: _onStudySyllabusContextChanged,
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
            child: PageTransitionSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, primaryAnimation, secondaryAnimation) {
                return SharedAxisTransition(
                  animation: primaryAnimation,
                  secondaryAnimation: secondaryAnimation,
                  transitionType: SharedAxisTransitionType.vertical,
                  fillColor: Colors.transparent,
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(_currentIndex),
                child: _getScreen(_currentIndex),
              ),
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
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Row of nav items
              Row(
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInBack,
              transitionBuilder: (child, animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: Icon(
                isActive ? activeIcon : icon,
                key: ValueKey<bool>(isActive),
                color: isActive ? activeColor : inactiveColor,
                size: 26,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedSlide(
              offset: isActive ? Offset.zero : const Offset(0, 0.2),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: isActive ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? activeColor : inactiveColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFabIcon() {
    if (_currentIndex == 0 && _isStudySyllabusTab) {
      return Icons.upload_file_rounded;
    }
    if (_currentIndex == 1) {
      return Icons.search_rounded;
    }
    return Icons.add_rounded;
  }

  Future<void> _handleFabTap() async {
    if (_roleLoading) return;
    if (_currentIndex == 0 && _isStudySyllabusTab) {
      if (_canUploadSyllabusFromStudy) {
        await _openSyllabusUploadFlowFromFab();
      }
      return;
    }
    if (_currentIndex == 2) {
      if (!_canPostNotices) {
        return;
      }
      final posted = await showPostNoticeDialog(
        context: context,
        collegeId: widget.collegeId,
      );
      if (!mounted) return;
      if (posted) {
        setState(() {
          _noticesRefreshToken++;
        });
      }
      return;
    }

    if (_currentIndex == 1) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DiscoverRoomsScreen(
            collegeId: widget.collegeId,
            collegeDomain: widget.collegeDomain,
            userEmail: _effectiveUserEmail,
          ),
        ),
      );
      return;
    }

    await _showUpload();
  }

  Widget _buildAnimatedFab(
    BuildContext context,
    bool isDark,
    double bottomPadding,
  ) {
    final isSyllabusUploadAction =
        _currentIndex == 0 && _isStudySyllabusTab && _canUploadSyllabusFromStudy;
    final isSyllabusUploadDisabled =
        _currentIndex == 0 &&
        _isStudySyllabusTab &&
        !_canUploadSyllabusFromStudy;
    final fabWidth = isSyllabusUploadAction ? 154.0 : 56.0;
    const fabHeight = 52.0;

    final gradientColors = isSyllabusUploadDisabled
        ? <Color>[
            isDark ? const Color(0xFF4B5563) : const Color(0xFF94A3B8),
            isDark ? const Color(0xFF374151) : const Color(0xFF64748B),
          ]
        : <Color>[AppTheme.primary, AppTheme.primaryDark];

    final shadowColor = (isSyllabusUploadDisabled
            ? Colors.black
            : AppTheme.primary)
        .withValues(alpha: 0.35);

    final screenWidth = MediaQuery.of(context).size.width;
    final left = (screenWidth - fabWidth) / 2;
    final bottom = bottomPadding + 26.0;

    return Positioned(
      left: left,
      bottom: bottom,
      child: IgnorePointer(
        ignoring: _roleLoading || isSyllabusUploadDisabled,
        child: Opacity(
          opacity: (_roleLoading || isSyllabusUploadDisabled) ? 0.6 : 1.0,
          child: Hero(
            tag: 'fab_main',
            child: GestureDetector(
              onTap: () async {
                HapticFeedback.mediumImpact();
                await _handleFabTap();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: fabWidth,
                height: fabHeight,
                padding: EdgeInsets.symmetric(
                  horizontal: isSyllabusUploadAction ? 10 : 0,
                ),
                decoration: BoxDecoration(
                  borderRadius:
                      isSyllabusUploadAction ? BorderRadius.circular(999) : null,
                  shape:
                      isSyllabusUploadAction ? BoxShape.rectangle : BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: isSyllabusUploadAction
                      ? Row(
                          key: const ValueKey<String>('fab_upload_syllabus'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.upload_file_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Upload Syllabus',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 11.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : Icon(
                          _getFabIcon(),
                          key: ValueKey<IconData>(_getFabIcon()),
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
