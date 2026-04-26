import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/emoji_reactions.dart';
import '../profile/user_profile_screen.dart';
import '../../services/backend_api_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/comment_input_box.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:path/path.dart' as p;
import '../../widgets/full_screen_image_viewer.dart';
import '../../widgets/user_avatar.dart';
import '../../utils/sticker_comment_codec.dart';
import '../../widgets/user_badge.dart';
import '../../widgets/paywall_dialog.dart';
import '../../utils/profile_photo_utils.dart';
import '../../utils/link_navigation_utils.dart';
import '../../models/user.dart';

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final String userEmail;
  final String collegeDomain;
  final String roomId;
  final bool isRoomAdmin;

  const PostDetailScreen({
    super.key,
    required this.post,
    required this.userEmail,
    required this.collegeDomain,
    this.roomId = '',
    this.isRoomAdmin = false,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  static final Map<String, List<Map<String, dynamic>>> _commentCache =
      <String, List<Map<String, dynamic>>>{};

  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();
  final BackendApiService _backendApiService = BackendApiService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  static const int kMaxStickerSizeBytes = 5 * 1024 * 1024;

  // Reply state
  String? _replyToId;
  String? _replyToName;
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isSaved = false;
  int _upvotes = 0;
  int _downvotes = 0;
  int? _userVote;
  bool _isSubmitting = false;
  bool _isReadOnly = false;
  bool _hasAccessOverride = false;
  final Set<String> _expandedCommentIds = {};
  int _reactionRefreshTick = 0;
  late Map<String, dynamic> _post;
  final Map<String, String> _profilePhotoCache = {};
  final Set<String> _profilePhotoFetchInFlight = {};
  static const List<String> _quickReactions = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🔥',
  ];

  static const List<String> _privilegedDomains = ['@kiet.edu'];

  String get _commentCacheKey => widget.post['id'].toString();

  bool _isPrivilegedEmail(String email) {
    final normalized = email.trim().toLowerCase();
    return _privilegedDomains.any((domain) => normalized.endsWith(domain));
  }

  bool _emailMatchesDomain(String email, String domain) {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedDomain = domain.trim().toLowerCase().replaceAll('@', '');
    if (normalizedEmail.isEmpty || normalizedDomain.isEmpty) return false;
    return normalizedEmail.endsWith('@$normalizedDomain');
  }

  Map<String, dynamic> _cloneCommentNode(Map<String, dynamic> comment) {
    final clone = Map<String, dynamic>.from(comment);
    clone['replies'] = _safeReplyList(
      comment['replies'],
    ).map(_cloneCommentNode).toList(growable: true);
    return clone;
  }

  List<Map<String, dynamic>> _cloneCommentTree(
    List<Map<String, dynamic>> comments,
  ) {
    return comments.map(_cloneCommentNode).toList(growable: true);
  }

  void _cacheComments(List<Map<String, dynamic>> comments) {
    _commentCache[_commentCacheKey] = _cloneCommentTree(comments);
  }

  Widget _buildCommentContent(
    String content,
    bool isDark,
    Color textColor,
    String commentId,
  ) {
    final stickerUrl = StickerCommentCodec.extractUrl(content);
    if (stickerUrl != null) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FullScreenImageViewer(
                imageUrl: stickerUrl,
                heroTag: 'sticker_${stickerUrl.hashCode}_$commentId',
              ),
            ),
          );
        },
        child: Hero(
          tag: 'sticker_${stickerUrl.hashCode}_$commentId',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildStickerImage(stickerUrl, isDark, textColor),
          ),
        ),
      );
    }

    // Default text rendering
    return SelectableLinkify(
      text: content,
      onOpen: (link) async {
        try {
          final launched = await openStudyShareLink(
            context,
            rawUrl: link.url,
            title: 'Shared link',
          );
          if (!launched && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open link: ${link.url}')),
            );
          }
        } catch (e) {
          debugPrint('Error opening link: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not open link. Please try again.'),
              ),
            );
          }
        }
      },
      style: GoogleFonts.inter(
        fontSize: 15,
        color: textColor.withValues(alpha: 0.9),
        height: 1.4,
      ),
      linkStyle: GoogleFonts.inter(
        color: Colors.blueAccent,
        decoration: TextDecoration.underline,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _post = Map<String, dynamic>.from(widget.post);
    _upvotes = _asSafeInt(_post['upvotes']);
    _downvotes = _asSafeInt(_post['downvotes']);
    _primePhotoCacheFromPost(_post);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _supabaseService.attachContext(context);
    });
    _loadWriterRole();
    _loadData();
  }

  void _initReadOnly() {
    final email = widget.userEmail.trim().toLowerCase();
    if (_hasAccessOverride || _isPrivilegedEmail(email)) {
      _isReadOnly = false;
    } else if (widget.collegeDomain.isEmpty) {
      _isReadOnly = true;
    } else {
      _isReadOnly = !_emailMatchesDomain(email, widget.collegeDomain);
    }
  }

  Future<void> _loadWriterRole() async {
    try {
      final role = await _supabaseService.getCurrentUserRole();
      if (!mounted) return;
      setState(() {
        _hasAccessOverride = role != AppRoles.readOnly;
        _initReadOnly();
      });
    } catch (e, st) {
      debugPrint('PostDetailScreen._loadWriterRole failed: $e\n$st');
    }
  }

  Future<void> _loadData() async {
    final cachedComments = _commentCache[_commentCacheKey];
    if (cachedComments != null && mounted) {
      final hydratedComments = _cloneCommentTree(cachedComments);
      _primePhotoCacheFromComments(hydratedComments);
      setState(() {
        _comments = hydratedComments;
        _isLoading = false;
      });
    }

    try {
      final results = await Future.wait<Object?>([
        _supabaseService.getPostComments(widget.post['id'].toString()),
        _supabaseService.isPostSaved(
          widget.post['id'].toString(),
          widget.userEmail,
        ),
      ]);
      final comments = (results[0] as List).cast<Map<String, dynamic>>();
      final isSaved = results[1] as bool;
      _primePhotoCacheFromComments(comments);
      _cacheComments(comments);

      if (mounted) {
        setState(() {
          _comments = _cloneCommentTree(comments);
          _isSaved = isSaved;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('PostDetailScreen._loadData error: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load post details. Please try again.'),
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshCommentsOnly() async {
    try {
      final comments = await _supabaseService.getPostComments(
        widget.post['id'].toString(),
      );
      _primePhotoCacheFromComments(comments);
      _cacheComments(comments);
      if (!mounted) return;
      setState(() => _comments = _cloneCommentTree(comments));
    } catch (e, stackTrace) {
      debugPrint(
        'PostDetailScreen._refreshCommentsOnly error: $e\n$stackTrace',
      );
    }
  }

  Map<String, dynamic> _buildOptimisticComment(
    String content, {
    String? parentId,
  }) {
    final authorEmail = widget.userEmail.trim();
    final authorName = (_authService.displayName?.trim().isNotEmpty ?? false)
        ? _authService.displayName!.trim()
        : (authorEmail.contains('@') ? authorEmail.split('@').first : 'You');
    final normalizedEmail = _normalizeEmail(authorEmail);
    final cachedPhoto = _profilePhotoCache[normalizedEmail];
    return <String, dynamic>{
      'id': 'temp_${DateTime.now().microsecondsSinceEpoch}',
      'content': content,
      'author_name': authorName,
      'author_email': authorEmail,
      'author_photo_url': cachedPhoto,
      'profile_photo_url': cachedPhoto,
      'created_at': DateTime.now().toIso8601String(),
      'parent_id': parentId,
      'parentId': parentId,
      'replies': <Map<String, dynamic>>[],
    };
  }

  bool _insertReplyIntoTree(
    List<Map<String, dynamic>> comments,
    String parentId,
    Map<String, dynamic> comment,
  ) {
    for (final entry in comments) {
      final entryId = entry['id']?.toString();
      if (entryId == parentId) {
        final replies = _safeReplyList(entry['replies']);
        replies.add(comment);
        entry['replies'] = replies;
        _expandedCommentIds.add(parentId);
        return true;
      }
      if (_insertReplyIntoTree(
        _safeReplyList(entry['replies']),
        parentId,
        comment,
      )) {
        return true;
      }
    }
    return false;
  }

  void _insertCommentLocally(Map<String, dynamic> comment) {
    final nextComments = _comments
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: true);
    final parentId =
        comment['parent_id']?.toString() ?? comment['parentId']?.toString();
    if (parentId == null || parentId.isEmpty) {
      nextComments.add(comment);
    } else if (!_insertReplyIntoTree(nextComments, parentId, comment)) {
      nextComments.add(comment);
    }
    _primePhotoCacheFromComments([comment]);
    _cacheComments(nextComments);
    setState(() => _comments = nextComments);
  }

  bool _removeCommentFromTree(
    List<Map<String, dynamic>> comments,
    String commentId,
  ) {
    final directIndex = comments.indexWhere(
      (entry) => entry['id']?.toString() == commentId,
    );
    if (directIndex != -1) {
      comments.removeAt(directIndex);
      return true;
    }

    for (final entry in comments) {
      final replies = _safeReplyList(entry['replies']);
      if (_removeCommentFromTree(replies, commentId)) {
        entry['replies'] = replies;
        return true;
      }
    }
    return false;
  }

  void _removeCommentLocally(String commentId) {
    final nextComments = _comments
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: true);
    if (_removeCommentFromTree(nextComments, commentId)) {
      _cacheComments(nextComments);
      setState(() => _comments = nextComments);
    }
  }

  Future<void> _toggleSave() async {
    try {
      if (_isSaved) {
        await _supabaseService.unsavePost(
          widget.post['id'].toString(),
          widget.userEmail,
          roomId: widget.roomId,
        );
      } else {
        await _supabaseService.savePost(
          widget.post['id'].toString(),
          widget.userEmail,
          roomId: widget.roomId,
        );
      }

      if (!mounted) return;

      setState(() => _isSaved = !_isSaved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isSaved ? 'Post saved' : 'Post unsaved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _vote(int direction) async {
    final oldVote = _userVote;
    final newVote = _userVote == direction ? null : direction;

    setState(() {
      if (oldVote == 1) _upvotes--;
      if (oldVote == -1) _downvotes--;
      if (newVote == 1) _upvotes++;
      if (newVote == -1) _downvotes++;
      _userVote = newVote;
    });

    try {
      await _supabaseService.votePost(
        widget.post['id'].toString(),
        widget.userEmail,
        newVote ?? 0,
      );
    } catch (e) {
      // Revert on error
      setState(() {
        if (newVote == 1) _upvotes--;
        if (newVote == -1) _downvotes--;
        if (oldVote == 1) _upvotes++;
        if (oldVote == -1) _downvotes++;
        _userVote = oldVote;
      });
    }
  }

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _isSubmitting) return;
    if (_isReadOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Read-only users cannot comment. Use your college email to unlock.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final replyTargetId = _replyToId;
    final optimisticComment = _buildOptimisticComment(
      content,
      parentId: replyTargetId,
    );
    final optimisticCommentId = optimisticComment['id']?.toString() ?? '';

    _commentController.clear();
    setState(() {
      _replyToId = null;
      _replyToName = null;
    });
    _commentFocusNode.unfocus();
    _insertCommentLocally(optimisticComment);

    try {
      await _supabaseService.addPostComment(
        postId: widget.post['id'].toString(),
        content: content,
        userEmail: widget.userEmail,
        userName: _authService.displayName ?? widget.userEmail.split('@')[0],
        parentId: replyTargetId,
      );
      unawaited(_refreshCommentsOnly());
    } catch (e) {
      if (optimisticCommentId.isNotEmpty) {
        _removeCommentLocally(optimisticCommentId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _setReplyTarget(String commentId, String authorName) {
    setState(() {
      _replyToId = commentId;
      _replyToName = authorName;
    });
    FocusScope.of(context).requestFocus(_commentFocusNode);
  }

  Future<void> _reactToComment(String commentId, String emoji) async {
    final userEmail = _authService.userEmail ?? widget.userEmail;
    if (userEmail.isEmpty) return;

    try {
      await _supabaseService.toggleReaction(
        commentId: commentId,
        commentType: 'post',
        userEmail: userEmail,
        emoji: emoji,
      );
      if (!mounted) return;
      setState(() {
        _reactionRefreshTick++;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to react: $e')));
    }
  }

  Future<void> _deletePostCommentById(String commentId) async {
    try {
      await _supabaseService.deletePostComment(commentId);
      _removeCommentLocally(commentId);
      unawaited(_refreshCommentsOnly());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Comment deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete comment: $e')));
    }
  }

  Future<void> _removeAuthorFromRoom(String authorEmail) async {
    if (widget.roomId.isEmpty) return;

    try {
      await _supabaseService.removeRoomMember(
        roomId: widget.roomId,
        userEmail: authorEmail,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removed $authorEmail from room')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove member: $e')));
    }
  }

  Future<void> _showCommentActions({
    required String commentId,
    required String authorName,
    required String authorEmail,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final normalizedAuthorEmail = authorEmail.toLowerCase();
    final normalizedCurrentUser = widget.userEmail.toLowerCase();
    final isOwnComment =
        normalizedAuthorEmail.isNotEmpty &&
        normalizedAuthorEmail == normalizedCurrentUser;
    final canDelete = isOwnComment || widget.isRoomAdmin;
    final canRemoveFromRoom =
        widget.isRoomAdmin &&
        widget.roomId.isNotEmpty &&
        normalizedAuthorEmail.isNotEmpty &&
        !isOwnComment;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comment actions',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Quick reactions',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickReactions.map((emoji) {
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    await _reactToComment(commentId, emoji);
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.reply_rounded, size: 20),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _setReplyTarget(commentId, authorName);
              },
            ),
            if (authorEmail.isNotEmpty)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline_rounded, size: 20),
                title: const Text('View Profile'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(
                        userEmail: authorEmail,
                        userName: authorName,
                      ),
                    ),
                  );
                },
              ),
            if (canDelete)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
                title: const Text(
                  'Delete Comment',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete comment?'),
                      content: const Text('This action cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  if (!mounted) return;
                  if (sheetCtx.mounted) {
                    Navigator.pop(sheetCtx);
                  }
                  await _deletePostCommentById(commentId);
                },
              ),
            if (canRemoveFromRoom)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.person_remove_outlined,
                  color: Colors.redAccent,
                  size: 20,
                ),
                title: const Text(
                  'Remove User From Room',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remove member?'),
                      content: Text('Remove $authorEmail from this room?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            'Remove',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  if (!mounted) return;
                  if (sheetCtx.mounted) {
                    Navigator.pop(sheetCtx);
                  }
                  await _removeAuthorFromRoom(authorEmail);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerImage(String url, bool isDark, Color textColor) {
    if (url.startsWith('asset://')) {
      final assetPath = url.replaceFirst('asset://', '');
      return Image.asset(
        assetPath,
        width: 120,
        height: 120,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Text(url, style: GoogleFonts.inter(color: textColor)),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: 120,
      height: 120,
      fit: BoxFit.contain,
      placeholder: (context, imageUrl) => SizedBox(
        width: 120,
        height: 120,
        child: Container(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      errorWidget: (context, imageUrl, error) =>
          const Icon(Icons.broken_image_outlined),
    );
  }

  ({String title, String body}) _extractPostParts(Map<String, dynamic> post) {
    final fullContent = post['content']?.toString() ?? '';
    final dbTitle = post['title']?.toString() ?? '';
    if (dbTitle.trim().isNotEmpty) {
      return (title: dbTitle.trim(), body: fullContent.trim());
    }
    final lines = fullContent.split('\n');
    if (lines.isEmpty) return (title: '', body: '');
    final title = lines.first.trim();
    final body = lines.length > 1 ? lines.sublist(1).join('\n').trim() : '';
    return (title: title, body: body);
  }

  Future<void> _showEditPostSheet() async {
    if (_isReadOnly) return;
    final postId = _post['id']?.toString() ?? '';
    if (postId.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parts = _extractPostParts(_post);
    final titleController = TextEditingController(text: parts.title);
    final contentController = TextEditingController(text: parts.body);
    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setModalState) => Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.75,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(color: AppTheme.textMuted),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Edit Post',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final title = titleController.text.trim();
                              final body = contentController.text.trim();
                              if (title.isEmpty && body.isEmpty) {
                                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Post cannot be empty.'),
                                  ),
                                );
                                return;
                              }
                              setModalState(() => isSaving = true);
                              final updatedContent = title.isNotEmpty
                                  ? (body.isNotEmpty ? '$title\n$body' : title)
                                  : body;
                              try {
                                await _supabaseService.updatePost(
                                  postId: postId,
                                  content: updatedContent,
                                );
                                if (!mounted) return;
                                setState(() {
                                  _post = Map<String, dynamic>.from(_post)
                                    ..['content'] = updatedContent;
                                  if (title.isNotEmpty) {
                                    _post['title'] = title;
                                  } else {
                                    _post.remove('title');
                                  }
                                });
                                if (sheetCtx.mounted) {
                                  Navigator.pop(sheetCtx);
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post updated')),
                                );
                              } catch (e) {
                                if (sheetCtx.mounted) {
                                  ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                  setModalState(() => isSaving = false);
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Save',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      TextField(
                        controller: titleController,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Title (Optional)',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: contentController,
                        maxLines: 10,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Update your post content...',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 15,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeletePost() async {
    if (_isReadOnly) return;
    final postId = _post['id']?.toString() ?? '';
    if (postId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _supabaseService.deletePost(postId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post deleted')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final post = _post;
    final authorEmail = (post['author_email'] ?? post['user_email'] ?? '')
        .toString();
    final isAuthor =
        authorEmail.isNotEmpty &&
        authorEmail.toLowerCase() == widget.userEmail.toLowerCase();
    final canEditPost = !_isReadOnly && isAuthor;
    final canDeletePost = !_isReadOnly && (isAuthor || widget.isRoomAdmin);

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Post',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isSaved ? Icons.bookmark : Icons.bookmark_border,
              color: _isSaved ? AppTheme.primary : AppTheme.textMuted,
            ),
            onPressed: _toggleSave,
          ),
          if (canEditPost || canDeletePost)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PopupMenuButton<String>(
                tooltip: 'Post actions',
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 20,
                  color: AppTheme.textMuted,
                ),
                onSelected: (value) async {
                  if (value == 'edit') {
                    await _showEditPostSheet();
                  } else if (value == 'delete') {
                    await _confirmDeletePost();
                  }
                },
                itemBuilder: (context) => [
                  if (canEditPost)
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_rounded,
                            size: 18,
                            color: AppTheme.textPrimary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Edit Post',
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (canDeletePost)
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Delete Post',
                            style: GoogleFonts.inter(color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Post content
                  _buildPostContent(post, isDark),

                  const SizedBox(height: 12),
                  Divider(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
                  const SizedBox(height: 12),

                  // Comments section
                  Text(
                    'Comments (${_comments.length})',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _comments.isEmpty
                      ? _buildEmptyComments(isDark)
                      : _buildCommentsList(isDark),
                ],
              ),
            ),
          ),

          // Comment input
          _buildCommentInput(isDark),
        ],
      ),
    );
  }

  Widget _buildPostContent(Map<String, dynamic> post, bool isDark) {
    // Parse title and content from full content
    final fullContent = post['content']?.toString() ?? '';
    final dbTitle = post['title']
        ?.toString()
        .trim(); // Fallback if column exists

    String title;
    String content;

    if (dbTitle != null && dbTitle.isNotEmpty) {
      title = dbTitle;
      content = fullContent;
    } else {
      final parts = fullContent.split('\n');
      if (parts.isNotEmpty) {
        title = parts[0];
        content = parts.length > 1 ? parts.sublist(1).join('\n').trim() : '';
      } else {
        title = '';
        content = '';
      }
    }

    final authorEmail = (post['author_email'] ?? post['user_email'] ?? '')
        .toString();
    final authorName =
        (post['author_name']?.toString().trim().isNotEmpty ?? false)
        ? post['author_name'].toString().trim()
        : authorEmail.contains('@')
        ? authorEmail.split('@').first
        : 'User';
    final normalizedEmail = _normalizeEmail(authorEmail);
    final cachedPhoto = _profilePhotoCache[normalizedEmail];
    final fallbackPhoto = _resolvePhotoUrl(post, const [
      'author_photo_url',
      'profile_photo_url',
      'photo_url',
      'avatar_url',
    ]);
    final resolvedPhoto = (cachedPhoto != null && cachedPhoto.isNotEmpty)
        ? cachedPhoto
        : fallbackPhoto;
    if (resolvedPhoto.isEmpty && normalizedEmail.isNotEmpty) {
      _ensureProfilePhotoCached(normalizedEmail);
    }
    final hasAuthorPhoto = resolvedPhoto.isNotEmpty;
    final createdAt =
        DateTime.tryParse(post['created_at']?.toString() ?? '') ??
        DateTime.now();
    final netVotes = _upvotes - _downvotes;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author info
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(
                        userEmail: authorEmail,
                        userName: authorName,
                        userPhotoUrl: hasAuthorPhoto ? resolvedPhoto : null,
                      ),
                    ),
                  );
                },
                child: Row(
                  children: [
                    UserAvatar(
                      radius: 18,
                      displayName: authorName,
                      photoUrl: hasAuthorPhoto ? resolvedPhoto : null,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              authorName,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(width: 4),
                            UserBadge(email: authorEmail, size: 14),
                          ],
                        ),
                        Text(
                          _formatTimeAgo(createdAt),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Title
          if (title.isNotEmpty)
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          if (title.isNotEmpty) const SizedBox(height: 6),

          // Content
          Text(
            content,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.black87,
              height: 1.5,
            ),
          ),

          // Image (Added Fix)
          if ((post['image_url']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final imageUrl = post['image_url']!.toString();
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullScreenImageViewer(
                          imageUrl: imageUrl,
                          heroTag: 'post_image_${widget.post['id']}',
                        ),
                      ),
                    );
                  },
                  child: Hero(
                    tag: 'post_image_${widget.post['id']}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          final expectedBytes =
                              loadingProgress.expectedTotalBytes;
                          final progress = expectedBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                    expectedBytes
                              : null;
                          return Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 2,
                                color: AppTheme.primary,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 150,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white10
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_not_supported_outlined,
                                size: 32,
                                color: AppTheme.textMuted,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Image unavailable',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 12),

          // Vote buttons
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_upward_rounded,
                        color: _userVote == 1
                            ? AppTheme.success
                            : AppTheme.textMuted,
                        size: 20,
                      ),
                      onPressed: () => _vote(1),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        netVotes.toString(),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: netVotes > 0
                              ? AppTheme.success
                              : netVotes < 0
                              ? AppTheme.error
                              : AppTheme.textMuted,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.arrow_downward_rounded,
                        color: _userVote == -1
                            ? AppTheme.error
                            : AppTheme.textMuted,
                        size: 20,
                      ),
                      onPressed: () => _vote(-1),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.comment_outlined, size: 20, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Text(
                '${post['comment_count'] ?? _comments.length}',
                style: GoogleFonts.inter(color: AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyComments(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: AppTheme.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No comments yet',
              style: GoogleFonts.inter(color: AppTheme.textMuted),
            ),
            Text(
              'Be the first to comment!',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.textMuted.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsList(bool isDark) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _comments.length,
      separatorBuilder: (_, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        return _buildCommentCard(_comments[index], isDark);
      },
    );
  }

  Widget _buildCommentCard(
    Map<String, dynamic> comment,
    bool isDark, {
    int depth = 0,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final rawAuthorName = comment['author_name']?.toString().trim();
    final authorEmail = (comment['author_email'] ?? '').toString();
    final authorName = rawAuthorName != null && rawAuthorName.isNotEmpty
        ? rawAuthorName
        : authorEmail.contains('@')
        ? authorEmail.split('@').first
        : 'User';
    final normalizedEmail = _normalizeEmail(authorEmail);
    final cachedPhoto = _profilePhotoCache[normalizedEmail];
    final fallbackPhoto = _resolvePhotoUrl(comment, const [
      'author_photo_url',
      'profile_photo_url',
      'photo_url',
      'avatar_url',
      'user_photo_url',
    ]);
    final resolvedPhoto = (cachedPhoto != null && cachedPhoto.isNotEmpty)
        ? cachedPhoto
        : fallbackPhoto;
    if (resolvedPhoto.isEmpty && normalizedEmail.isNotEmpty) {
      _ensureProfilePhotoCached(normalizedEmail);
    }
    final hasAuthorPhoto = resolvedPhoto.isNotEmpty;
    final content = (comment['content'] ?? '').toString();
    final createdAt =
        DateTime.tryParse(comment['created_at']?.toString() ?? '') ??
        DateTime.now();

    final rawReplies = comment['replies'];
    final replies = _safeReplyList(rawReplies);
    final hasReplies = replies.isNotEmpty;
    final commentId =
        comment['id']?.toString() ??
        'comment-${createdAt.toIso8601String()}-$authorName-${content.hashCode}';
    final isExpanded = _expandedCommentIds.contains(commentId);

    return Dismissible(
      key: ValueKey('comment-swipe-$commentId-$depth'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.22},
      confirmDismiss: (_) async {
        _setReplyTarget(commentId, authorName);
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
      child: GestureDetector(
        onLongPress: () {
          _showCommentActions(
            commentId: commentId,
            authorName: authorName,
            authorEmail: authorEmail,
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserProfileScreen(
                            userEmail: authorEmail,
                            userName: authorName,
                            userPhotoUrl: hasAuthorPhoto ? resolvedPhoto : null,
                          ),
                        ),
                      );
                    },
                    child: UserAvatar(
                      radius: 18,
                      displayName: authorName,
                      photoUrl: hasAuthorPhoto ? resolvedPhoto : null,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: Name + Time
                        Row(
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => UserProfileScreen(
                                          userEmail: authorEmail,
                                          userName: authorName,
                                          userPhotoUrl: hasAuthorPhoto
                                              ? resolvedPhoto
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    authorName,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                UserBadge(email: authorEmail, size: 14),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTimeAgo(createdAt),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            const Spacer(),
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                size: 18,
                                color: AppTheme.textMuted,
                              ),
                              onSelected: (value) {
                                if (value == 'report') {
                                  _showReportDialog(
                                    context,
                                    commentId,
                                    isComment: true,
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'report',
                                  child: Text('Report'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Comment Body
                        _buildCommentContent(
                          content,
                          isDark,
                          textColor,
                          commentId,
                        ),

                        const SizedBox(height: 8),

                        // Actions Row: Reactions + Reply
                        Row(
                          children: [
                            // Emoji Reactions
                            Expanded(
                              child: EmojiReactions(
                                key: ValueKey(
                                  'post-$commentId-$_reactionRefreshTick',
                                ),
                                commentId: commentId,
                                commentType: 'post',
                                compact: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Reply Button
                            GestureDetector(
                              onTap: () {
                                _setReplyTarget(commentId, authorName);
                              },
                              child: Text(
                                'Reply',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Threaded Replies Toggle
                        if (hasReplies) ...[
                          Padding(
                            padding: EdgeInsets.only(
                              top: 6,
                              bottom: isExpanded ? 6 : 10,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  setState(() {
                                    if (isExpanded) {
                                      _expandedCommentIds.remove(commentId);
                                    } else {
                                      _expandedCommentIds.add(commentId);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white12
                                          : Colors.black12,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isExpanded
                                            ? Icons.keyboard_arrow_up_rounded
                                            : Icons.keyboard_arrow_down_rounded,
                                        size: 16,
                                        color: AppTheme.textMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isExpanded
                                            ? 'Hide replies'
                                            : 'View ${replies.length} replies',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // Render Recursive Replies
              if (hasReplies && isExpanded)
                Container(
                  margin: const EdgeInsets.only(left: 36, top: 4),
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: isDark ? Colors.white24 : Colors.black12,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: depth < 3
                      ? ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: replies.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) => _buildCommentCard(
                            replies[index],
                            isDark,
                            depth: depth + 1,
                          ),
                        )
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 6,
                              ),
                              minimumSize: const Size(0, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              // Navigate to thread detail or expand further (not implemented)
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Deep thread view not implemented',
                                  ),
                                ),
                              );
                            },
                            child: Text('View ${replies.length} more replies'),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _asSafeInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  List<Map<String, dynamic>> _safeReplyList(Object? rawReplies) {
    if (rawReplies is! List) return const <Map<String, dynamic>>[];
    return rawReplies
        .whereType<Map>()
        .map((reply) => Map<String, dynamic>.from(reply))
        .toList();
  }

  String _normalizeEmail(String value) => value.trim().toLowerCase();

  void _primePhotoCacheFromPost(Map<String, dynamic> post) {
    final email = _normalizeEmail(
      post['author_email']?.toString() ?? post['user_email']?.toString() ?? '',
    );
    if (email.isEmpty || _profilePhotoCache.containsKey(email)) return;
    final resolved = _resolvePhotoUrl(post, const [
      'author_photo_url',
      'profile_photo_url',
      'photo_url',
      'avatar_url',
    ]);
    if (resolved.isNotEmpty) {
      _profilePhotoCache[email] = resolved;
    }
  }

  void _primePhotoCacheFromComments(List<Map<String, dynamic>> comments) {
    for (final comment in comments) {
      final email = _normalizeEmail(comment['author_email']?.toString() ?? '');
      if (email.isNotEmpty && !_profilePhotoCache.containsKey(email)) {
        final resolved = _resolvePhotoUrl(comment, const [
          'author_photo_url',
          'profile_photo_url',
          'photo_url',
          'avatar_url',
          'user_photo_url',
        ]);
        if (resolved.isNotEmpty) {
          _profilePhotoCache[email] = resolved;
        }
      }

      final replies = comment['replies'];
      if (replies is List && replies.isNotEmpty) {
        final mapped = replies.whereType<Map>().map((item) {
          return Map<String, dynamic>.from(item);
        }).toList();
        if (mapped.isNotEmpty) {
          _primePhotoCacheFromComments(mapped);
        }
      }
    }
  }

  Future<void> _ensureProfilePhotoCached(String email) async {
    final normalized = _normalizeEmail(email);
    if (normalized.isEmpty ||
        _profilePhotoCache.containsKey(normalized) ||
        _profilePhotoFetchInFlight.contains(normalized)) {
      return;
    }
    _profilePhotoFetchInFlight.add(normalized);
    try {
      final profile = await _supabaseService.getUserInfo(normalized);
      final resolved = resolveProfilePhotoUrl(profile) ?? '';
      if (!mounted) return;
      setState(() {
        _profilePhotoCache[normalized] = resolved;
      });
    } catch (e) {
      debugPrint('Failed to resolve profile photo for $normalized: $e');
    } finally {
      _profilePhotoFetchInFlight.remove(normalized);
    }
  }

  static String _resolvePhotoUrl(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    return resolveProfilePhotoUrl(source, preferredKeys: keys) ?? '';
  }

  Future<bool> _ensurePremiumStickerAccess() async {
    final hasPremium = await _subscriptionService.isPremium();
    if (hasPremium) return true;
    if (!mounted) return false;

    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => PaywallDialog(
        onSuccess: () {
          Navigator.of(dialogContext).pop(true);
        },
      ),
    );

    if (result == true && mounted) {
      // Re-check premium status after successful purchase
      final isPremium = await _subscriptionService.isPremium();
      if (isPremium) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Premium unlocked! Sticker feature enabled.'),
          ),
        );
      }
      return isPremium;
    }

    if (!mounted) return false;
    return false;
  }

  Future<void> _handleStickerSelection(File stickerFile) async {
    if (_isReadOnly) return;
    if (!await _ensurePremiumStickerAccess()) return;

    // Upload sticker media first, then persist the encoded URL as comment content.
    // For now, show a placeholder message
    setState(() => _isSubmitting = true);
    String optimisticCommentId = '';
    try {
      final length = await stickerFile.length();
      if (length > kMaxStickerSizeBytes) {
        throw Exception('Sticker is too large (max 5MB).');
      }
      final bytes = await stickerFile.readAsBytes();
      final rawExt = p.extension(stickerFile.path).toLowerCase();
      final ext = {'.gif', '.webp', '.png', '.jpg', '.jpeg'}.contains(rawExt)
          ? rawExt
          : '.png';
      final filename = 'sticker_${DateTime.now().millisecondsSinceEpoch}$ext';

      final upload = await _backendApiService.uploadChatImageBytes(
        bytes: bytes,
        filename: filename,
      );
      final url =
          upload['imageUrl']?.toString().trim() ??
          upload['url']?.toString().trim();
      if (url == null || url.isEmpty) {
        throw const FormatException('Sticker upload completed without a URL.');
      }
      final replyTargetId = _replyToId;
      final optimisticComment = _buildOptimisticComment(
        StickerCommentCodec.encode(url),
        parentId: replyTargetId,
      );
      optimisticCommentId = optimisticComment['id']?.toString() ?? '';

      setState(() {
        _replyToId = null;
        _replyToName = null;
      });
      _insertCommentLocally(optimisticComment);

      await _supabaseService.addPostComment(
        postId: widget.post['id'].toString(),
        content: StickerCommentCodec.encode(url),
        userEmail: widget.userEmail,
        userName: _authService.displayName ?? widget.userEmail.split('@')[0],
        parentId: replyTargetId,
      );
      unawaited(_refreshCommentsOnly());
    } catch (e) {
      if (optimisticCommentId.isNotEmpty) {
        _removeCommentLocally(optimisticCommentId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sending sticker: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildCommentInput(bool isDark) {
    return CommentInputBox(
      controller: _commentController,
      focusNode: _commentFocusNode,
      isReadOnly: _isReadOnly,
      isSubmitting: _isSubmitting,
      replyToName: _replyToName,
      onCancelReply: () {
        setState(() {
          _replyToId = null;
          _replyToName = null;
        });
        _commentFocusNode.unfocus();
      },
      onSubmit: _submitComment,
      onStickerSelected: _handleStickerSelection,
      onStickerAccessCheck: _ensurePremiumStickerAccess,
      hintText: _replyToName != null
          ? 'Write your reply...'
          : 'Add a comment...',
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dateTime.day}/${dateTime.month}';
  }

  Future<void> _showReportDialog(
    BuildContext context,
    String targetId, {
    bool isComment = false,
  }) async {
    final TextEditingController reasonController = TextEditingController();
    final itemType = isComment ? 'comment' : 'post';

    try {
      await showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor:
              Theme.of(dialogCtx).dialogTheme.backgroundColor ??
              Theme.of(dialogCtx).colorScheme.surface,
          title: Text(
            'Report ${itemType == 'comment' ? 'Comment' : 'Post'}',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              color: Theme.of(dialogCtx).colorScheme.onSurface,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why are you reporting this $itemType?',
                style: GoogleFonts.inter(
                  color: Theme.of(
                    dialogCtx,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                style: GoogleFonts.inter(
                  color: Theme.of(dialogCtx).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter reason...',
                  hintStyle: GoogleFonts.inter(
                    color: Theme.of(
                      dialogCtx,
                    ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: Theme.of(
                    dialogCtx,
                  ).colorScheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  color: Theme.of(dialogCtx).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) return;
                final messenger =
                    ScaffoldMessenger.maybeOf(dialogCtx) ??
                    ScaffoldMessenger.maybeOf(context);

                // Deny unauthenticated reports
                if (_authService.currentUser == null) {
                  messenger?.showSnackBar(
                    const SnackBar(
                      content: Text("You must be signed in to report."),
                    ),
                  );
                  if (mounted && dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                  }
                  return;
                }
                final reporterId = _authService.currentUser!.uid;

                messenger?.showSnackBar(
                  const SnackBar(content: Text("Submitting report...")),
                );

                // Call Backend API
                try {
                  if (isComment) {
                    await _backendApiService.reportComment(
                      targetId,
                      reason,
                      reporterId,
                    );
                  } else {
                    await _backendApiService.reportPost(
                      targetId,
                      reason,
                      reporterId,
                    );
                  }

                  messenger?.showSnackBar(
                    const SnackBar(
                      content: Text("Report submitted successfully."),
                    ),
                  );
                } catch (e) {
                  messenger?.showSnackBar(
                    SnackBar(content: Text("Report failed: $e")),
                  );
                } finally {
                  if (mounted && dialogCtx.mounted) {
                    Navigator.pop(dialogCtx); // Close dialog
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Report',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } finally {
      reasonController.dispose();
    }
  }
}
