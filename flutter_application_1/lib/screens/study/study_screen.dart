import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:lottie/lottie.dart';
import 'package:badges/badges.dart' as badges;
import 'package:flutter_app_badger/flutter_app_badger.dart';
import '../../config/theme.dart';
import '../../models/resource.dart';
import '../../services/supabase_service.dart';
import '../../services/download_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/resource_card.dart';
import '../notifications/notification_screen.dart';
import '../profile/bookmarks_screen.dart';
import '../ai_chat_screen.dart';
import '../../services/backend_api_service.dart';
import '../profile/explore_students_screen.dart';
import 'resource_search_screen.dart';
import '../../services/home_widget_service.dart';
import '../../widgets/study/department_card_3d.dart';
import '../../data/academic_subjects_data.dart';
import '../../data/departments_data.dart'; // Added for DepartmentData and DepartmentsProvider
import '../../utils/admin_access.dart';

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
  final SubscriptionService _subscriptionService = SubscriptionService();
  final DownloadService _downloadService = DownloadService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _followingSearchController =
      TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  // Tab state

  // For You resources
  List<Resource> _resources = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  late Future<List<DepartmentData>> _departmentsFuture;
  Timer? _voteRefreshDebounce;
  Timer? _retryTimer;

  // Following resources
  List<Resource> _followingResources = [];
  bool _isLoadingFollowing = true;
  bool _isLoadingMoreModeration = false;
  bool _hasMoreModeration = true;
  int _moderationPage = 1;
  static const int _moderationPageSize = 50;
  bool _isModerating = false;

  // User Profile Data
  String _userSemester = '1';
  String _userBranch = '';
  String? _profileSemesterFilter;
  String? _profileBranchFilter;
  String? _profileSubjectFilter;
  String? _activeModerationSemesterFilter;
  String? _activeModerationBranchFilter;
  String? _activeModerationSubjectFilter;
  bool _didRetryInitialEmptyLoad = false;
  bool _resourcesRelevantOnly = true;
  bool _moderationRelevantOnly = true;
  bool _isResourceScopeToggleLoading = false;
  bool _canManageAdminResources = false;
  String _followingSearchQuery = '';
  List<Resource>? _cachedFilteredFollowingResources;
  String _lastFollowingFilterQuery = '';

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

  String get _effectiveUserEmail {
    final fromWidget = widget.userEmail.trim();
    if (fromWidget.isNotEmpty) return fromWidget;
    return (_supabaseService.currentUserEmail ?? '').trim();
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      int unread = 0;
      try {
        unread = await _apiService.getUnreadNotificationCount();
      } catch (e) {
        debugPrint('Unread count endpoint unavailable, using fallback: $e');
        final notifications = await _apiService.getNotifications(limit: 200);
        unread = notifications.where((notification) {
          final isReadRaw = notification.containsKey('is_read')
              ? notification['is_read']
              : notification['isRead'];
          final isRead = isReadRaw == true;
          return !isRead;
        }).length;
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
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1) {
        _loadFollowingFeed();
      }
    });
    _loadFilters();
    _departmentsFuture = DepartmentsProvider.getDepartments();
    _scrollController.addListener(_onScroll);

    _loadUserProfile().whenComplete(() {
      if (!mounted) return;
      _loadResources();
      _loadFollowingFeed();
      _loadUnreadNotificationCount();
    });
  }

  Future<void> _loadUserProfile({bool forceRefresh = false}) async {
    try {
      final profile = await _supabaseService.getCurrentUserProfile(
        forceRefresh: forceRefresh,
        maxAttempts: forceRefresh ? 2 : 1,
      );
      if (profile.isEmpty) return;
      final semester = _normalizeFilterValue(profile['semester']?.toString());
      final branch = _normalizeFilterValue(profile['branch']?.toString());
      final subject = isTeacherOrAdminProfile(profile)
          ? _normalizeFilterValue(profile['subject']?.toString())
          : null;
      final normalizedBranchCode = normalizeBranchCode(branch);
      final canManageAdminResources = canManageAdminResourcesProfile(profile);
      if (mounted) {
        setState(() {
          _profileSemesterFilter = semester;
          _profileBranchFilter = branch;
          _profileSubjectFilter = subject;
          _userSemester = semester ?? '1';
          _userBranch = normalizedBranchCode.isEmpty
              ? (branch ?? _userBranch)
              : normalizedBranchCode;
          _canManageAdminResources = canManageAdminResources;
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile in StudyScreen: $e');
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _voteRefreshDebounce?.cancel();
    _searchController.dispose();
    _followingSearchController.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<Resource> get _filteredFollowingResources {
    final query = _followingSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      _cachedFilteredFollowingResources = null;
      _lastFollowingFilterQuery = '';
      return _followingResources;
    }

    if (_cachedFilteredFollowingResources != null &&
        _lastFollowingFilterQuery == query) {
      return _cachedFilteredFollowingResources!;
    }

    _cachedFilteredFollowingResources = _followingResources.where((resource) {
      final haystacks = <String>[
        resource.title,
        resource.description ?? '',
        resource.subject ?? '',
        resource.branch ?? '',
        resource.semester ?? '',
        resource.uploadedByName ?? '',
      ];
      return haystacks.any((value) => value.toLowerCase().contains(query));
    }).toList();
    _lastFollowingFilterQuery = query;
    return _cachedFilteredFollowingResources!;
  }

  void _handleResourceVoteChanged() {
    if (_mapSortOption(_selectedSort) != 'upvotes') {
      return;
    }
    _voteRefreshDebounce?.cancel();
    _voteRefreshDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _loadResources();
    });
  }

  Future<void> _loadFollowingFeed() async {
    if (mounted) {
      setState(() {
        _isLoadingFollowing = true;
        _isLoadingMoreModeration = false;
      });
    }

    try {
      await _loadUserProfile(forceRefresh: true);

      if (_canManageAdminResources) {
        const requestPage = 1;
        final scopeCandidates = _buildModerationScopeCandidates();
        var selectedScope = scopeCandidates.first;
        List<Resource> resources = const <Resource>[];

        for (final scope in scopeCandidates) {
          final scopedResources = await _loadAdminResourcesForScope(
            page: requestPage,
            semester: scope.semester,
            branch: scope.branch,
            subject: scope.subject,
          );
          selectedScope = scope;
          resources = scopedResources;
          if (scopedResources.isNotEmpty || !_moderationRelevantOnly) {
            break;
          }
        }

        if (!mounted) return;
        setState(() {
          _moderationPage = requestPage;
          _activeModerationSemesterFilter = selectedScope.semester;
          _activeModerationBranchFilter = selectedScope.branch;
          _activeModerationSubjectFilter = selectedScope.subject;
          _followingResources = resources;
          _hasMoreModeration = resources.length >= _moderationPageSize;
          _isLoadingMoreModeration = false;
          _isLoadingFollowing = false;
        });
      } else {
        final activeEmail = _effectiveUserEmail;
        if (activeEmail.isEmpty) {
          if (!mounted) return;
          setState(() {
            _followingResources = [];
            _isLoadingFollowing = false;
            _hasMoreModeration = false;
            _isLoadingMoreModeration = false;
          });
          return;
        }

        final resources = await _supabaseService.getFollowingFeed(
          userEmail: activeEmail,
          collegeId: widget.collegeId,
        );
        if (!mounted) return;
        setState(() {
          _followingResources = resources;
          _hasMoreModeration = false;
          _isLoadingMoreModeration = false;
          _isLoadingFollowing = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading following/moderation feed: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingFollowing = false;
        _isLoadingMoreModeration = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load feed. Please try again.')),
      );
    }
  }

  Future<void> _loadMoreModerationResources() async {
    if (!_canManageAdminResources ||
        _isLoadingMoreModeration ||
        _isLoadingFollowing ||
        !_hasMoreModeration) {
      return;
    }

    final nextPage = _moderationPage + 1;
    setState(() => _isLoadingMoreModeration = true);
    try {
      final resources = await _loadAdminResourcesForScope(
        page: nextPage,
        semester: _resolvedModerationSemesterFilter(),
        branch: _resolvedModerationBranchFilter(),
        subject: _resolvedModerationSubjectFilter(),
      );

      if (!mounted) return;
      setState(() {
        _moderationPage = nextPage;
        _followingResources = [..._followingResources, ...resources];
        _hasMoreModeration = resources.length >= _moderationPageSize;
        _isLoadingMoreModeration = false;
      });
    } catch (e) {
      debugPrint('Error loading more moderation resources: $e');
      if (!mounted) return;
      setState(() => _isLoadingMoreModeration = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load more moderation items.')),
      );
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

    if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _subjects = ['All', ...subjects];
      });
    } else {
      if (!mounted) return;
      setState(() => _subjects = []);
    }
  }

  String? _normalizeFilterValue(String? value) {
    final trimmed = value?.trim() ?? '';
    final lower = trimmed.toLowerCase();
    const nullLikeValues = {'all', 'null', 'none', 'n/a', '-'};
    if (trimmed.isEmpty || nullLikeValues.contains(lower)) {
      return null;
    }
    return trimmed;
  }

  String? _normalizeBranchCodeFilter(String? value) {
    final normalized = normalizeBranchCode(value);
    return normalized.isEmpty ? null : normalized;
  }

  List<({String? semester, String? branch, String? subject})>
  _buildModerationScopeCandidates() {
    if (!_moderationRelevantOnly) {
      return const <({String? semester, String? branch, String? subject})>[
        (semester: null, branch: null, subject: null),
      ];
    }

    final semester = _normalizeFilterValue(_profileSemesterFilter);
    final subject = _normalizeFilterValue(_profileSubjectFilter);
    final rawBranch = _normalizeFilterValue(_profileBranchFilter);
    final normalizedBranch = _normalizeBranchCodeFilter(rawBranch);
    final branchVariants = <String?>[
      rawBranch,
      if (normalizedBranch != null && normalizedBranch != rawBranch)
        normalizedBranch,
      null,
    ];

    final seen = <String>{};
    final scopes = <({String? semester, String? branch, String? subject})>[];

    void addScope(String? sem, String? branch, String? subj) {
      final resolvedSemester = _normalizeFilterValue(sem);
      final resolvedBranch = _normalizeFilterValue(branch);
      final resolvedSubject = _normalizeFilterValue(subj);
      final signature = [
        resolvedSemester ?? '*',
        resolvedBranch ?? '*',
        resolvedSubject ?? '*',
      ].join('|');
      if (!seen.add(signature)) return;
      scopes.add((
        semester: resolvedSemester,
        branch: resolvedBranch,
        subject: resolvedSubject,
      ));
    }

    for (final branch in branchVariants) {
      addScope(semester, branch, subject);
    }
    for (final branch in branchVariants) {
      addScope(semester, branch, null);
    }
    for (final branch in branchVariants) {
      addScope(null, branch, null);
    }
    addScope(null, null, null);

    return scopes;
  }

  Future<List<Resource>> _loadAdminResourcesForScope({
    required int page,
    String? semester,
    String? branch,
    String? subject,
  }) async {
    final resourcesPayload = await _apiService.listAdminResources(
      collegeId: widget.collegeId,
      semester: semester,
      branch: branch,
      subject: subject,
      page: page,
      pageSize: _moderationPageSize,
    );

    return resourcesPayload.map((json) => Resource.fromJson(json)).toList();
  }

  String? _resolvedResourceSemesterFilter() {
    if (_resourcesRelevantOnly) {
      return _normalizeFilterValue(_profileSemesterFilter);
    }
    return _normalizeFilterValue(_selectedSemester);
  }

  String? _resolvedResourceBranchFilter() {
    if (_resourcesRelevantOnly) {
      return _normalizeFilterValue(_profileBranchFilter);
    }
    return _normalizeFilterValue(_selectedBranch);
  }

  String? _resolvedResourceSubjectFilter() {
    if (_resourcesRelevantOnly) {
      return _normalizeFilterValue(_profileSubjectFilter);
    }
    return _normalizeFilterValue(_selectedSubject);
  }

  String? _resolvedModerationSemesterFilter() {
    if (!_moderationRelevantOnly) return null;
    return _normalizeFilterValue(
      _activeModerationSemesterFilter ?? _profileSemesterFilter,
    );
  }

  String? _resolvedModerationBranchFilter() {
    if (!_moderationRelevantOnly) return null;
    return _normalizeFilterValue(
      _activeModerationBranchFilter ?? _profileBranchFilter,
    );
  }

  String? _resolvedModerationSubjectFilter() {
    if (!_moderationRelevantOnly) return null;
    return _normalizeFilterValue(
      _activeModerationSubjectFilter ?? _profileSubjectFilter,
    );
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
      final hasPremiumAccess = await _subscriptionService.isPremium();
      final downloadedResources = await _downloadService
          .getAllDownloadedResourcesForUser(
            _effectiveUserEmail,
            hasPremiumAccess: hasPremiumAccess,
          );
      if (!mounted) return;
      setState(() {
        _resources = downloadedResources;
        _isLoading = false;
      });
      return;
    }

    try {
      final resources = await _fetchResourcesWithRelevantFallback(offset: 0);

      if (!mounted) return;

      setState(() {
        _resources = resources;
        _isLoading = false;
      });

      // Retry once when first load returns empty with default filters.
      if (!_didRetryInitialEmptyLoad &&
          !refresh &&
          resources.isEmpty &&
          !_hasActiveFilters) {
        _didRetryInitialEmptyLoad = true;
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(milliseconds: 900), () {
          _retryTimer = null;
          if (!mounted) return;
          _loadResources(refresh: true);
        });
      }

      // Update Home Widget by filtering syllabus resources
      if (_selectedType == null) {
        final syllabusResources = resources
            .where((r) => r.type.toLowerCase() == 'syllabus')
            .toList();
        HomeWidgetService.instance.syncSyllabus(
          _userSemester,
          _userBranch,
          syllabusResources,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!_didRetryInitialEmptyLoad && !refresh && !_hasActiveFilters) {
        _didRetryInitialEmptyLoad = true;
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(milliseconds: 900), () {
          _retryTimer = null;
          if (!mounted) return;
          _loadResources(refresh: true);
        });
      }
    }
  }

  int get _manualAcademicFilterCount {
    if (_resourcesRelevantOnly) return 0;
    return [
      _selectedSemester != null && _selectedSemester != 'All',
      _selectedBranch != null && _selectedBranch != 'All',
      _selectedSubject != null && _selectedSubject != 'All',
    ].where((isApplied) => isApplied).length;
  }

  bool get _hasManualAcademicFilters => _manualAcademicFilterCount > 0;

  int get _activeResourceFilterCount {
    return _manualAcademicFilterCount +
        (_selectedType != null && _selectedType != 'All' ? 1 : 0) +
        (_selectedSort != 'Recent' ? 1 : 0) +
        (!_resourcesRelevantOnly ? 1 : 0);
  }

  bool get _hasActiveFilters {
    return _hasManualAcademicFilters ||
        (_selectedType != null && _selectedType != 'All') ||
        _selectedSort != 'Recent' ||
        !_resourcesRelevantOnly ||
        _searchController.text.trim().isNotEmpty;
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
      final moreResources = await _fetchResourcesWithRelevantFallback(
        offset: _resources.length,
      );

      if (!mounted) return;

      setState(() {
        _resources = [..._resources, ...moreResources];
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<List<Resource>> _queryResources({
    required int offset,
    String? semester,
    String? branch,
    String? subject,
  }) {
    return _supabaseService.getResources(
      collegeId: widget.collegeId,
      semester: semester,
      branch: branch,
      subject: subject,
      type: _mapResourceType(_selectedType),
      searchQuery: _searchController.text.isNotEmpty
          ? _searchController.text
          : null,
      sortBy: _mapSortOption(_selectedSort),
      offset: offset,
    );
  }

  Future<List<Resource>> _fetchResourcesWithRelevantFallback({
    required int offset,
  }) async {
    final semesterFilter = _resolvedResourceSemesterFilter();
    final branchFilter = _resolvedResourceBranchFilter();
    final subjectFilter = _resolvedResourceSubjectFilter();

    final primary = await _queryResources(
      offset: offset,
      semester: semesterFilter,
      branch: branchFilter,
      subject: subjectFilter,
    );

    if (!_resourcesRelevantOnly || primary.isNotEmpty) {
      return primary;
    }

    final hasRelevantFilters = [
      semesterFilter,
      branchFilter,
      subjectFilter,
    ].any((value) => value != null && value.trim().isNotEmpty);
    if (!hasRelevantFilters) {
      return primary;
    }

    final seen = <String>{
      '${semesterFilter ?? ''}|${branchFilter ?? ''}|${subjectFilter ?? ''}',
    };
    final fallbackAttempts =
        <({String? semester, String? branch, String? subject})>[
          (semester: semesterFilter, branch: branchFilter, subject: null),
          (semester: null, branch: branchFilter, subject: subjectFilter),
          (semester: null, branch: branchFilter, subject: null),
          (semester: null, branch: null, subject: subjectFilter),
          (semester: semesterFilter, branch: null, subject: null),
          (semester: null, branch: null, subject: null),
        ];

    for (final attempt in fallbackAttempts) {
      final key =
          '${attempt.semester ?? ''}|${attempt.branch ?? ''}|${attempt.subject ?? ''}';
      if (!seen.add(key)) continue;

      final rows = await _queryResources(
        offset: offset,
        semester: attempt.semester,
        branch: attempt.branch,
        subject: attempt.subject,
      );
      if (rows.isNotEmpty) {
        debugPrint(
          'Relevant scope fallback matched resources with filters: '
          'semester=${attempt.semester}, branch=${attempt.branch}, subject=${attempt.subject}',
        );
        return rows;
      }
    }

    return primary;
  }

  // Unused method removed

  @override
  Widget build(BuildContext context) {
    final isTeacher = _canManageAdminResources;
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
                        _buildResourcesScopeStrip(),
                        Expanded(
                          child: CustomRefreshIndicator(
                            onRefresh: () => _loadResources(refresh: true),
                            builder: (context, child, controller) =>
                                _buildRefreshIndicatorContent(
                                  controller,
                                  child,
                                ),
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
                    Column(
                      children: [
                        if (isTeacher) _buildModerationScopeStrip(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                          child: _buildFollowingSearchBar(),
                        ),
                        Expanded(
                          child: CustomRefreshIndicator(
                            onRefresh: _loadFollowingFeed,
                            builder: (context, child, controller) =>
                                _buildRefreshIndicatorContent(
                                  controller,
                                  child,
                                ),
                            child: _isLoadingFollowing
                                ? _buildLoadingSkeleton()
                                : _followingResources.isEmpty
                                ? (isTeacher
                                      ? _buildModerationEmptyState()
                                      : _buildFollowingEmptyState())
                                : _filteredFollowingResources.isEmpty
                                ? _buildFollowingSearchEmptyState(isTeacher)
                                : _buildFollowingGrid(),
                          ),
                        ),
                      ],
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
          Tab(text: _canManageAdminResources ? 'Moderation' : 'Following'),
          const Tab(text: 'Syllabus'),
        ],
      ),
    );
  }

  Widget _buildResourcesScopeStrip() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Text(
            'Resources scope',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF4B5563),
            ),
          ),
          const Spacer(),
          _buildScopeToggle(
            relevantOnly: _resourcesRelevantOnly,
            onChanged: (relevantOnly) {
              _handleResourcesScopeChanged(relevantOnly);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleResourcesScopeChanged(bool relevantOnly) async {
    if (_resourcesRelevantOnly == relevantOnly ||
        _isResourceScopeToggleLoading) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _resourcesRelevantOnly = relevantOnly;
      _isResourceScopeToggleLoading = true;
    });

    try {
      if (relevantOnly) {
        await _loadUserProfile();
        if (!mounted) return;
        await _loadResources(refresh: true);
        return;
      }

      if (_selectedBranch != null && _selectedBranch != 'All') {
        await _loadSubjects();
      }
      if (!mounted) return;
      await _loadResources(refresh: true);
    } finally {
      if (mounted) {
        setState(() => _isResourceScopeToggleLoading = false);
      }
    }
  }

  Widget _buildModerationScopeStrip() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Text(
            'Moderation scope',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF4B5563),
            ),
          ),
          const Spacer(),
          _buildScopeToggle(
            relevantOnly: _moderationRelevantOnly,
            onChanged: (relevantOnly) {
              if (_moderationRelevantOnly == relevantOnly) return;
              setState(() => _moderationRelevantOnly = relevantOnly);
              _loadFollowingFeed();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFollowingSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: TextField(
        controller: _followingSearchController,
        onChanged: (value) {
          setState(() => _followingSearchQuery = value);
        },
        style: GoogleFonts.inter(
          fontSize: 14,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: _canManageAdminResources
              ? 'Search moderation queue...'
              : 'Search following feed...',
          hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppTheme.textMuted,
          ),
          suffixIcon: _followingSearchQuery.trim().isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _followingSearchController.clear();
                    setState(() => _followingSearchQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildScopeToggle({
    required bool relevantOnly,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF12151C)
        : const Color(0xFFF3F4F6);
    final activeColor = isDark
        ? AppTheme.primary.withValues(alpha: 0.32)
        : AppTheme.primary.withValues(alpha: 0.16);
    final border = isDark ? Colors.white10 : const Color(0xFFE5E7EB);

    Widget segment({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: selected ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppTheme.primary
                      : (isDark ? Colors.white70 : const Color(0xFF6B7280)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 128,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          segment(
            label: 'Relevant',
            selected: relevantOnly,
            onTap: () => onChanged(true),
          ),
          segment(
            label: 'All',
            selected: !relevantOnly,
            onTap: () => onChanged(false),
          ),
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
          userEmail: _effectiveUserEmail,
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
            _moderationRelevantOnly
                ? 'No resources to moderate for your saved scope.'
                : 'No resources available for moderation.',
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

  Widget _buildFollowingSearchEmptyState(bool isTeacher) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 58,
            color: AppTheme.textMuted.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 14),
          Text(
            'No matches found',
            style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            isTeacher
                ? 'Try a different search for the moderation queue.'
                : 'Try a different search for your following feed.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textMuted.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowingGrid() {
    final isTeacher = _canManageAdminResources;
    final isFiltering = _followingSearchQuery.trim().isNotEmpty;
    final showLoadMore =
        isTeacher &&
        !isFiltering &&
        (_hasMoreModeration || _isLoadingMoreModeration);
    final visibleResources = _filteredFollowingResources;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        100,
      ), // Bottom padding for floating nav
      itemCount: visibleResources.length + (showLoadMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (showLoadMore && index == visibleResources.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Center(
              child: _isLoadingMoreModeration
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : OutlinedButton.icon(
                      onPressed: _loadMoreModerationResources,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('Load more'),
                    ),
            ),
          );
        }

        final resource = visibleResources[index];
        final status = resource.status.toLowerCase();
        final bool isApproved = status == 'approved';
        final bool isPending = status == 'pending';
        final bool isRejected = status == 'rejected';

        final VoidCallback? onApprove = isTeacher && !isApproved
            ? () => _moderateResource(resource.id, 'approved')
            : null;
        final VoidCallback? onReject = isTeacher && isPending
            ? () => _moderateResource(resource.id, 'rejected')
            : null;
        final VoidCallback? onRetract = isTeacher && isApproved
            ? () => _moderateResource(resource.id, 'rejected')
            : (isTeacher && isRejected
                  ? () => _moderateResource(resource.id, 'pending')
                  : null);
        final VoidCallback? onDelete = isTeacher
            ? () => _deleteResource(resource)
            : null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ResourceCard(
            resource: resource,
            userEmail: _effectiveUserEmail,
            showModerationControls: isTeacher,
            onApprove: onApprove,
            onRetract: onRetract,
            onReject: onReject,
            onDelete: onDelete,
          ),
        );
      },
    );
  }

  Future<void> _moderateResource(String resourceId, String newStatus) async {
    if (_isModerating) return;
    if (!_canManageAdminResources) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to moderate resources.'),
        ),
      );
      return;
    }

    setState(() => _isModerating = true);

    try {
      await _supabaseService.updateResourceStatusWithFallback(
        resourceId: resourceId,
        status: newStatus,
        context: context,
      );

      if (!mounted) return;
      await _loadFollowingFeed();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'rejected'
                ? 'Resource retracted/rejected successfully'
                : newStatus == 'pending'
                ? 'Resource retracted successfully'
                : 'Resource $newStatus successfully',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error moderating resource: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to moderate resource: $e')),
      );
    } finally {
      if (mounted) setState(() => _isModerating = false);
    }
  }

  Future<void> _deleteResource(Resource resource) async {
    if (_isModerating) return;
    if (!_canManageAdminResources) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to delete resources.'),
        ),
      );
      return;
    }

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete Resource?'),
          content: Text(
            'This will permanently delete "${resource.title}" from StudyShare.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      if (!mounted) return;
      setState(() => _isModerating = true);

      await _supabaseService.deleteResourceAsAdminWithFallback(
        resourceId: resource.id,
      );
      await _downloadService.deleteResource(resource.id);

      if (!mounted) return;
      await _loadFollowingFeed();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resource deleted successfully')),
      );
    } catch (e) {
      debugPrint('Error deleting resource: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete resource: $e')));
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
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
                _unreadNotificationCount > 9
                    ? '9+'
                    : _unreadNotificationCount.toString(),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              badgeStyle: badges.BadgeStyle(
                badgeColor: AppTheme.error,
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

    return DepartmentCard3D(
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
        _hasManualAcademicFilters ||
        (_selectedType != null && _selectedType != 'All') ||
        _selectedSort != 'Recent' ||
        !_resourcesRelevantOnly;
    final activeFilterCount = _activeResourceFilterCount;

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
                  userEmail: _effectiveUserEmail,
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
          _buildFilterHeader(setModalState, isDark, syncSheet),
          Divider(
            height: 1,
            color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
          ),
          _buildFilterBody(isDark, syncSheet),
          _buildFilterFooter(),
        ],
      ),
    );
  }

  Widget _buildFilterHeader(
    StateSetter setModalState,
    bool isDark,
    VoidCallback syncSheet,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
                    _resourcesRelevantOnly = true;
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
      ],
    );
  }

  Widget _buildFilterBody(bool isDark, VoidCallback syncSheet) {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          children: [
            if (_resourcesRelevantOnly)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Relevant scope uses profile semester/branch/subject. '
                    'Switch to All to apply manual academic filters.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ),
              ),
            _buildSortRow(isDark, syncSheet),
            _divider(isDark),
            _buildTypeRow(isDark, syncSheet),
            _divider(isDark),
            _buildAcademicFilterRows(isDark, syncSheet),
          ],
        ),
      ),
    );
  }

  Divider _divider(bool isDark) => Divider(
    height: 1,
    color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
  );

  Widget _buildSortRow(bool isDark, VoidCallback syncSheet) {
    return _buildSheetSelectionRow(
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
    );
  }

  Widget _buildTypeRow(bool isDark, VoidCallback syncSheet) {
    return _buildSheetSelectionRow(
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
    );
  }

  Widget _buildAcademicFilterRows(bool isDark, VoidCallback syncSheet) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSheetSelectionRow(
          label: 'Semester',
          value: _resourcesRelevantOnly
              ? (_profileSemesterFilter ?? 'Profile not set')
              : (_selectedSemester ?? 'All'),
          isDark: isDark,
          enabled: !_resourcesRelevantOnly,
          onTap: _resourcesRelevantOnly
              ? null
              : () {
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
        _divider(isDark),
        _buildSheetSelectionRow(
          label: 'Branch',
          value: _resourcesRelevantOnly
              ? (_profileBranchFilter ?? 'Profile not set')
              : (_selectedBranch ?? 'All'),
          isDark: isDark,
          enabled: !_resourcesRelevantOnly,
          onTap: _resourcesRelevantOnly
              ? null
              : () {
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
        _divider(isDark),
        _buildSheetSelectionRow(
          label: 'Subject',
          value: _resourcesRelevantOnly
              ? (_profileSubjectFilter ?? 'Profile not set')
              : (_selectedSubject ??
                    (_selectedBranch == null ? 'Select branch first' : 'All')),
          isDark: isDark,
          enabled:
              !_resourcesRelevantOnly &&
              _selectedBranch != null &&
              _selectedBranch != 'All',
          onTap:
              (_resourcesRelevantOnly ||
                  _selectedBranch == null ||
                  _selectedBranch == 'All')
              ? null
              : () {
                  _showPickerSheet(
                    title: 'Subject',
                    items: _subjects.isEmpty ? ['All'] : _subjects,
                    selectedValue: _selectedSubject ?? 'All',
                    isDark: isDark,
                    onSelected: (value) {
                      setState(() {
                        _selectedSubject = value == 'All' ? null : value;
                      });
                      syncSheet();
                      _loadResources(refresh: true);
                    },
                  );
                },
        ),
        _divider(isDark),
      ],
    );
  }

  Widget _buildFilterFooter() {
    return Padding(
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
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
        ),
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
                    userEmail: _effectiveUserEmail,
                    onVoteChanged: _handleResourceVoteChanged,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRefreshIndicatorContent(
    IndicatorController controller,
    Widget child,
  ) {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor =
        theme.cardTheme.color ??
        (isDark ? AppTheme.darkCard : AppTheme.lightCard);
    final lightTarget = isDark
        ? theme.colorScheme.onSurface
        : theme.colorScheme.surface;
    final highlightColor =
        Color.lerp(baseColor, lightTarget, isDark ? 0.22 : 0.08) ?? baseColor;
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        decoration: BoxDecoration(
          color: baseColor,
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
                _resourcesRelevantOnly = true;
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
}
