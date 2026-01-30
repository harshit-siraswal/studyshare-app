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
  State<DepartmentAccountScreen> createState() => _DepartmentAccountScreenState();
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
    if (email == null) return;
    
    try {
      final isFollowing = await _supabaseService.isFollowingDepartment(
        widget.account.id, 
        email
      );
      final count = await _supabaseService.getDepartmentFollowerCount(
        widget.account.id,
        widget.collegeId
      );
      
      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
          _followerCount = count;
          _isFollowLoading = false;
        });
      }
    } catch (e) {
      print('Error loading follow data: $e');
    }
  }
  
  Future<void> _toggleFollow() async {
    final email = _authService.userEmail;
    if (email == null) return;
    
    setState(() => _isFollowLoading = true);
    
    try {
      if (_isFollowing) {
        await _supabaseService.unfollowDepartment(widget.account.id, email);
        setState(() {
          _isFollowing = false;
          _followerCount--;
        });
      } else {
        await _supabaseService.followDepartment(widget.account.id, widget.collegeId, email);
        setState(() {
          _isFollowing = true;
          _followerCount++;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<void> _loadDepartmentNotices() async {
    try {
      final allNotices = await _supabaseService.getNotices(
        collegeId: widget.collegeId,
      );
      
      // Filter by department
      final deptNotices = allNotices.where((n) => 
        n['department']?.toString().toLowerCase() == widget.account.id.toLowerCase()
      ).toList();
      
      setState(() {
        _notices = deptNotices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final secondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final bgColor = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    
    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // App Bar with department header
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: widget.account.color,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.account.color,
                      widget.account.color.withOpacity(0.8),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      // Avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            widget.account.avatarLetter,
                            style: GoogleFonts.inter(
                              fontSize: widget.account.avatarLetter.length > 1 ? 24 : 32,
                              fontWeight: FontWeight.bold,
                              color: widget.account.color,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.account.name,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.account.handle,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Follow Button
                      SizedBox(
                        height: 36,
                        child: ElevatedButton(
                          onPressed: _isFollowLoading ? null : _toggleFollow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isFollowing ? Colors.transparent : Colors.white,
                            foregroundColor: _isFollowing ? Colors.white : widget.account.color,
                            elevation: _isFollowing ? 0 : 2,
                            side: _isFollowing ? const BorderSide(color: Colors.white, width: 1.5) : null,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                          ),
                          child: _isFollowLoading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  _isFollowing ? 'Following' : 'Follow',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
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
          
          // Stats bar
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: cardColor,
                border: Border(
                  bottom: BorderSide(color: borderColor),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStat(_notices.length.toString(), 'Notices', textColor, secondaryColor),
                  _buildStat(_followerCount.toString(), 'Followers', textColor, secondaryColor),
                  _buildStat('Active', 'Status', textColor, secondaryColor),
                ],
              ),
            ),
          ),
          
          // Header for notices
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Recent Notices',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_notices.length} total',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: secondaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Notices list
          _isLoading
              ? SliverToBoxAdapter(child: _buildLoadingSkeleton(isDark))
              : _notices.isEmpty
                  ? SliverToBoxAdapter(child: _buildEmptyState(isDark, textColor, secondaryColor))
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => NoticeCard(
                          notice: _notices[index],
                          account: widget.account,
                          isDark: isDark,
                        ),
                        childCount: _notices.length,
                      ),
                    ),
          
          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label, Color textColor, Color secondaryColor) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: secondaryColor,
          ),
        ),
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
              color: secondaryColor.withOpacity(0.5),
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
              style: GoogleFonts.inter(
                fontSize: 13,
                color: secondaryColor,
              ),
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
        children: List.generate(3, (index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Shimmer.fromColors(
            baseColor: isDark ? AppTheme.darkCard : Colors.grey.shade200,
            highlightColor: isDark ? AppTheme.darkBorder : Colors.grey.shade100,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        )),
      ),
    );
  }
}
