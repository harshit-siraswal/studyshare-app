import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import 'department_account_screen.dart' as dept_screen;
import '../../widgets/notice_card.dart';
import '../../models/department_account.dart';
import '../../widgets/branded_loader.dart';
import '../../services/home_widget_service.dart';
import '../../models/notice.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

class NoticesScreen extends StatefulWidget {
  final String collegeId;
  final int refreshToken;

  const NoticesScreen({
    super.key,
    required this.collegeId,
    this.refreshToken = 0,
  });

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _filteredNotices = [];
  bool _isLoading = true;

  late TabController _tabController;

  // Department accounts (Twitter-style)
  final List<DepartmentAccount> _departmentAccounts = [
    DepartmentAccount(
      id: 'general',
      name: 'General Notices',
      handle: '@general',
      avatarLetter: 'G',
      color: const Color(0xFF3B82F6),
    ),
    DepartmentAccount(
      id: 'cse',
      name: 'Computer Science',
      handle: '@cse_dept',
      avatarLetter: 'CS',
      color: const Color(0xFF8B5CF6),
    ),
    DepartmentAccount(
      id: 'ece',
      name: 'Electronics & Comm',
      handle: '@ece_dept',
      avatarLetter: 'EC',
      color: const Color(0xFF10B981),
    ),
    DepartmentAccount(
      id: 'eee',
      name: 'Electrical Engg',
      handle: '@eee_dept',
      avatarLetter: 'EE',
      color: const Color(0xFFF59E0B),
    ),
    DepartmentAccount(
      id: 'me',
      name: 'Mechanical Engg',
      handle: '@mech_dept',
      avatarLetter: 'ME',
      color: const Color(0xFFEF4444),
    ),
    DepartmentAccount(
      id: 'ce',
      name: 'Civil Engineering',
      handle: '@civil_dept',
      avatarLetter: 'CE',
      color: const Color(0xFF6366F1),
    ),
    DepartmentAccount(
      id: 'it',
      name: 'Information Tech',
      handle: '@it_dept',
      avatarLetter: 'IT',
      color: const Color(0xFF14B8A6),
    ),
  ];

  DateTime? _startDate;
  DateTime? _endDate;
  final Map<String, int> _departmentFollowerCounts = {};

  Future<void> _showDateFilter() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.primary,
              brightness: isDark ? Brightness.dark : Brightness.light,
              surface: isDark ? AppTheme.darkSurface : Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _isLoading = true;
      });
      _loadNotices();
    }
  }

  void _showNoticeSearch(bool isDark) {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 240),
        reverseDuration: Duration(milliseconds: 180),
      ),
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          void performSearch(String query) {
            if (query.isEmpty) {
              setModalState(() => searchResults = []);
              return;
            }
            final lowercaseQuery = query.toLowerCase();
            setModalState(() {
              searchResults = _filteredNotices.where((notice) {
                final title = (notice['title'] as String? ?? '').toLowerCase();
                final content = (notice['content'] as String? ?? '')
                    .toLowerCase();
                return title.contains(lowercaseQuery) ||
                    content.contains(lowercaseQuery);
              }).toList();
            });
          }

          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Search field
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search notices...',
                      hintStyle: GoogleFonts.inter(color: Colors.grey),
                      prefixIcon: Icon(
                        Icons.search,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2C2C2E)
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    onChanged: performSearch,
                  ),
                  const SizedBox(height: 16),
                  // Results
                  Expanded(
                    child: searchResults.isEmpty
                        ? Center(
                            child: Text(
                              searchController.text.isEmpty
                                  ? 'Type to search notices'
                                  : 'No results found',
                              style: GoogleFonts.inter(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: searchResults.length,
                            itemBuilder: (context, index) {
                              final notice = searchResults[index];
                              final deptId =
                                  notice['department'] as String? ?? 'general';
                              final account = _departmentAccounts.firstWhere(
                                (a) => a.id == deptId,
                                orElse: () => _departmentAccounts.first,
                              );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: NoticeCard(
                                  notice: notice,
                                  account: account,
                                  collegeId: widget.collegeId,
                                  isDark: isDark,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Set<String> _followedDepartments = {};

  String get _activeUserEmail {
    return (_authService.userEmail ?? _supabaseService.currentUserEmail ?? '')
        .trim();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadNotices();
    _loadFollowedDepartments();
    _loadDepartmentFollowerCounts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NoticesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      _loadNotices();
      _loadFollowedDepartments();
      _loadDepartmentFollowerCounts();
    }
  }

  Future<void> _loadDepartmentFollowerCounts() async {
    try {
      final entries = await Future.wait(
        _departmentAccounts.map((account) async {
          final count = await _supabaseService.getDepartmentFollowerCount(
            account.id,
            widget.collegeId,
          );
          return MapEntry(account.id, count);
        }),
      );

      if (!mounted) return;
      setState(() {
        _departmentFollowerCounts
          ..clear()
          ..addEntries(entries);
      });
    } catch (e) {
      debugPrint('Error loading department follower counts: $e');
    }
  }

  Future<void> _loadFollowedDepartments() async {
    final email = _activeUserEmail;
    if (email.isEmpty) return;

    try {
      final followedIds = await _supabaseService.getFollowedDepartmentIds(
        widget.collegeId,
        email,
      );
      if (mounted) {
        setState(() {
          _followedDepartments = followedIds.toSet();
        });
      }
    } catch (e) {
      debugPrint('Error loading followed departments: $e');
    }
  }

  Future<void> _toggleDepartmentFollow(String deptId) async {
    final email = _activeUserEmail;
    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in to follow')));
      return;
    }

    final isFollowing = _followedDepartments.contains(deptId);

    // Optimistic update
    setState(() {
      if (isFollowing) {
        _followedDepartments.remove(deptId);
        _departmentFollowerCounts[deptId] = math.max(
          0,
          (_departmentFollowerCounts[deptId] ?? 1) - 1,
        );
      } else {
        _followedDepartments.add(deptId);
        _departmentFollowerCounts[deptId] =
            (_departmentFollowerCounts[deptId] ?? 0) + 1;
      }
    });

    try {
      if (isFollowing) {
        await _supabaseService.unfollowDepartment(
          deptId,
          email,
          collegeId: widget.collegeId,
        );
      } else {
        await _supabaseService.followDepartment(
          deptId,
          widget.collegeId,
          email,
        );
      }
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          if (isFollowing) {
            _followedDepartments.add(deptId);
            _departmentFollowerCounts[deptId] =
                (_departmentFollowerCounts[deptId] ?? 0) + 1;
          } else {
            _followedDepartments.remove(deptId);
            _departmentFollowerCounts[deptId] = math.max(
              0,
              (_departmentFollowerCounts[deptId] ?? 1) - 1,
            );
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_followErrorMessage(e))));
      }
    }
  }

  Future<void> _loadNotices() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final notices = await _supabaseService.getNotices(
        collegeId: widget.collegeId,
      );

      // Filter by date range if set
      List<Map<String, dynamic>> filtered = notices;
      if (_startDate != null && _endDate != null) {
        filtered = notices.where((notice) {
          final createdAt = notice['created_at'];
          if (createdAt == null) return false;
          final date = DateTime.tryParse(createdAt.toString());
          if (date == null) return false;
          return date.isAfter(_startDate!.subtract(const Duration(days: 1))) &&
              date.isBefore(_endDate!.add(const Duration(days: 1)));
        }).toList();
      }

      if (mounted) {
        setState(() {
          _filteredNotices = filtered;
          _isLoading = false;
        });
      }

      // Sync the latest unfiltered notices to the home screen widget
      final List<Notice> noticeObjs = [];
      int failCount = 0;
      for (final n in notices) {
        try {
          noticeObjs.add(Notice.fromJson(n));
        } catch (e) {
          failCount++;
          debugPrint('Notice.fromJson skipped malformed entry: $e');
        }
      }
      if (failCount > 0) {
        debugPrint(
          'Widget sync: $failCount notice(s) skipped due to parse errors',
        );
      }
      unawaited(
        HomeWidgetService.instance.syncNotices(noticeObjs).catchError((e) {
          debugPrint('HomeWidget sync failed: $e');
          return false;
        }),
      );
    } catch (e) {
      debugPrint('Error loading notices: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: bgColor,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notices',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            Text(
                              'Latest updates from your departments',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: isDark
                                    ? AppTheme.darkTextMuted
                                    : AppTheme.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.calendar_today_rounded,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onPressed: _showDateFilter,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.search_rounded,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onPressed: () => _showNoticeSearch(isDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => _showNoticeSearch(isDark),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white10
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Search notices...',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: isDark ? Colors.white : Colors.black,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primary,
              tabs: const [
                Tab(text: 'Latest Updates'),
                Tab(text: 'Departments'),
              ],
            ),
            _buildDateFilterHeader(isDark),

            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Notices List
                  RefreshIndicator(
                    onRefresh: _loadNotices,
                    child: _isLoading
                        ? _buildLoadingSkeleton(isDark)
                        : _filteredNotices.isEmpty
                        ? _buildEmptyState(isDark)
                        : AnimationLimiter(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                120,
                              ),
                              itemCount: _filteredNotices.length,
                              itemBuilder: (context, index) {
                                final notice = _filteredNotices[index];
                                // Attempt to map to department, fallback to General
                                // Depending on notice schema, it might have 'department' key
                                final deptId =
                                    notice['department'] as String? ??
                                    'general';
                                final account = _departmentAccounts.firstWhere(
                                  (a) => a.id == deptId,
                                  orElse: () => _departmentAccounts.first,
                                );

                                return AnimationConfiguration.staggeredList(
                                  position: index,
                                  duration: const Duration(milliseconds: 375),
                                  child: SlideAnimation(
                                    verticalOffset: 20.0,
                                    child: FadeInAnimation(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: NoticeCard(
                                          notice: notice,
                                          account: account,
                                          collegeId: widget.collegeId,
                                          isDark: isDark,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),

                  // Tab 2: Departments List
                  AnimationLimiter(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(top: 12, bottom: 120),
                      itemCount: _departmentAccounts.length,
                      itemBuilder: (context, index) {
                        final account = _departmentAccounts[index];
                        return _buildDepartmentAccountTile(
                          account,
                          isDark,
                          index,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentAccountTile(
    DepartmentAccount account,
    bool isDark,
    int index,
  ) {
    final isFollowing = _followedDepartments.contains(account.id);
    final followerCount = _departmentFollowerCounts[account.id] ?? 0;

    return AnimationConfiguration.staggeredList(
      position: index,
      duration: const Duration(milliseconds: 375),
      child: SlideAnimation(
        horizontalOffset: 20.0,
        child: FadeInAnimation(
          child: InkWell(
            onTap: () async {
              // Navigate to department account page and refresh on return
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => dept_screen.DepartmentAccountScreen(
                    account: DepartmentAccount(
                      id: account.id,
                      name: account.name,
                      handle: account.handle,
                      avatarLetter: account.avatarLetter,
                      color: account.color,
                    ),
                    collegeId: widget.collegeId,
                  ),
                ),
              );
              _loadFollowedDepartments(); // Refresh state on return
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: account.color,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Center(
                      child: Text(
                        account.avatarLetter,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: account.avatarLetter.length > 1 ? 16 : 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                account.name,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: isDark
                                      ? AppTheme.darkTextPrimary
                                      : AppTheme.lightTextPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: AppTheme.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              account.handle,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: isDark
                                    ? AppTheme.darkTextMuted
                                    : AppTheme.lightTextMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.people_outline_rounded,
                              size: 14,
                              color: isDark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.lightTextMuted,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '$followerCount followers',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: isDark
                                    ? AppTheme.darkTextMuted
                                    : AppTheme.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Follow button
                  GestureDetector(
                    onTap: () => _toggleDepartmentFollow(account.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isFollowing ? Colors.transparent : account.color,
                        border: isFollowing
                            ? Border.all(color: account.color, width: 1.5)
                            : null,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isFollowing ? 'Following' : 'Follow',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isFollowing ? account.color : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(bool isDark) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        const Center(
          child: BrandedLoader(
            compact: true,
            showQuotes: false,
            message: 'Loading notices...',
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(5, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Shimmer.fromColors(
              baseColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[300]!,
              highlightColor: isDark
                  ? const Color(0xFF3D3D3D)
                  : Colors.grey[100]!,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 120, height: 12, color: Colors.white),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _loadNotices();
  }

  Widget _buildDateFilterHeader(bool isDark) {
    if (_startDate == null || _endDate == null) return const SizedBox.shrink();

    final startStr = DateFormat.yMd().format(_startDate!);
    final endStr = DateFormat.yMd().format(_endDate!);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? Colors.white10 : Colors.grey.shade200,
      child: Row(
        children: [
          Icon(Icons.filter_list_rounded, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            "Filtering: $startStr - $endStr",
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _clearDateFilter,
            child: Text(
              'Clear',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon/app_icon.png',
                width: 64,
                height: 64,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                'No notices found',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              if (_startDate != null)
                Text(
                  'Try clearing the date filter',
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _followErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('row-level security') ||
        message.contains('unauthorized')) {
      return 'Follow is not available right now. Please sign in again.';
    }
    return 'Failed to update follow status.';
  }
}
