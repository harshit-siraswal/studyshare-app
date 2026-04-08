import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../../widgets/user_avatar.dart';
import 'user_profile_screen.dart';

class ExploreStudentsScreen extends StatefulWidget {
  final String userEmail;
  final String? collegeId;
  final String? collegeName;
  final String? collegeDomain;

  const ExploreStudentsScreen({
    super.key,
    required this.userEmail,
    this.collegeId,
    this.collegeName,
    this.collegeDomain,
  });

  @override
  State<ExploreStudentsScreen> createState() => _ExploreStudentsScreenState();
}

class _ExploreStudentsScreenState extends State<ExploreStudentsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> profile = const <String, dynamic>{};
      try {
        profile = await _supabaseService.getCurrentUserProfile(
          maxAttempts: 1,
        );
      } catch (e) {
        debugPrint(
          'Failed to resolve current profile for student discovery: $e',
        );
      }

      final resolvedCollegeId = (widget.collegeId?.trim().isNotEmpty ?? false)
          ? widget.collegeId!.trim()
          : profile['college_id']?.toString().trim() ?? '';
      final fallbackCollegeHint =
          (widget.collegeDomain?.trim().isNotEmpty ?? false)
          ? widget.collegeDomain!.trim()
          : (widget.userEmail.contains('@')
            ? widget.userEmail.split('@').last.trim()
            : '');
      final profileCollege = profile['college']?.toString().trim() ?? '';
      final resolvedCollege = (widget.collegeName?.trim().isNotEmpty ?? false)
          ? widget.collegeName!.trim()
          : profileCollege.isNotEmpty
          ? profileCollege
          : fallbackCollegeHint;
      final students = await _supabaseService.discoverUsers(
        query: _searchQuery,
        limit: 50,
        collegeId: resolvedCollegeId.isNotEmpty ? resolvedCollegeId : null,
        college: resolvedCollege.isNotEmpty ? resolvedCollege : null,
      );

      final currentUserEmail = widget.userEmail.trim().toLowerCase();
      final allowedDomain = ((widget.collegeDomain?.trim().isNotEmpty ?? false)
              ? widget.collegeDomain!.trim()
              : (widget.userEmail.contains('@')
                    ? widget.userEmail.split('@').last.trim()
                    : ''))
          .toLowerCase()
          .replaceAll('@', '');
      final filtered = students.where((student) {
        final emailValue = student['email'];
        if (emailValue is! String) return false;
        final email = emailValue.trim().toLowerCase();
        if (email.isEmpty || email == currentUserEmail) return false;
        if (allowedDomain.isNotEmpty && !email.endsWith('@$allowedDomain')) {
          return false;
        }
        return true;
      }).toList();

      if (mounted) {
        setState(() {
          _students = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load students: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load students')),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();

    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = query);
        _loadStudents();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final textColor = isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightSurface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Explore Students',
          style: GoogleFonts.inter(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: GoogleFonts.inter(color: textColor),
              decoration: InputDecoration(
                hintText: 'Search by name or username...',
                hintStyle: GoogleFonts.inter(
                  color: isDark
                      ? AppTheme.darkTextMuted
                      : AppTheme.lightTextMuted,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark
                      ? AppTheme.darkTextMuted
                      : AppTheme.lightTextMuted,
                ),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                ? Center(
                    child: Text(
                      'No students found',
                      style: GoogleFonts.inter(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _students.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final student = _students[index];
                      return _buildStudentCard(student, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student, bool isDark) {
    final photoUrl = student['profile_photo_url'];
    final hasValidPhoto =
        photoUrl != null && photoUrl.toString().isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        final email = student['email'] as String?;
        final userName = student['display_name'] as String?;
        final userPhotoUrl = student['profile_photo_url'] as String?;

        if (email == null || email.trim().isEmpty) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(
              userEmail: email.trim(),
              userName: userName,
              userPhotoUrl: userPhotoUrl,
            ),
          ),
        );
      },
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.lightSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            UserAvatar(
              photoUrl: hasValidPhoto ? photoUrl : null,
              radius: 24,
              displayName: student['display_name'] ?? 'User',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student['display_name'] ?? 'Unknown',
                    style: GoogleFonts.inter(
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.lightTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  if (student['username'] != null)
                    Text(
                      '@${student['username']}',
                      style: GoogleFonts.inter(
                        color: isDark
                            ? AppTheme.darkTextMuted
                            : AppTheme.lightTextMuted,
                        fontSize: 14,
                      ),
                    ),
                  if (student['bio'] != null &&
                      student['bio'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        student['bio'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: isDark
                              ? AppTheme.darkTextMuted
                              : AppTheme.lightTextMuted,
                          fontSize: 13,
                        ),
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
}
