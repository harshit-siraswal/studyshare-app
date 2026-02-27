import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:lottie/lottie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:badges/badges.dart' as badges;
import 'package:flutter_app_badger/flutter_app_badger.dart';
import '../../config/theme.dart';
import '../../models/resource.dart';
import '../../services/supabase_service.dart';
import '../../services/download_service.dart';
import '../../widgets/resource_card.dart';
import '../notifications/notification_screen.dart';
import '../profile/bookmarks_screen.dart';
import '../ai_chat_screen.dart';
import '../../services/backend_api_service.dart';
import '../../services/auth_service.dart';
import '../profile/explore_students_screen.dart';
import 'syllabus_screen.dart';
import 'resource_search_screen.dart';
import '../../services/home_widget_service.dart';

import '../../data/departments_data.dart'; // Added for DepartmentData and DepartmentsProvider

class StudyScreen extends StatefulWidget {
  final String collegeId;
  final String collegeDomain;
  final String collegeName;
  final String userEmail;
  final VoidCallback? onChangeCollege;

  const StudyScreen({
    super.key,
    required this.collegeId,
    required this.collegeDomain,
    required this.collegeName,
    required this.userEmail,
    this.onChangeCollege,
  });

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final BackendApiService _apiService = BackendApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  // Tab state

  // For You resources
  List<Resource> _resources = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  late Future<List<DepartmentData>> _departmentsFuture;

  // Following resources
  List<Resource> _followingResources = [];
  bool _isLoadingFollowing = true;
  bool _isModerating = false;

  // User Profile Data
  String _userRole = 'READ_ONLY';
  String _userSemester = '1';
  String _userBranch = 'CSE';
  String? _userAdminKey;

  // Downloaded resources
  List<Resource> _downloadedResources = [];

  // Filters
  String? _selectedSemester;
  String? _selectedBranch;
  String? _selectedSubject;
  String? _selectedType;
  String _selectedSort = 'Recent';

  // Filter options
  List<String> _semesters = [];
  List<String> _branches = [];
  List<String> _subjects = [];
  final List<String> _types = ['All', 'Notes', 'PYQ', 'Videos', 'Downloads'];
  final List<String> _sortOptions = ['Recent', 'Most upvotes', 'Teacher'];

  int _unreadNotificationCount = 0;

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final notifications = await _apiService.getNotifications(limit: 50);
      int unread = 0;
      for (var n in notifications) {
        if (n['is_read'] != true && n['isRead'] != true) {
          unread++;
        }
      }
      if (mounted) {
        setState(() {
          _unreadNotificationCount = unread;
        });
      }
      
      // Update OS level app badge
      final isSupported = await FlutterAppBadger.isAppBadgeSupported();
      if (!mounted) return;
      if (isSupported) {
        if (unread > 0) {
          FlutterAppBadger.updateBadgeCount(unread);
        } else {
          FlutterAppBadger.removeBadge();
        }
      }
    } catch (e) {
      debugPrint('Error loading unread notification count: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
    ); // 3 tabs: For You, Following, Syllabus
    _loadFilters();
    _departmentsFuture = DepartmentsProvider.getDepartments();
    _scrollController.addListener(_onScroll);
    
    _loadUserProfile().then((_) {
      _loadResources();
      _loadFollowingFeed();
      _loadUnreadNotificationCount();
    });
  }

  Future<void> _loadUserProfile() async {
    try {
      final data = await _apiService.getProfile();
      final profile = (data['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      if (mounted) {
        setState(() {
          _userRole = profile['role']?.toString() ?? 'READ_ONLY';
          _userSemester = profile['semester']?.toString() ?? '1';
          _userBranch = profile['branch']?.toString() ?? 'CSE';
          _userAdminKey = profile['admin_key']?.toString();
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile in StudyScreen: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadFollowingFeed() async {
    try {
      if (_userRole == 'TEACHER') {
        final resources = await _supabaseService.getPendingResourcesForTeacher(
          collegeId: widget.collegeId,
          branch: _userBranch, 
        );
        setState(() {
          _followingResources = resources;
          _isLoadingFollowing = false;
        });
      } else {
        final resources = await _supabaseService.getFollowingFeed(
          userEmail: widget.userEmail,
          collegeId: widget.collegeId,
        );
        setState(() {
          _followingResources = resources;
          _isLoadingFollowing = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingFollowing = false);
    }
  }

  Future<void> _loadFilters() async {
    final semesters = await _supabaseService.getUniqueValues(
      'semester',
      widget.collegeId,
    );
    final branches = await _supabaseService.getUniqueValues(
      'branch',
      widget.collegeId,
    );

    setState(() {
      _semesters = ['All', ...semesters];
      _branches = ['All', ...branches];
    });
  }

  Future<void> _loadSubjects() async {
    if (_selectedBranch != null && _selectedBranch != 'All') {
      final subjects = await _supabaseService.getUniqueValues(
        'subject',
        widget.collegeId,
        branch: _selectedBranch,
      );
      setState(() {
        _subjects = ['All', ...subjects];
      });
    } else {
      setState(() => _subjects = []);
    }
  }

  Future<void> _loadResources({bool refresh = false}) async {
    if (refresh) {
      _loadUnreadNotificationCount();
      setState(() {
        _resources = [];
        _isLoading = true;
      });
    }

    // Handle Downloads Filter
    if (_selectedType == 'Downloads') {
      setState(() {
        _resources = DownloadService().getAllDownloadedResources();
        _isLoading = false;
      });
      return;
    }

    try {
      final resources = await _supabaseService.getResources(
        collegeId: widget.collegeId,
        semester: _selectedSemester != 'All' ? _selectedSemester : null,
        branch: _selectedBranch != 'All' ? _selectedBranch : null,
        subject: _selectedSubject != 'All' ? _selectedSubject : null,
        type: _mapResourceType(_selectedType),
        searchQuery: _searchController.text.isNotEmpty
            ? _searchController.text
            : null,
        sortBy: _mapSortOption(_selectedSort),
        offset: 0,
      );

      if (!mounted) return;

      setState(() {
        _resources = resources;
        _isLoading = false;
      });
      
      // Update Home Widget by filtering syllabus resources
      if (_selectedType == null) {
        final syllabusResources = resources.where((r) => r.type.toLowerCase() == 'syllabus').toList();
        HomeWidgetService.instance.syncSyllabus(
          _userSemester, 
          _userBranch, 
          syllabusResources,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreResources();
    }
  }

  Future<void> _loadMoreResources() async {
    if (_isLoadingMore || _isLoading) return;

    // Downloads are local only - no pagination needed
    if (_selectedType == 'Downloads') return;

    setState(() => _isLoadingMore = true);

    try {
      final moreResources = await _supabaseService.getResources(
        collegeId: widget.collegeId,
        semester: _selectedSemester != 'All' ? _selectedSemester : null,
        branch: _selectedBranch != 'All' ? _selectedBranch : null,
        subject: _selectedSubject != 'All' ? _selectedSubject : null,
        type: _mapResourceType(_selectedType),
        searchQuery: _searchController.text.isNotEmpty
            ? _searchController.text
            : null,
        sortBy: _mapSortOption(_selectedSort),
        offset: _resources.length,
      );

      if (!mounted) return;

      setState(() {
        _resources.addAll(moreResources);
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  // Unused method removed

  @override
  Widget build(BuildContext context) {
    final isTeacher = _userRole == 'TEACHER';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // Header
              _buildHeader(),

              // Tab Bar for For You / Following
              _buildTabBar(isDark),

              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // For You Tab
                    Column(
                      children: [
                        _buildSearchBar(),
                        Expanded(
                          child: CustomRefreshIndicator(
                            onRefresh: () => _loadResources(refresh: true),
                            builder: (context, child, controller) {
                              return Stack(
                                children: [
                                  if (controller.value > 0.0)
                                    Positioned(
                                      top: 25 * controller.value,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: SizedBox(
                                          height: 80,
                                          width: 80,
                                          child: Opacity(
                                            opacity: controller.value.clamp(0.0, 1.0),
                                            child: Lottie.asset(
                                              'assets/lottie/refresh.json',
                                              animate: controller.isLoading,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Transform.translate(
                                    offset: Offset(0, 100 * controller.value),
                                    child: child,
                                  ),
                                ],
                              );
                            },
                            child: _isLoading
                                ? _buildLoadingSkeleton()
                                : _resources.isEmpty
                                ? _buildEmptyState()
                                : _buildResourcesGrid(),
                          ),
                        ),
                      ],
                    ),

                    // Following / Moderation Tab
                    CustomRefreshIndicator(
                      onRefresh: _loadFollowingFeed,
                      builder: (context, child, controller) {
                        return Stack(
                          children: [
                            if (controller.value > 0.0)
                              Positioned(
                                top: 25 * controller.value,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: SizedBox(
                                    height: 80,
                                    width: 80,
                                    child: Opacity(
                                      opacity: controller.value.clamp(0.0, 1.0),
                                      child: Lottie.asset(
                                        'assets/lottie/refresh.json',
                                        animate: controller.isLoading,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Transform.translate(
                              offset: Offset(0, 100 * controller.value),
                              child: child,
                            ),
                          ],
                        );
                      },
                      child: _isLoadingFollowing
                          ? _buildLoadingSkeleton()
                          : _followingResources.isEmpty
                          ? (isTeacher ? _buildModerationEmptyState() : _buildFollowingEmptyState())
                          : _buildFollowingGrid(),
                    ),
                    // Syllabus Tab
                    _buildSyllabusTab(isDark),
                  ],
                ),
              ),
            ],
          ), // Column
        ), // Padding
      ), // SafeArea
    ); // Scaffold
  }

  Widget _buildTabBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: AppTheme.primary,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.textMuted,
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        padding: const EdgeInsets.all(4),
        tabs: [
          const Tab(text: 'For You'),
          Tab(text: _userRole == 'TEACHER' ? 'Moderation' : 'Following'),
          const Tab(text: 'Syllabus'),
        ],
      ),
    );
  }

  void _navigateToExploreStudents(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExploreStudentsScreen(
          collegeDomain: widget.collegeDomain,
          userEmail: widget.userEmail,
        ),
      ),
    );
  }

  Widget _buildModerationEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.task_alt_rounded,
            size: 64,
            color: AppTheme.success.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'All caught up!',
            style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            'No pending resources to moderate for your branch.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowingEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 64,
            color: AppTheme.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No resources from people you follow',
            style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            'Follow students to see their uploads here',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textMuted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _navigateToExploreStudents(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Find Students'),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowingGrid() {
    final isTeacher = _userRole == 'TEACHER';

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        100,
      ), // Bottom padding for floating nav
      itemCount: _followingResources.length,
      itemBuilder: (context, index) {
        final resource = _followingResources[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ResourceCard(
            resource: resource,
            userEmail: widget.userEmail,
            showModerationControls: isTeacher,
            onApprove: isTeacher ? () => _moderateResource(resource.id, 'approved') : null,
            onReject: isTeacher ? () => _moderateResource(resource.id, 'rejected') : null,
          ),
        );
      },
    );
  }

  Future<void> _moderateResource(String resourceId, String newStatus) async {
    if (_isModerating) return;
    if (_userAdminKey == null || _userAdminKey!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing Admin Key. Update your profile.')),
      );
      return;
    }

    setState(() => _isModerating = true);

    try {
      await _apiService.updateResourceStatus(
        resourceId: resourceId,
        status: newStatus,
        adminKey: _userAdminKey!,
        context: context,
      );

      if (!mounted) return;
      // Remove from list or refresh
      setState(() {
        _followingResources.removeWhere((r) => r.id == resourceId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resource $newStatus successfully')),
      );
    } catch (e) {
      debugPrint('Error moderating resource: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to moderate resource. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isModerating = false);
    }
  }

  ({Color textColor, Color secondaryColor, Color cardColor, Color borderColor})
  _getThemeColors(bool isDark) {
    return (
      textColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
      secondaryColor: isDark
          ? AppTheme.darkTextSecondary
          : AppTheme.lightTextSecondary,
      cardColor: isDark ? AppTheme.darkCard : Colors.white,
      borderColor: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
    );
  }

  Widget _buildSyllabusTab(bool isDark) {
    final (:textColor, :secondaryColor, :cardColor, :borderColor) =
        _getThemeColors(isDark);

    // Use DepartmentsProvider
    return FutureBuilder<List<DepartmentData>>(
      future: _departmentsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Failed to load departments',
                  style: GoogleFonts.inter(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() {
                    _departmentsFuture = DepartmentsProvider.getDepartments();
                  }),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final departments = snapshot.data!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Department',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'View syllabus by department',
                style: GoogleFonts.inter(fontSize: 13, color: secondaryColor),
              ),
              const SizedBox(height: 20),

              // Department Grid
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                ),
                children: [
                  ...departments.map((dept) {
                    return _buildDepartmentCard(dept, isDark: isDark);
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final collegeName = widget.collegeName.trim();
    final useCompactText = collegeName.length > 24;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          // College badge - Wrapped in Flexible to prevent overflow
          Flexible(
            child: InkWell(
              onTap: widget.onChangeCollege,
              borderRadius: BorderRadius.circular(20),
              child: Container(
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.school_rounded,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        collegeName.isEmpty ? 'My College' : collegeName,
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: useCompactText ? 12 : 13,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                    if (widget.onChangeCollege != null) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 16,
                        color: AppTheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),

          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AIChatScreen(
                    collegeId: widget.collegeId,
                    collegeName: widget.collegeName,
                  ),
                ),
              );
            },
            icon: Icon(
              Icons.auto_awesome,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),

          // Bookmarks button
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BookmarksScreen(),
                ),
              );
            },
            icon: Icon(
              Icons.bookmark_outline_rounded,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          // Notification bell
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationScreen(),
                ),
              ).then((_) => _loadUnreadNotificationCount());
            },
            icon: badges.Badge(
              showBadge: _unreadNotificationCount > 0,
              badgeContent: Text(
                _unreadNotificationCount > 9 ? '9+' : _unreadNotificationCount.toString(),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              badgeStyle: badges.BadgeStyle(
                badgeColor: const Color(0xFFEF4444),
                padding: const EdgeInsets.all(4),
              ),
              child: Icon(
                Icons.notifications_outlined,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentCard(DepartmentData dept, {required bool isDark}) {
    final (:textColor, :secondaryColor, :cardColor, :borderColor) =
        _getThemeColors(isDark);

    return _DepartmentCard3D(
      dept: dept,
      collegeId: widget.collegeId,
      textColor: textColor,
      secondaryColor: secondaryColor,
      cardColor: cardColor,
      borderColor: borderColor,
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hasActiveFilters =
        (_selectedSemester != null && _selectedSemester != 'All') ||
        (_selectedBranch != null && _selectedBranch != 'All') ||
        (_selectedSubject != null && _selectedSubject != 'All') ||
        (_selectedType != null && _selectedType != 'All') ||
        _selectedSort != 'Recent';
    final activeFilterCount = [
      _selectedSemester != null && _selectedSemester != 'All',
      _selectedBranch != null && _selectedBranch != 'All',
      _selectedSubject != null && _selectedSubject != 'All',
      _selectedType != null && _selectedType != 'All',
      _selectedSort != 'Recent',
    ].where((v) => v).length;

    final searchBarColor = isDark ? Colors.black : const Color(0xFFF4F6FB);
    final borderColor = hasActiveFilters
        ? AppTheme.primary.withValues(alpha: 0.55)
        : (isDark ? Colors.white24 : const Color(0xFFE1E7F0));
    final dividerColor = isDark ? Colors.white10 : Colors.black12;
    final filterBackground = hasActiveFilters
        ? AppTheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)
        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06));
    final filterTextColor = hasActiveFilters
        ? AppTheme.primary
        : (isDark ? Colors.white70 : const Color(0xFF111827));

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                ResourceSearchScreen(
                  collegeId: widget.collegeId,
                  userEmail: widget.userEmail,
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  const begin = Offset(0.0, 0.05);
                  const end = Offset.zero;
                  const curve = Curves.easeOutCubic;
                  var tween = Tween(
                    begin: begin,
                    end: end,
                  ).chain(CurveTween(curve: curve));
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: animation.drive(tween),
                      child: child,
                    ),
                  );
                },
            transitionDuration: const Duration(milliseconds: 200),
          ),
        );
      },
      child: Container(
        height: 60,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: searchBarColor,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: borderColor,
            width: hasActiveFilters ? 1.2 : 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFDCE3EE),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.search_rounded,
                color: isDark ? Colors.white70 : const Color(0xFF19212E),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Search resources...',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.grey[400] : const Color(0xFF4B5563),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(width: 1, height: 30, color: dividerColor),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showFilterOptionsSheet,
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: filterBackground,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: hasActiveFilters
                              ? AppTheme.primary.withValues(alpha: 0.4)
                              : dividerColor,
                        ),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: filterTextColor,
                        size: 18,
                      ),
                    ),
                    if (activeFilterCount > 0)
                      Positioned(
                        right: -4,
                        top: -5,
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0EA5E9),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            activeFilterCount.toString(),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _mapSortOption(String? sortLabel) {
    switch (sortLabel) {
      case 'Most upvotes':
        return 'upvotes';
      case 'Teacher':
        return 'teacher';
      default:
        return null;
    }
  }

  String? _mapResourceType(String? typeLabel) {
    if (typeLabel == null || typeLabel == 'All') {
      return null;
    }
    if (typeLabel == 'Videos') {
      return 'video';
    }
    return typeLabel.toLowerCase();
  }

  void _showFilterOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor:
          Colors.transparent, // Use transparent to handle rounded corners
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) =>
            _buildFilterSheetContent(setModalState),
      ),
    );
  }

  Widget _buildFilterSheetContent(StateSetter setModalState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F1116) : Colors.white;
    void syncSheet() => setModalState(() {});

    return Container(
      height: MediaQuery.of(context).size.height * 0.74,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
            child: Row(
              children: [
                const SizedBox(width: 56),
                Expanded(
                  child: Text(
                    'Sort & filter',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedSemester = null;
                      _selectedBranch = null;
                      _selectedSubject = null;
                      _selectedType = null;
                      _selectedSort = 'Recent';
                      _subjects = [];
                    });
                    syncSheet();
                    _loadResources(refresh: true);
                  },
                  child: Text(
                    'Clear',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                children: [
                  _buildSheetSelectionRow(
                    label: 'Sort by',
                    value: _selectedSort,
                    isDark: isDark,
                    onTap: () {
                      _showPickerSheet(
                        title: 'Sort by',
                        items: _sortOptions,
                        selectedValue: _selectedSort,
                        isDark: isDark,
                        onSelected: (value) {
                          setState(() => _selectedSort = value);
                          syncSheet();
                          _loadResources(refresh: true);
                        },
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
                  ),
                  _buildSheetSelectionRow(
                    label: 'Type',
                    value: _selectedType ?? 'All',
                    isDark: isDark,
                    onTap: () {
                      _showPickerSheet(
                        title: 'Type',
                        items: _types,
                        selectedValue: _selectedType ?? 'All',
                        isDark: isDark,
                        onSelected: (value) {
                          setState(() {
                            _selectedType = value == 'All' ? null : value;
                          });
                          syncSheet();
                          _loadResources(refresh: true);
                        },
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
                  ),
                  _buildSheetSelectionRow(
                    label: 'Semester',
                    value: _selectedSemester ?? 'All',
                    isDark: isDark,
                    onTap: () {
                      _showPickerSheet(
                        title: 'Semester',
                        items: _semesters.isEmpty ? ['All'] : _semesters,
                        selectedValue: _selectedSemester ?? 'All',
                        isDark: isDark,
                        onSelected: (value) {
                          setState(() {
                            _selectedSemester = value == 'All' ? null : value;
                          });
                          syncSheet();
                          _loadResources(refresh: true);
                        },
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
                  ),
                  _buildSheetSelectionRow(
                    label: 'Branch',
                    value: _selectedBranch ?? 'All',
                    isDark: isDark,
                    onTap: () {
                      _showPickerSheet(
                        title: 'Branch',
                        items: _branches.isEmpty ? ['All'] : _branches,
                        selectedValue: _selectedBranch ?? 'All',
                        isDark: isDark,
                        onSelected: (value) {
                          setState(() {
                            _selectedBranch = value == 'All' ? null : value;
                            _selectedSubject = null;
                          });
                          syncSheet();
                          _loadSubjects();
                          _loadResources(refresh: true);
                        },
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
                  ),
                  _buildSheetSelectionRow(
                    label: 'Subject',
                    value:
                        _selectedSubject ??
                        (_selectedBranch == null
                            ? 'Select branch first'
                            : 'All'),
                    isDark: isDark,
                    enabled:
                        _selectedBranch != null && _selectedBranch != 'All',
                    onTap: (_selectedBranch == null || _selectedBranch == 'All')
                        ? null
                        : () {
                            _showPickerSheet(
                              title: 'Subject',
                              items: _subjects.isEmpty ? ['All'] : _subjects,
                              selectedValue: _selectedSubject ?? 'All',
                              isDark: isDark,
                              onSelected: (value) {
                                setState(() {
                                  _selectedSubject = value == 'All'
                                      ? null
                                      : value;
                                });
                                syncSheet();
                                _loadResources(refresh: true);
                              },
                            );
                          },
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                'Show results',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetSelectionRow({
    required String label,
    required String value,
    required bool isDark,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final mutedColor = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          child: Row(
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: enabled ? textColor : mutedColor,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: enabled ? AppTheme.primary : mutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: enabled ? mutedColor : mutedColor.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPickerSheet({
    required String title,
    required List<String> items,
    required String selectedValue,
    required Function(String) onSelected,
    required bool isDark,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Items list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = item == selectedValue;
                  return ListTile(
                    title: Text(
                      item,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? AppTheme.primary
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppTheme.primary,
                            size: 20,
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelected(item);
                    },
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _buildResourcesGrid() {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.purple,
            Colors.transparent,
            Colors.transparent,
            Colors.purple,
          ],
          stops: [0.0, 0.05, 0.9, 1.0], // Fade out top 5% and bottom 10%
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstOut,
      child: AnimationLimiter(
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
          16,
          8,
          16,
          100,
        ), // Bottom padding for FAB/Nav
        itemCount: _resources.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _resources.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final resource = _resources[index];
          return AnimationConfiguration.staggeredList(
            position: index,
            delay: const Duration(milliseconds: 50),
            duration: const Duration(milliseconds: 375),
            child: SlideAnimation(
              verticalOffset: 30.0,
              child: FadeInAnimation(
                child: ResourceCard(
                  resource: resource,
                  userEmail: widget.userEmail,
                  onVoteChanged: () => _loadResources(),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

  Widget _buildLoadingSkeleton() {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => _buildLoadingCard(),
    );
  }

  Widget _buildLoadingCard() {
    return Shimmer.fromColors(
      baseColor: AppTheme.darkCard,
      highlightColor: AppTheme.darkBorder,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 80,
            color: AppTheme.textMuted.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No resources found',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters or search',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _selectedSemester = null;
                _selectedBranch = null;
                _selectedSubject = null;
                _selectedType = null;
                _selectedSort = 'Recent';
                _searchController.clear();
              });
              _loadResources(refresh: true);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reset Filters'),
          ),
        ],
      ),
    );
  }

  void _loadDownloadedResources() {
    setState(() {
      _downloadedResources = DownloadService().getAllDownloadedResources();
    });
  }

  Widget _buildDownloadsTab() {
    if (_downloadedResources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.offline_pin_rounded,
              size: 64,
              color: AppTheme.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No downloads yet',
              style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              'Download notes to access them offline',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textMuted.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _downloadedResources.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ResourceCard(
            resource: _downloadedResources[index],
            userEmail: widget.userEmail,
          ),
        );
      },
    );
  }
}

class _DepartmentCard3D extends StatefulWidget {
  final DepartmentData dept;
  final String collegeId;
  final Color textColor;
  final Color secondaryColor;
  final Color cardColor;
  final Color borderColor;

  const _DepartmentCard3D({
    required this.dept,
    required this.collegeId,
    required this.textColor,
    required this.secondaryColor,
    required this.cardColor,
    required this.borderColor,
  });

  @override
  State<_DepartmentCard3D> createState() => _DepartmentCard3DState();
}

class _DepartmentCard3DState extends State<_DepartmentCard3D>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Matrix4> _transformAnimation;

  double _xRotation = 0.0;
  double _yRotation = 0.0;
  bool _isTapped = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _transformAnimation = Matrix4Tween(
      begin: Matrix4.identity(),
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    // Determine the local position
    final localPosition = details.localPosition;
    
    // Calculate rotation based on pointer pos (max 15 degrees = 0.26 radians)
    final double halfWidth = size.width / 2;
    final double halfHeight = size.height / 2;
    
    // Normalize mapping from -1.0 to 1.0
    final double xFactor = (localPosition.dx - halfWidth) / halfWidth;
    final double yFactor = (localPosition.dy - halfHeight) / halfHeight;
    
    // Clamp to -1..1
    final double clampedX = xFactor.clamp(-1.0, 1.0);
    final double clampedY = yFactor.clamp(-1.0, 1.0);

    setState(() {
      _yRotation = clampedX * 0.15; // Rotate around Y axis based on X pos
      _xRotation = -clampedY * 0.15; // Rotate around X axis based on Y pos
    });
  }

  void _resetTransform() {
    final Matrix4 current = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateX(_xRotation)
      ..rotateY(_yRotation)
      ..scale(_isTapped ? 0.95 : 1.0);

    // Rebuild the matrix tween from the current tapped rotation to identity
    _transformAnimation = Matrix4Tween(
      begin: current,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    setState(() {
      _xRotation = 0.0;
      _yRotation = 0.0;
      _isTapped = false;
    });
    _controller.forward(from: 0.0);
  }

  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    final Matrix4 currentTransform = Matrix4.identity()
      ..setEntry(3, 2, 0.001) // perspective
      ..rotateX(_xRotation)
      ..rotateY(_yRotation)
      ..scale(_isTapped ? 0.95 : 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanDown: (details) {
            setState(() => _isTapped = true);
            _controller.stop();
          },
          onPanUpdate: (details) => _onPanUpdate(details, size),
          onPanEnd: (_) => _resetTransform(),
          onPanCancel: () => _resetTransform(),
          onTapUp: (_) => _resetTransform(),
          onTap: () {
            if (_isNavigating) return;
            setState(() => _isNavigating = true);
            // Slight delay so the press animation is visible
            Future.delayed(const Duration(milliseconds: 150), () {
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SyllabusScreen(
                      collegeId: widget.collegeId,
                      department: widget.dept.name,
                      departmentName: widget.dept.full,
                      departmentColor: widget.dept.color,
                    ),
                  ),
                ).then((_) {
                  if (mounted) setState(() => _isNavigating = false);
                });
              } else {
                _isNavigating = false;
              }
            });
          },
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform(
                transform: _controller.isAnimating
                    ? _transformAnimation.value
                    : currentTransform,
                alignment: Alignment.center,
                child: child,
              );
            },
            child: Material(
              color: widget.cardColor,
              borderRadius: BorderRadius.circular(12),
              elevation: _isTapped ? 8 : 2,
              shadowColor: widget.borderColor.withValues(alpha: 0.5),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.borderColor),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.dept.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.folder_outlined,
                          color: widget.dept.color, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.dept.name,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: widget.textColor,
                      ),
                    ),
                    Text(
                      widget.dept.full,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: widget.secondaryColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
