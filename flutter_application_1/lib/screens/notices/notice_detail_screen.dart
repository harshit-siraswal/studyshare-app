import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Stickers handled via file_picker in CommentInputBox
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../models/department_account.dart';
import '../profile/user_profile_screen.dart';
import '../../widgets/comment_input_box.dart';
import '../../services/cloudinary_service.dart';
import '../../utils/sticker_comment_codec.dart';
import '../../widgets/full_screen_image_viewer.dart';
import '../../widgets/emoji_reactions.dart';
import 'department_account_screen.dart';

class NoticeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> notice;
  final DepartmentAccount account;
  final String collegeId;

  const NoticeDetailScreen({
    super.key,
    required this.notice,
    required this.account,
    required this.collegeId,
  });

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _commentFocusNode = FocusNode();

  List<Map<String, dynamic>> _comments = [];
  List<String> _mediaUrls = [];
  bool _isLoading = true;
  bool _isPosting = false;
  bool _isSaved = false;

  // Reply state
  String? _replyToId;
  String? _replyToName;
  bool _isReadOnly = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _supabaseService.attachContext(context);
    });
    _initReadOnly();
    _extractMedia();
    _loadComments();
    _checkSavedStatus();
  }

  Future<void> _initReadOnly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final domain = prefs.getString('selectedCollegeDomain') ?? '';
      final email = _authService.userEmail ?? '';

      // If no domain set or no email, user can still comment if they're authenticated
      if (email.isEmpty) {
        _isReadOnly = true;
      } else if (domain.isEmpty) {
        // If no domain selected but user is logged in, allow commenting
        _isReadOnly = false;
      } else {
        // Check if email ends with @domain or just domain
        final domainToCheck = domain.startsWith('@') ? domain : '@$domain';
        _isReadOnly = !email.toLowerCase().endsWith(
          domainToCheck.toLowerCase(),
        );
      }
      if (mounted) setState(() {});
    } catch (_) {
      // On error, allow commenting if user is authenticated
      _isReadOnly = _authService.userEmail == null;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  void _extractMedia() {
    final List<String> urls = [];
    // Check for single image
    if (widget.notice['image_url'] != null &&
        widget.notice['image_url'].toString().isNotEmpty) {
      urls.add(widget.notice['image_url']);
    }
    // Check for media array
    if (widget.notice['media_urls'] != null) {
      if (widget.notice['media_urls'] is List) {
        for (var url in widget.notice['media_urls']) {
          if (url != null && url.toString().isNotEmpty) {
            urls.add(url.toString());
          }
        }
      }
    }
    setState(() {
      _mediaUrls = urls.toSet().toList(); // Remove duplicates
    });
  }

  Future<void> _checkSavedStatus() async {
    final email = _authService.userEmail;
    if (email == null) return;

    final saved = await _supabaseService.isNoticeSaved(
      widget.notice['id'].toString(),
      email,
    );
    if (mounted) {
      setState(() => _isSaved = saved);
    }
  }

  Future<void> _toggleSaved() async {
    final email = _authService.userEmail;
    if (email == null) {
      _showFeedback('You must be signed in to save notices');
      return;
    }

    try {
      if (_isSaved) {
        await _supabaseService.unsaveNotice(
          widget.notice['id'].toString(),
          email,
        );
        if (mounted) setState(() => _isSaved = false);
      } else {
        await _supabaseService.saveNotice(
          widget.notice['id'].toString(),
          email,
        );
        if (mounted) {
          setState(() => _isSaved = true);
          _showFeedback('Notice saved to bookmarks');
        }
      }
    } catch (e) {
      debugPrint('Error updating bookmark: $e');
      _showError('Unable to update bookmark');
    }
  }

  Future<void> _loadComments() async {
    try {
      final comments = await _supabaseService.getNoticeComments(
        widget.notice['id'].toString(),
      );
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Silent error or retry option could be added
      }
    }
  }

  void _initiateReply(String commentId, String userName) {
    setState(() {
      _replyToId = commentId;
      _replyToName = userName;
    });
    _commentFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyToId = null;
      _replyToName = null;
    });
    _commentFocusNode.unfocus();
  }

  void _openUserProfile(String email, String displayName) {
    if (email.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            UserProfileScreen(userEmail: email, userName: displayName),
      ),
    );
  }

  void _openDepartmentProfile() {
    if (widget.collegeId.trim().isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DepartmentAccountScreen(
          account: widget.account,
          collegeId: widget.collegeId,
        ),
      ),
    );
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final email = _authService.userEmail;
    if (email == null) {
      _showFeedback('You must be signed in to comment');
      return;
    }
    if (_isReadOnly) {
      _showFeedback(
        'Read-only users cannot comment. Use your college email to unlock.',
      );
      return;
    }

    setState(() => _isPosting = true);

    try {
      await _supabaseService.addNoticeComment(
        noticeId: widget.notice['id'].toString(),
        content: text,
        userEmail: email,
        userName: _authService.displayName ?? email.split('@')[0],
        parentId: _replyToId,
      );

      _commentController.clear();
      _cancelReply(); // Reset reply state

      await _loadComments();

      // Scroll to bottom only if it was a top-level comment
      if (_replyToId == null && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      debugPrint('Failed to post comment: $e');
      _showError('Failed to post comment. Please try again.');
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  void _showFeedback(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  String _formatTimeAgo(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }

  void _openGallery(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _MediaViewerScreen(
          galleryItems: _mediaUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Future<void> _shareAsImage() async {
    final controller = ScreenshotController();

    // Create a generated image
    try {
      final bytes = await controller.captureFromWidget(
        Material(
          color: Colors.white,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: widget.account.color,
                      radius: 20,
                      child: Text(
                        widget.account.avatarLetter,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.account.name,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          'MyStudySpace Notice',
                          style: GoogleFonts.inter(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  widget.notice['title'] ?? 'Untitled',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                // Content
                Text(
                  widget.notice['content'] ?? '',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFF334155),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 30),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'via MyStudySpace',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatTimeAgo(widget.notice['created_at']),
                      style: GoogleFonts.inter(color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        delay: const Duration(milliseconds: 50),
        pixelRatio: 2.0,
      );

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/notice_share.png').create();
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Check out this notice on MyStudySpace!');
    } catch (e) {
      debugPrint('Failed to generate image: $e');
      _showError('Failed to generate image');
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

    final title = widget.notice['title'] ?? 'Untitled';
    final content = widget.notice['content'] ?? '';
    final createdAt = widget.notice['created_at'];

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkBackground : Colors.white,
        title: Text('Notice Details', style: TextStyle(color: textColor)),
        leading: BackButton(color: textColor),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            ),
            color: _isSaved ? AppTheme.primary : textColor,
            onPressed: _toggleSaved,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            color: textColor,
            onPressed: _shareAsImage,
          ),
        ],
      ),
      body: Hero(
        tag: 'notice_card_${widget.notice['id']}',
        flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
          return Material(
            color: Colors.transparent,
            child: toHeroContext.widget,
          );
        },
        child: Material(
          color: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
          child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                // Notice Header (Author Info)
                _buildAuthorHeader(textColor, secondaryColor, createdAt),
                const SizedBox(height: 20),

                // Title
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),

                // Content Body
                SelectableLinkify(
                  onOpen: (link) async {
                    try {
                      final uri = Uri.tryParse(link.url);
                      if (uri == null) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not open: ${link.url}')),
                          );
                        }
                        return;
                      }
                      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                      if (!launched && mounted) {
                        _showError('Could not open link');
                      }
                    } catch (e) {
                      debugPrint('Failed to launch URL: $e');
                      if (mounted) {
                        _showError('Unable to open link');
                      }
                    }
                  },
                  text: content,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF334155),
                    height: 1.6,
                  ),
                  linkStyle: GoogleFonts.inter(
                    fontSize: 16,
                    color: AppTheme.primary,
                    decoration: TextDecoration.underline,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 20),

                // Media Gallery
                if (_mediaUrls.isNotEmpty) ...[
                  _buildMediaGallery(),
                  const SizedBox(height: 24),
                ],

                Divider(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
                const SizedBox(height: 16),

                // Comments Section Header
                Text(
                  'Comments (${_comments.length} threads)',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 16),

                // Comments List
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: secondaryColor.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No comments yet.\nBe the first to start the discussion!',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: secondaryColor),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._comments.map(
                    (c) =>
                        _buildCommentTree(c, isDark, textColor, secondaryColor),
                  ),

                const SizedBox(height: 20),
              ],
            ),
          ),

          // Comment Input Area
          SafeArea(
            top: false,
            child: _buildInputArea(isDark, textColor, secondaryColor),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildAuthorHeader(
    Color textColor,
    Color secondaryColor,
    String? createdAt,
  ) {
    return Row(
      children: [
        InkWell(
          onTap: _openDepartmentProfile,
          borderRadius: BorderRadius.circular(24),
          child: CircleAvatar(
            backgroundColor: widget.account.color,
            radius: 20,
            child: Text(
              widget.account.avatarLetter,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: _openDepartmentProfile,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.account.name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.verified, size: 14, color: AppTheme.primary),
                  ],
                ),
                Text(
                  _formatTimeAgo(createdAt),
                  style: GoogleFonts.inter(color: secondaryColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaGallery() {
    if (_mediaUrls.isEmpty) return const SizedBox.shrink();

    if (_mediaUrls.length == 1) {
      return GestureDetector(
        onTap: () => _openGallery(0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Hero(
            tag: 'media_${_mediaUrls[0]}',
            child: CachedNetworkImage(
              imageUrl: _mediaUrls[0],
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (context, url) => Container(
                height: 200,
                color: Colors.grey.withValues(alpha: 0.1),
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                height: 200,
                color: Colors.grey.withValues(alpha: 0.1),
                child: const Icon(Icons.error),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _mediaUrls.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _openGallery(index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Hero(
                  tag: 'media_${_mediaUrls[index]}',
                  child: CachedNetworkImage(
                    imageUrl: _mediaUrls[index],
                    height: 200,
                    width: 200,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 200,
                      color: Colors.grey.withValues(alpha: 0.1),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCommentTree(
    Map<String, dynamic> comment,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    // Backend returns a flat list of comments with 'parent_id'.
    // The getNoticeComments method already converts this into a nested structure with a 'replies' list.
    // So here we assume each comment map has a 'replies' key containing a List<Map<String, dynamic>>.

    // Check for replies array
    final replies =
        (comment['replies'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCommentItem(comment, isDark, textColor, secondaryColor),
        if (replies.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isDark ? Colors.white24 : Colors.black12,
                  width: 1.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: replies
                  .map(
                    (r) =>
                        _buildCommentTree(r, isDark, textColor, secondaryColor),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildCommentItem(
    Map<String, dynamic> comment,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    final senderName = comment['user_name'] ?? 'Unknown';
    final content = comment['content'] ?? '';
    final createdAt = comment['created_at'];
    final commentId = comment['id']?.toString() ?? '';
    final userEmail = comment['user_email'] ?? '';
    final dismissKey = commentId.isNotEmpty
        ? commentId
        : '${createdAt?.toString() ?? DateTime.now().microsecondsSinceEpoch}-${senderName.hashCode}';

    return Dismissible(
      key: ValueKey('notice-comment-$dismissKey'),
      direction: commentId.isEmpty
          ? DismissDirection.none
          : DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.22},
      confirmDismiss: (_) async {
        if (commentId.isEmpty) return false;
        _initiateReply(commentId, senderName.toString());
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.reply_rounded, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              'Reply',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: userEmail.isEmpty
                  ? null
                  : () => _openUserProfile(
                      userEmail.toString(),
                      senderName.toString(),
                    ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                child: Text(
                  senderName.toString().isNotEmpty
                      ? senderName.toString()[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: userEmail.isEmpty
                            ? null
                            : () => _openUserProfile(
                                userEmail.toString(),
                                senderName.toString(),
                              ),
                        child: Text(
                          senderName.toString(),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTimeAgo(createdAt),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: secondaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildCommentContent(
                    content.toString(),
                    isDark,
                    textColor,
                    commentId,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: EmojiReactions(
                          commentId: commentId,
                          commentType: 'notice',
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          if (commentId.isNotEmpty) {
                            _initiateReply(commentId, senderName.toString());
                          }
                        },
                        child: Text(
                          'Reply',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: secondaryColor,
                          ),
                        ),
                      ),
                      if (userEmail.toString().isNotEmpty) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _openUserProfile(
                            userEmail.toString(),
                            senderName.toString(),
                          ),
                          child: Text(
                            'View Profile',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: secondaryColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentContent(
    String rawContent,
    bool isDark,
    Color textColor,
    String commentId,
  ) {
    final stickerUrl = StickerCommentCodec.extractUrl(rawContent);
    if (stickerUrl != null) {
      final heroTag = 'notice_sticker_${commentId}_$stickerUrl';
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  FullScreenImageViewer(imageUrl: stickerUrl, heroTag: heroTag),
            ),
          );
        },
        child: Hero(
          tag: heroTag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: stickerUrl,
              width: 150,
              height: 150,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 150,
                height: 150,
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) {
                return Text(
                  rawContent,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: textColor.withValues(alpha: 0.9),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    return Text(
      rawContent,
      style: GoogleFonts.inter(
        fontSize: 14,
        color: textColor.withValues(alpha: 0.9),
      ),
    );
  }

  Future<void> _handleStickerSelection(File stickerFile) async {
    if (_isReadOnly) return;

    setState(() => _isPosting = true);

    // Save reply ID before clearing it
    final String? parentId = _replyToId;

    try {
      final bytes = await stickerFile.readAsBytes();
      final filename = 'sticker_${DateTime.now().millisecondsSinceEpoch}.png';

      final url = await CloudinaryService.uploadBytes(bytes, filename);

      if (_authService.userEmail == null) throw Exception('User not signed in');

      await _supabaseService.addNoticeComment(
        noticeId: widget.notice['id'].toString(),
        content: StickerCommentCodec.encode(url),
        userEmail: _authService.userEmail!,
        userName:
            _authService.displayName ?? _authService.userEmail!.split('@')[0],
        parentId: parentId,
      );

      _cancelReply();
      await _loadComments();

      if (parentId == null && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      _showFeedback('Failed to post sticker: $e');
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Widget _buildInputArea(bool isDark, Color textColor, Color secondaryColor) {
    return CommentInputBox(
      controller: _commentController,
      focusNode: _commentFocusNode,
      isReadOnly: _isReadOnly,
      isSubmitting: _isPosting,
      replyToName: _replyToName,
      onCancelReply: _cancelReply,
      onSubmit: _postComment,
      onStickerSelected: _handleStickerSelection,
      hintText: _replyToName != null
          ? 'Write your reply...'
          : 'Add a comment...',
    );
  }
}

class _MediaViewerScreen extends StatelessWidget {
  final List<String> galleryItems;
  final int initialIndex;

  const _MediaViewerScreen({required this.galleryItems, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Colors.white),
      ),
      body: PhotoViewGallery.builder(
        scrollPhysics: const BouncingScrollPhysics(),
        builder: (BuildContext context, int index) {
          return PhotoViewGalleryPageOptions(
            imageProvider: CachedNetworkImageProvider(galleryItems[index]),
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
            heroAttributes: PhotoViewHeroAttributes(
              tag: 'media_${galleryItems[index]}',
            ),
          );
        },
        itemCount: galleryItems.length,
        loadingBuilder: (context, event) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        pageController: PageController(initialPage: initialIndex),
      ),
    );
  }
}
