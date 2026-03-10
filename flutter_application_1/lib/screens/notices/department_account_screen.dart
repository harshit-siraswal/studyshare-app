import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/notice_card.dart';
import '../../models/department_account.dart';

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
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _notices = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  int _followerCount = 0;
  bool _isFollowLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDepartmentNotices();
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
    }  }

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
      final departmentId = widget.account.id;
      final allNotices = await _supabaseService.getNotices(
        collegeId: widget.collegeId,
      );
      final departmentNotices = allNotices.where((notice) {
        final noticeDepartment =
            (notice['department'] ?? notice['department_id'] ?? '')
                .toString()
                .trim();
        return noticeDepartment == departmentId;
      }).toList();

      if (!mounted) return;
      setState(() {
        _notices = departmentNotices;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
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

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
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
                ],
              ),
            ),
          ),

          // Notices List
          if (_isLoading)
            SliverToBoxAdapter(child: _buildLoadingSkeleton(isDark))
          else if (_notices.isEmpty)
            SliverToBoxAdapter(
              child: _buildEmptyState(isDark, textColor, secondaryColor),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => NoticeCard(
                  notice: _notices[index],
                  account: widget.account,
                  collegeId: widget.collegeId,
                  isDark: isDark,
                ),
                childCount: _notices.length,
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
    return 'Could not update follow status right now.';
  }
}
