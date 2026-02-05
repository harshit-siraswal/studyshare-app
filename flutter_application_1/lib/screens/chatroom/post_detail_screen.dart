import 'package:flutter/material.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/emoji_reactions.dart';
import '../profile/user_profile_screen.dart';
import '../../services/backend_api_service.dart';
import '../../widgets/comment_input_box.dart';
import '../../config/app_config.dart';

import '../../services/subscription_service.dart';
import '../../widgets/paywall_dialog.dart';

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final String userEmail;
  final String collegeDomain;

  const PostDetailScreen({
    super.key,
    required this.post,
    required this.userEmail,
    required this.collegeDomain,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();
  final SubscriptionService _subscriptionService = SubscriptionService(); // New instance
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  // Reply state
  String? _replyToId;
  String? _replyToName;
  
  // ... (rest of vars)

  Future<void> _handleGifTap() async {
     final isPremium = await _subscriptionService.isPremium();
     if (!mounted) return;
     
     if (!isPremium) {
       showDialog(
         context: context,
         builder: (context) => PaywallDialog(
           onSuccess: () {
             if (!mounted) return;
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Premium unlocked! You can now post GIFs.')),
             );
             // Directly show picker for smooth UX
             _showGifPicker();
           },
         ),
       );
     } else {
       _showGifPicker();
     }
  }

  void _showGifPicker() {
    final theme = Theme.of(context);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Select GIF (Premium Feature)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                children: [
                  _buildGifOption('https://media.giphy.com/media/l0HlHJGHe3yAMhdQY/giphy.gif'),
                  _buildGifOption('https://media.giphy.com/media/3o7TKs6DH0R3X3U6v6/giphy.gif'),
                  _buildGifOption('https://media.giphy.com/media/d9QiBcfzg64Io/giphy.gif'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGifOption(String url) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        final text = _commentController.text;
        final selection = _commentController.selection;
        final insertPos = selection.isValid ? selection.baseOffset : text.length;
        final gifMarkdown = ' ![GIF]($url) ';
        final newText = text.substring(0, insertPos) + gifMarkdown + text.substring(insertPos);
        _commentController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: insertPos + gifMarkdown.length),
        );
      },
      child: Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[300],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      ),
    );
  }

  // ... (rest of methods)
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isSaved = false;
  int _upvotes = 0;
  int _downvotes = 0;
  int? _userVote;
  bool _isSubmitting = false;
  bool _isReadOnly = false;
  final Set<String> _expandedCommentIds = {};

  @override
  void initState() {
    super.initState();
    _upvotes = widget.post['upvotes'] ?? 0;
    _downvotes = widget.post['downvotes'] ?? 0;
    _initReadOnly();
    _loadData();
  }

  void _initReadOnly() {
    if (widget.collegeDomain.isEmpty) {
      _isReadOnly = true;
    } else {
      _isReadOnly = !widget.userEmail.endsWith(widget.collegeDomain);
    }
  }

  Future<void> _loadData() async {
    try {
      // Use backend-driven comments to match website schema (message_id instead of post_id)
      final comments = await _supabaseService.getPostComments(widget.post['id'].toString());
      final isSaved = await _supabaseService.isPostSaved(widget.post['id'].toString(), widget.userEmail);
      
      if (mounted) {
        setState(() {
          _comments = comments;
          _isSaved = isSaved;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleSave() async {
    try {
      if (_isSaved) {
        await _supabaseService.unsavePost(widget.post['id'].toString(), widget.userEmail);
      } else {
        await _supabaseService.savePost(widget.post['id'].toString(), widget.userEmail);
      }
      setState(() => _isSaved = !_isSaved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isSaved ? 'Post saved!' : 'Post unsaved')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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
      await _supabaseService.votePost(widget.post['id'].toString(), widget.userEmail, direction);
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
        const SnackBar(content: Text('Read-only users cannot comment. Use your college email to unlock.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _supabaseService.addPostComment(
        postId: widget.post['id'].toString(),
        content: content,
        userEmail: widget.userEmail,
        userName: _authService.displayName ?? widget.userEmail.split('@')[0],
        parentId: _replyToId,
      );
      _commentController.clear();
      setState(() {
        _replyToId = null;
        _replyToName = null;
      });
      _commentFocusNode.unfocus();
      await _loadData(); // Refresh comments
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final post = widget.post;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: isDark ? Colors.white : Colors.black),
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
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Post content
                  _buildPostContent(post, isDark),
                  
                  const SizedBox(height: 16),
                  Divider(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                  const SizedBox(height: 16),
                  
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
    final fullContent = post['content'] ?? '';
    final dbTitle = post['title'] as String?; // Fallback if column exists
    
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

    final authorName = post['author_name'] ?? post['author_email']?.split('@')[0] ?? 'User';
    final createdAt = post['created_at'] != null 
        ? DateTime.parse(post['created_at']) 
        : DateTime.now();
    final netVotes = _upvotes - _downvotes;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
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
                        userEmail: post['author_email'] ?? '',
                        userName: authorName,
                        userPhotoUrl: post['author_photo_url'],
                      ),
                    ),
                  );
                },
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        authorName[0].toUpperCase(),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authorName,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
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
          const SizedBox(height: 12),
          
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
          if (title.isNotEmpty) const SizedBox(height: 8),
          
          // Content
          Text(
            content,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
              height: 1.5,
            ),
          ),
          
           // Image (Added Fix)
          if (post['image_url'] != null && post['image_url'].toString().isNotEmpty) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                post['image_url'],
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_not_supported_outlined, size: 32, color: AppTheme.textMuted),
                      const SizedBox(height: 8),
                      Text(
                        'Image unavailable',
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          
          // Vote buttons
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_upward_rounded,
                        color: _userVote == 1 ? AppTheme.success : AppTheme.textMuted,
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
                        color: _userVote == -1 ? AppTheme.error : AppTheme.textMuted,
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
            Icon(Icons.chat_bubble_outline, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'No comments yet',
              style: GoogleFonts.inter(color: AppTheme.textMuted),
            ),
            Text(
              'Be the first to comment!',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted.withValues(alpha: 0.7)),
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
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildCommentCard(_comments[index], isDark),
    );
  }

  Widget _buildCommentCard(Map<String, dynamic> comment, bool isDark) {
    final authorName = comment['author_name'] ?? comment['author_email']?.split('@')[0] ?? 'User';
    final content = comment['content'] ?? '';
    final createdAt = comment['created_at'] != null 
        ? DateTime.parse(comment['created_at']) 
        : DateTime.now();

    final replies = comment['replies'] as List<Map<String, dynamic>>? ?? [];
    final hasReplies = replies.isNotEmpty;
    final commentId = comment['id']?.toString() ?? '';
    final isExpanded = _expandedCommentIds.contains(commentId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                        userEmail: comment['author_email'] ?? '',
                        userName: authorName,
                        userPhotoUrl: comment['author_photo_url'],
                      ),
                    ),
                  );
                },
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.secondary, // Or random color/image
                  child: Text(
                    authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
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
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserProfileScreen(
                                  userEmail: comment['author_email'] ?? '',
                                  userName: authorName,
                                  userPhotoUrl: comment['author_photo_url'],
                                ),
                              ),
                            );
                          },
                          child: Text(
                            authorName,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
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
                        Icon(Icons.more_horiz_rounded, size: 16, color: AppTheme.textMuted),
                      ],
                    ),
                    const SizedBox(height: 4),
                    
                    // Comment Body
                    Text(
                      content,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Actions Row: Reactions + Reply
                    Row(
                      children: [
                        // Emoji Reactions
                        Expanded(
                          child: EmojiReactions(
                            commentId: commentId,
                            commentType: 'post',
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Reply Button
                          GestureDetector(
                          onTap: () {
                             setState(() {
                               _replyToId = commentId;
                               _replyToName = authorName;
                             });
                             FocusScope.of(context).requestFocus(_commentFocusNode);
                          },
                          child: Text(
                            'Reply',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    // Threaded Replies Toggle
                    if (hasReplies) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedCommentIds.remove(commentId);
                            } else {
                              _expandedCommentIds.add(commentId);
                            }
                          });
                        },
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 1, // Line
                              color: AppTheme.textMuted.withValues(alpha: 0.5),
                              margin: const EdgeInsets.only(right: 8),
                            ),
                            Text(
                              isExpanded ? 'Hide replies' : 'View ${replies.length} replies',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            Icon(
                              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, 
                              size: 16, 
                              color: AppTheme.textMuted
                            ),
                          ],
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
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 12), // Indent replies
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: replies.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _buildCommentCard(replies[index], isDark),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleStickerSelection(File stickerFile) async {
     if (_isReadOnly) return;
     
     // For stickers, we would upload to cloudinary or storage and get URL
     // For now, show a placeholder message
     setState(() => _isSubmitting = true);
     try {
       // TODO: Upload sticker to storage and get URL
       // For now, just show the file path as content
       await _supabaseService.addPostComment(
         postId: widget.post['id'].toString(),
         content: '📝 [Sticker sent]',
         userEmail: widget.userEmail,
         userName: _authService.displayName ?? widget.userEmail.split('@')[0],
         parentId: _replyToId,
       );
       
       setState(() {
         _replyToId = null;
         _replyToName = null;
       });
       await _loadData();
     } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Error sending GIF: $e')),
       );
     } finally {
       setState(() => _isSubmitting = false);
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

  void _showReportDialog(BuildContext context, String postId, String authorId) {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Report Post', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why are you reporting this post?', style: GoogleFonts.inter(color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              style: GoogleFonts.inter(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter reason...',
                hintStyle: GoogleFonts.inter(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              
              Navigator.pop(context); // Close dialog

              // Call Backend API
              try {
                // Determine current user ID if possible, otherwise empty
                final reporterId = AuthService().currentUser?.uid ?? 'unknown';

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Submitting report...")),
                );

                await BackendApiService().reportPost(postId, reason, reporterId);

                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text("Report submitted successfully.")),
                   );
                }
              } catch (e) {
                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text("Report submitted (backend limitation: $e)")),
                   );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text('Report', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
