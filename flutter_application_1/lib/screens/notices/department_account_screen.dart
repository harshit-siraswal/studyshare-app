import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/notice_card.dart';
import '../../models/department_account.dart';
import '../../utils/admin_access.dart';

class DepartmentAccountScreen extends StatefulWidget {
  final DepartmentAccount account;
  final String collegeId;

  const DepartmentAccountScreen({
    super.key,
    required this.account,
    required this.collegeId,
  });

  @override
  State<DepartmentAccountScreen> createState() =>
      _DepartmentAccountScreenState();
}

class _DepartmentAccountScreenState extends State<DepartmentAccountScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final BackendApiService _backendApiService = BackendApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _notices = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  int _followerCount = 0;
  bool _isFollowLoading = true;
  bool _canManageNotices = false;
  bool _showSearchBar = false;
  String _searchQuery = '';
  DateTimeRange? _selectedDateRange;

  Future<void> _loadNoticeAccess() async {
    try {
      final profile = await _supabaseService.getCurrentUserProfile(
        maxAttempts: 2,
      );
      final canManage =
          isTeacherOrAdminProfile(profile) ||
          hasAdminCapability(profile, 'upload_notice');
      if (!mounted) return;
      setState(() => _canManageNotices = canManage);
    } catch (e) {
      debugPrint('Failed to resolve notice access: $e');
    }
  }

  Future<void> _loadAccessContextAndNotices() async {
    await _loadNoticeAccess();
    await _loadDepartmentNotices();
  }

  @override
  void initState() {
    super.initState();
    _loadAccessContextAndNotices();
    _loadFollowData();
  }

  Future<void> _loadFollowData() async {
    final email = _authService.userEmail;
    if (email == null) {
      if (mounted) {
        setState(() => _isFollowLoading = false);
      }
      return;
    }
    try {
      final isFollowing = await _supabaseService.isFollowingDepartment(
        widget.account.id,
        email,
        collegeId: widget.collegeId,
      );
      final count = await _supabaseService.getDepartmentFollowerCount(
        widget.account.id,
        widget.collegeId,
      );

      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
          _followerCount = count;
          _isFollowLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading follow data: $e');
      if (mounted) {
        setState(() => _isFollowLoading = false);
      }
    }
  }

  Future<void> _toggleFollow() async {
    final email = _authService.userEmail;
    if (email == null) return;

    setState(() => _isFollowLoading = true);

    try {
      if (_isFollowing) {
        await _supabaseService.unfollowDepartment(
          widget.account.id,
          email,
          collegeId: widget.collegeId,
        );
        setState(() {
          _isFollowing = false;
          _followerCount--;
        });
      } else {
        await _supabaseService.followDepartment(
          widget.account.id,
          widget.collegeId,
          email,
        );
        setState(() {
          _isFollowing = true;
          _followerCount++;
        });
      }

      // Verify and sync the actual count from the server after either action.
      if (mounted) {
        try {
          final actualCount = await _supabaseService.getDepartmentFollowerCount(
            widget.account.id,
            widget.collegeId,
          );
          if (mounted) {
            setState(() {
              _followerCount = actualCount;
            });
          }
        } catch (countError) {
          debugPrint('Error syncing follower count: $countError');
        }
      }
    } catch (e) {
      debugPrint('Department follow update failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_followErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<void> _loadDepartmentNotices() async {
    try {
      // Fetch only notices for this department via backend query param —
      // avoids loading all notices and filtering in-memory.
      final departmentNotices = await _backendApiService.getNotices(
        widget.collegeId,
        department: widget.account.id,
      );

      if (!mounted) return;
      setState(() {
        _notices = departmentNotices;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading department notices: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _filteredDepartmentNotices() {
    Iterable<Map<String, dynamic>> filtered = _notices;

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((notice) {
        final title = (notice['title'] ?? '').toString().toLowerCase();
        final content = (notice['content'] ?? '').toString().toLowerCase();
        final creator = (notice['created_by'] ?? '').toString().toLowerCase();
        return title.contains(query) ||
            content.contains(query) ||
            creator.contains(query);
      });
    }

    if (_selectedDateRange != null) {
      filtered = filtered.where((notice) {
        final createdAt = DateTime.tryParse(
          notice['created_at']?.toString() ?? '',
        );
        if (createdAt == null) return false;
        final start = DateTime(
          _selectedDateRange!.start.year,
          _selectedDateRange!.start.month,
          _selectedDateRange!.start.day,
        );
        final end = DateTime(
          _selectedDateRange!.end.year,
          _selectedDateRange!.end.month,
          _selectedDateRange!.end.day,
          23,
          59,
          59,
        );
        return !createdAt.isBefore(start) && !createdAt.isAfter(end);
      });
    }

    return filtered.toList();
  }

  Future<void> _pickNoticeDateRange(bool isDark) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
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

    if (!mounted || picked == null) return;
    setState(() => _selectedDateRange = picked);
  }

  Widget _buildDepartmentSearchBar(bool isDark, Color secondaryColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: GoogleFonts.inter(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: 'Search notices in ${widget.account.name}',
          hintStyle: GoogleFonts.inter(fontSize: 14, color: secondaryColor),
          filled: true,
          fillColor: isDark
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.04),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: secondaryColor,
            size: 20,
          ),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: Icon(Icons.close_rounded, color: secondaryColor),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(
              color: AppTheme.primary.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final secondaryColor = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final bgColor = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final followBgColor = _isFollowing
        ? Colors.transparent
        : (isDark ? Colors.white : Colors.black);
    final followTextColor = _isFollowing
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? Colors.black : Colors.white);
    final visibleNotices = _filteredDepartmentNotices();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: _showSearchBar ? 'Hide search' : 'Search notices',
            icon: Icon(
              _showSearchBar ? Icons.close_rounded : Icons.search_rounded,
              color: textColor,
            ),
            onPressed: () {
              setState(() {
                _showSearchBar = !_showSearchBar;
                if (!_showSearchBar) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          IconButton(
            tooltip: _selectedDateRange != null
                ? 'Clear date filter'
                : 'Filter by date',
            icon: Icon(
              _selectedDateRange != null
                  ? Icons.event_busy_rounded
                  : Icons.calendar_month_rounded,
              color: _selectedDateRange != null ? AppTheme.primary : textColor,
            ),
            onPressed: () async {
              if (_selectedDateRange != null) {
                setState(() => _selectedDateRange = null);
                return;
              }
              await _pickNoticeDateRange(isDark);
            },
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Profile Header Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: widget.account.color,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            widget.account.avatarLetter,
                            style: GoogleFonts.inter(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Follow Button
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          height: 36,
                          child: ElevatedButton(
                            onPressed: _isFollowLoading ? null : _toggleFollow,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: followBgColor,
                              foregroundColor: followTextColor,
                              elevation: 0,
                              side: _isFollowing
                                  ? BorderSide(
                                      color: isDark
                                          ? Colors.white30
                                          : Colors.black26,
                                    )
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                            ),
                            child: _isFollowLoading
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        followTextColor,
                                      ),
                                    ),
                                  )
                                : Text(
                                    _isFollowing ? 'Following' : 'Follow',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: followTextColor,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Name & Handle
                  Row(
                    children: [
                      Text(
                        widget.account.name,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (_isFollowing)
                        Icon(Icons.verified, size: 20, color: AppTheme.primary),
                    ],
                  ),
                  Text(
                    widget.account.handle,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: secondaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Stats
                  Row(
                    children: [
                      _buildXStat(
                        _followerCount.toString(),
                        'Followers',
                        textColor,
                        secondaryColor,
                      ),
                      const SizedBox(width: 16),
                      _buildXStat(
                        '${_notices.length}',
                        'Notices',
                        textColor,
                        secondaryColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _showSearchBar
                        ? _buildDepartmentSearchBar(isDark, secondaryColor)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),

          // Notices List
          if (_isLoading)
            SliverToBoxAdapter(child: _buildLoadingSkeleton(isDark))
          else if (visibleNotices.isEmpty)
            SliverToBoxAdapter(
              child: _buildEmptyState(isDark, textColor, secondaryColor),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => NoticeCard(
                  notice: visibleNotices[index],
                  account: widget.account,
                  collegeId: widget.collegeId,
                  isDark: isDark,
                  canManage: _canManageNotices,
                  onNoticeUpdated: _loadAccessContextAndNotices,
                ),
                childCount: visibleNotices.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildXStat(
    String value,
    String label,
    Color textColor,
    Color secondaryColor,
  ) {
    return Row(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(color: secondaryColor)),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark, Color textColor, Color secondaryColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 48,
              color: secondaryColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No notices yet',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'This department hasn\'t posted any notices',
              style: GoogleFonts.inter(fontSize: 13, color: secondaryColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          3,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Shimmer.fromColors(
              baseColor: isDark ? AppTheme.darkCard : Colors.grey.shade200,
              highlightColor: isDark
                  ? AppTheme.darkBorder
                  : Colors.grey.shade100,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _followErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('row-level security') ||
        message.contains('unauthorized')) {
      return 'Follow is not available right now. Please sign in again.';
    }
    if (message.contains('college context') ||
        message.contains('college id is required')) {
      return 'Follow needs your college profile. Please refresh your profile and try again.';
    }
    return 'Could not update follow status right now.';
  }
}
