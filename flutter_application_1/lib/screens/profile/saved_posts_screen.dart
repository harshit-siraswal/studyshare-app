import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../chatroom/post_detail_screen.dart';
import 'package:intl/intl.dart';

class SavedPostsScreen extends StatefulWidget {
  final String userEmail;

  const SavedPostsScreen({super.key, required this.userEmail});

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _savedPosts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedPosts();
  }

  Future<void> _loadSavedPosts() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final email = widget.userEmail.trim().isNotEmpty
        ? widget.userEmail.trim()
        : (_authService.userEmail ?? '').trim();
    if (email.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final posts = await _supabaseService.getSavedPosts(email);
      if (mounted) {
        setState(() {
          _savedPosts = posts;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('SavedPostsScreen._loadSavedPosts error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load saved posts. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(
          'Saved Posts',
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                      onPressed: _loadSavedPosts,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _savedPosts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 64,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No saved posts yet',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _savedPosts.length,
              itemBuilder: (context, index) {
                final post = _savedPosts[index];
                return _buildSavedPostCard(post, isDark);
              },
            ),
    );
  }

  Widget _buildSavedPostCard(Map<String, dynamic> post, bool isDark) {
    final content = (post['content'] ?? '').toString();
    final authorName = (post['author_name'] ?? post['authorName'] ?? 'Unknown')
        .toString();
    final createdRaw =
        post['_saved_at'] ??
        post['savedAt'] ??
        post['created_at'] ??
        post['postedAt'] ??
        '';
    final createdAt =
        DateTime.tryParse(createdRaw.toString()) ?? DateTime.now();
    final timeAgo = _formatTimeAgo(createdAt);

    // Extract title if present (first line)
    String title = '';
    String body = content;
    final lines = content.split('\n');
    if (lines.isNotEmpty && lines[0].length < 100) {
      title = lines[0];
      body = lines.skip(1).join('\n').trim();
    }

    return GestureDetector(
      onTap: () {
        final postId =
            (post['id'] ?? post['message_id'] ?? post['messageId'] ?? '')
                .toString()
                .trim();
        if (postId.isEmpty) return;

        // We need collegeDomain for PostDetailScreen.
        // We can try to infer it or just pass empty if not actively used for view.
        // Assuming user is logged in, we can use their domain or fetch the college.
        // For simplicity, passing a placeholder or extracting from user email if available.
        final userEmail = widget.userEmail.trim().isNotEmpty
            ? widget.userEmail.trim()
            : (_authService.userEmail ?? '');
        final domain = userEmail.isNotEmpty && userEmail.contains('@')
            ? userEmail.split('@').last
            : '';
        final roomId =
            (post['_saved_room_id'] ?? post['room_id'] ?? post['roomId'] ?? '')
                .toString()
                .trim();
        final normalizedPost = <String, dynamic>{
          ...post,
          'id': postId,
          'room_id': roomId,
        };

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(
              post: normalizedPost,
              userEmail: userEmail,
              collegeDomain: domain,
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
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.primary,
                  child: Text(
                    authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  authorName,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  timeAgo,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (title.isNotEmpty)
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (title.isNotEmpty && body.isNotEmpty) const SizedBox(height: 6),
            if (body.isNotEmpty)
              Text(
                body,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return DateFormat('MMM d').format(date);
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
