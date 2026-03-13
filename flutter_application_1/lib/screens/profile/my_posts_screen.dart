import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../../utils/profile_photo_utils.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/user_badge.dart';
import '../chatroom/post_detail_screen.dart';

class MyPostsScreen extends StatefulWidget {
  final String userEmail;
  final String collegeDomain;

  const MyPostsScreen({
    super.key,
    required this.userEmail,
    required this.collegeDomain,
  });

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  final SupabaseService _supabaseService = SupabaseService();

  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final email = widget.userEmail.trim();
    if (email.isEmpty) {
      if (mounted) {
        setState(() {
          _posts = const [];
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final posts = await _supabaseService.getUserPostsAcrossRooms(email);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('MyPostsScreen._loadPosts error: $e');
      if (!mounted) return;
      setState(() {
        _posts = const [];
        _isLoading = false;
        _errorMessage = 'Failed to load your posts. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(
          'My Posts',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPosts,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadPosts,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : _posts.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.62,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.dynamic_feed_outlined,
                          size: 64,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No posts yet',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  return _buildPostCard(post, isDark);
                },
              ),
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, bool isDark) {
    final content = (post['content'] ?? '').toString();
    final roomName = (post['room_name'] ?? '').toString().trim();
    final roomId = (post['room_id'] ?? '').toString().trim();
    final authorName =
        (post['author_name'] ?? post['author_email'] ?? 'You').toString();
    final authorEmail = (post['author_email'] ?? widget.userEmail)
        .toString()
        .trim();
    final authorPhoto = resolveProfilePhotoUrl(post) ?? '';
    final hasPhoto = authorPhoto.isNotEmpty;
    final createdAt = DateTime.tryParse(post['created_at']?.toString() ?? '');
    final createdLabel = createdAt == null
        ? ''
        : DateFormat('dd MMM yyyy, hh:mm a').format(createdAt.toLocal());

    final lines = content.split('\n');
    String title = '';
    String body = content;
    if (lines.isNotEmpty && lines.first.trim().isNotEmpty) {
      title = lines.first.trim();
      body = lines.skip(1).join('\n').trim();
    }

    return GestureDetector(
      onTap: () {
        final postId = (post['id'] ?? '').toString().trim();
        if (postId.isEmpty) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(
              post: Map<String, dynamic>.from(post),
              userEmail: widget.userEmail,
              collegeDomain: widget.collegeDomain,
              roomId: roomId,
              isRoomAdmin: false,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  radius: 12,
                  displayName: authorName,
                  photoUrl: hasPhoto ? authorPhoto : null,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      if (authorEmail.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        UserBadge(email: authorEmail, size: 12),
                      ],
                    ],
                  ),
                ),
                if (createdLabel.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    createdLabel,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ],
            ),
            if (roomName.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  roomName,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
            if (title.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
