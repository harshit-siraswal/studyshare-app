import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import '../../config/theme.dart';
import '../../services/cloudinary_service.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../profile/user_profile_screen.dart';
import 'post_detail_screen.dart';
import 'package:giphy_picker/giphy_picker.dart';
import '../../config/app_config.dart';
import '../../services/backend_api_service.dart';
import '../../services/subscription_service.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String roomName;
  final String description;
  final String userEmail;
  final String collegeDomain;

  const ChatRoomScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.description,
    required this.userEmail,
    required this.collegeDomain,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();

  bool get _isReadOnly {
    final domain = widget.collegeDomain;
    if (domain.isEmpty) return true;
    return !widget.userEmail.endsWith(domain);
  }
  
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  final String _sortBy = 'recent'; // 'recent' or 'top'
  Map<String, dynamic>? _roomInfo;
  bool _isAdmin = false;
  bool _isMember = false;
  
  // Track which posts are saved (bookmarked)
  final Map<String, bool> _savedPosts = {};
  
  // Track user votes: local state for optimistic updates
  // postId -> vote direction (1, -1, 0)
  final Map<String, int> _userVotes = {};
  
  // Realtime subscription
  RealtimeChannel? _subscription;
  Timer? _reloadDebounce;
  
  late AnimationController _fabAnimationController;
  
  // Search state
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // Start animation with a slight delay to mimic "arrival"
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fabAnimationController.forward();
    });
    
    _loadRoomData();
    _subscribeToPosts();
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    _subscription?.unsubscribe();
    _reloadDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // Request sequencing
  int _loadRequestId = 0;

  Future<void> _loadRoomData({bool silent = false}) async {
    final int requestId = ++_loadRequestId;
    if (!silent && mounted) setState(() => _isLoading = true);
    
    try {
      // Parallelize requests to speed up load time
      final results = await Future.wait([
        _supabaseService.getRoomPosts(widget.roomId, sortBy: _sortBy),
        _supabaseService.getRoomInfo(widget.roomId),
        _supabaseService.isRoomAdmin(widget.roomId, widget.userEmail),
        _supabaseService.getUserRoomIds(widget.userEmail),
        _supabaseService.getSavedPostIds(widget.userEmail),
        _supabaseService.getUserVotes(widget.roomId),
      ]);
      
      if (requestId != _loadRequestId || !mounted) return;

      final posts = results[0] as List<Map<String, dynamic>>;
      final info = results[1] as Map<String, dynamic>?;
      final isAdmin = results[2] as bool;
      
      // Handle User Room IDs (List -> Set)
      final rawUserRoomIds = results[3];
      final Set<String> memberCheckIds = (rawUserRoomIds is List) 
          ? rawUserRoomIds.map((e) => e.toString()).toSet() 
          : (rawUserRoomIds as Set).cast<String>();

      // Handle Saved Post IDs (Set or List -> Set)
      final rawSavedPostIds = results[4];
      final Set<String> savedPostIds = (rawSavedPostIds is List)
          ? rawSavedPostIds.map((e) => e.toString()).toSet()
          : (rawSavedPostIds as Set).cast<String>();

      final userVotes = results[5] as Map<String, int>;
      
      // Update saved status from batch
      for (var post in posts) {
        final postId = post['id']?.toString() ?? '';
        if (postId.isNotEmpty) {
          _savedPosts[postId] = savedPostIds.contains(postId);
          _userVotes[postId] = userVotes[postId] ?? 0;
        }
      }
      
      if (mounted && requestId == _loadRequestId) {
        setState(() {
          _posts = posts;
          _roomInfo = info;
          _isAdmin = isAdmin;
          _isMember = memberCheckIds.contains(widget.roomId);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading room data: $e');
      if (mounted && requestId == _loadRequestId) {
         setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _joinRoom() async {
    setState(() => _isLoading = true);
    try {
      await _supabaseService.joinRoom(widget.roomId);
      
      if (mounted) {
         await _loadRoomData();
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Joined room successfully!')),
         );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining room: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _subscribeToPosts() {
     // Config debounce duration
     const debounceDuration = Duration(milliseconds: 300);

    _subscription = Supabase.instance.client
        .channel('public:room_messages:room_id=eq.${widget.roomId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (payload) {
             // Debounce the reload
             if (_reloadDebounce?.isActive ?? false) _reloadDebounce!.cancel();
             _reloadDebounce = Timer(debounceDuration, () {
                if (mounted) _loadRoomData(silent: true);
             });
          },
        )
        .subscribe();
  }

  Future<void> _handleVote(String postId, int direction) async {
    try {
      if (_isReadOnly) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Read-only users cannot vote. Use your college email to unlock.')),
        );
        return;
      }
      
      // Optimistic update
      final index = _posts.indexWhere((p) => p['id'].toString() == postId);
      if (index != -1) {
        setState(() {
          final currentVote = _userVotes[postId] ?? 0;
          final updatedPost = Map<String, dynamic>.from(_posts[index]);
          
          if (currentVote == direction) {
            // Toggle off (remove vote)
            if (direction == 1) {
               updatedPost['upvotes'] = max(0, (updatedPost['upvotes'] as int) - 1);
            } else {
               updatedPost['downvotes'] = max(0, (updatedPost['downvotes'] as int) - 1);
            }
            _userVotes[postId] = 0;
          } else {
            // Switch or Add vote
            if (currentVote == 1) {
               // Remove old upvote
               updatedPost['upvotes'] = max(0, (updatedPost['upvotes'] as int) - 1);
            } else if (currentVote == -1) {
               // Remove old downvote
               updatedPost['downvotes'] = max(0, (updatedPost['downvotes'] as int) - 1);
            }
            
            // Add new vote
            if (direction == 1) {
               updatedPost['upvotes'] = (updatedPost['upvotes'] as int) + 1;
            } else {
               updatedPost['downvotes'] = (updatedPost['downvotes'] as int) + 1;
            }
            _userVotes[postId] = direction;
          }
          
          _posts[index] = updatedPost;
        });
      }

      await _supabaseService.votePost(postId, widget.userEmail, direction);
      // Logic handled by subscription reload, or silent reload here if needed
      // _loadRoomData(silent: true); 
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error voting: $e')),
        );
        _loadRoomData(silent: true);
      }
    }
  }

  Future<void> _handleBookmark(String postId) async {
    try {
      if (_isReadOnly) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Read-only users cannot save posts. Use your college email to unlock.')),
        );
        return;
      }
      
      final currentlySaved = _savedPosts[postId] ?? false;
      
      // Optimistic UI update
      setState(() {
        _savedPosts[postId] = !currentlySaved;
      });
      
      if (currentlySaved) {
        await _supabaseService.unsavePost(postId, widget.userEmail);
      } else {
        await _supabaseService.savePost(postId, widget.userEmail);
      }
      
      // Show feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentlySaved ? 'Removed from saved' : 'Saved!'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Revert optimistic update on error
      final currentState = _savedPosts[postId] ?? false;
      setState(() {
        _savedPosts[postId] = !currentState;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final isDark = true; // Force dark mode for this screen as per design
    
    return Scaffold(
      backgroundColor: const Color(0xFF0B1015), // Deep dark background
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1015),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController, // need to add this controller
                autofocus: true,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search posts...',
                  hintStyle: GoogleFonts.inter(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                   setState(() {}); // Trigger rebuild to filter posts
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.roomName,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white70),
            onPressed: () {
               setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                  }
               });
            },
          ),
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white70),
              onPressed: _showRoomInfo,
            ),
        ],
      ),
      body: Stack(
        children: [
          // Main Content
          Column(
            children: [
               if (!_isMember)
                 Container(
                   width: double.infinity,
                   padding: const EdgeInsets.all(12),
                   color: AppTheme.primary.withValues(alpha: 0.1),
                   child: Text(
                     'Join this room to post and interact.',
                     textAlign: TextAlign.center,
                     style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.w600),
                   ),
                 ),
               Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildPostList(isDark)),
            ],
          ),

          // Custom FAB Animation (Center -> Bottom Right)
          if (_isMember && !_isReadOnly)
            AnimatedBuilder(
              animation: _fabAnimationController,
              builder: (context, child) {
                // Animate from Bottom Center to Bottom Right
                // 0.0 -> Center, 1.0 -> Right
                
                final double screenWidth = MediaQuery.of(context).size.width;
                // Center X: screenWidth/2 - fabSize/2
                // Right X: screenWidth - 16 - fabSize
                
                final double startX = (screenWidth / 2) - 28; // 56 is fab size
                final double endX = screenWidth - 16 - 56;
                
                final double currentX = ui.lerpDouble(startX, endX, Curves.easeInOut.transform(_fabAnimationController.value))!;
                final double currentY = ui.lerpDouble(40, 32, Curves.bounceOut.transform(_fabAnimationController.value))!; // slide up slightly

                return Positioned(
                  left: currentX,
                  bottom: currentY,
                  child: Hero(
                    tag: 'fab_main',
                    child: Transform.rotate(
                      angle: (1.0 - _fabAnimationController.value) * -0.5, // Keep rotation if desired, or remove
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                           color: const Color(0xFF4A90E2), // Specific blue from design
                           shape: BoxShape.circle,
                           boxShadow: [
                             BoxShadow(
                               color: Colors.black.withValues(alpha: 0.3),
                               blurRadius: 10,
                               offset: const Offset(0, 4),
                             )
                           ]
                        ),
                        child: Material( // Added Material to enable InkWell splash over Hero
                          color: Colors.transparent,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _showCreatePostSheet,
                            child: const Icon(Icons.add, color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      // Use standard bottom nav for join button only
      bottomNavigationBar: !_isMember && !_isLoading
          ? Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF151922),
              child: SafeArea(
                child: ElevatedButton(
                  onPressed: () => _joinRoom(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('Join Room', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildPostList(bool isDark) {
      // Filter posts based on search query
      final query = _searchController.text.toLowerCase();
      final displayPosts = _posts.where((p) {
         if (query.isEmpty) return true;
         final title = p['title']?.toString().toLowerCase() ?? '';
         final content = p['content']?.toString().toLowerCase() ?? '';
         final author = p['author_name']?.toString().toLowerCase() ?? '';
         return title.contains(query) || content.contains(query) || author.contains(query);
      }).toList();

      if (displayPosts.isEmpty && _posts.isNotEmpty) {
         return Center(child: Text('No results found', style: GoogleFonts.inter(color: Colors.white54)));
      }

      if (_posts.isEmpty) {
        return _buildEmptyState(isDark);
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Bottom padding for FAB
        itemCount: displayPosts.length,
        itemBuilder: (context, index) {
          final post = displayPosts[index];
          return _buildPostCard(post, isDark);
        },
      );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: Colors.white24),
          const SizedBox(height: 16),
          Text('No discussions yet', style: GoogleFonts.inter(color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, bool isDark) {
    final postId = post['id'].toString();
    final fullContent = post['content'] as String? ?? '';
    final dbTitle = post['title'] as String?;
    
    String displayContent = fullContent;
    if (dbTitle != null && dbTitle.isNotEmpty) {
      displayContent = "$dbTitle\n$fullContent";
    }
    
    final authorName = post['author_name'] ?? 'User';
    final createdAt = post['created_at'] != null ? DateTime.parse(post['created_at']) : DateTime.now();
    final upvotes = (post['upvotes'] ?? 0) as int;
    final voteScore = upvotes - ((post['downvotes'] ?? 0) as int);
    final commentCount = (post['comment_count'] ?? 0) as int;
    final isSaved = _savedPosts[postId] ?? false;
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(
              post: post,
              userEmail: widget.userEmail,
              collegeDomain: widget.collegeDomain,
            ),
          ),
        ).then((_) => _loadRoomData(silent: true));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF151922),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
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
                        radius: 16,
                        backgroundColor: Colors.purple.shade900,
                        child: Text(authorName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authorName,
                            style: GoogleFonts.inter(
                              fontSize: 14, 
                              fontWeight: FontWeight.w600,
                              color: Colors.white
                            ),
                          ),
                          Text(
                            _formatTime(createdAt),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white38
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: Colors.white38, size: 20),
                  color: const Color(0xFF1E293B),
                  onSelected: (value) {
                    if (value == 'copy') {
                      Clipboard.setData(ClipboardData(text: displayContent));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    } else if (value == 'report') {
                      _showReportDialog(context, postId, post['author_id'] ?? '');
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: [
                          const Icon(Icons.copy, color: Colors.white, size: 18),
                          const SizedBox(width: 12),
                          Text('Copy Text', style: GoogleFonts.inter(color: Colors.white)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'report',
                      child: Row(
                        children: [
                          const Icon(Icons.flag_outlined, color: Colors.redAccent, size: 18),
                          const SizedBox(width: 12),
                          Text('Report', style: GoogleFonts.inter(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Content
            Text(
              displayContent,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.9),
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            
            if (post['image_url'] != null && post['image_url'].toString().isNotEmpty) ...[
               const SizedBox(height: 12),
               ClipRRect(
                 borderRadius: BorderRadius.circular(8),
                 child: Image.network(post['image_url'], height: 150, width: double.infinity, fit: BoxFit.cover),
               ),
            ],
            
            const SizedBox(height: 16),
            
            // Footer (Actions)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // Upvote
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 20),
                      color: (_userVotes[postId] == 1) ? Colors.orange : Colors.white38,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _handleVote(postId, 1),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$voteScore',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                    // Downvote
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 20),
                      color: (_userVotes[postId] == -1) ? Colors.blue : Colors.white38,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _handleVote(postId, -1),
                    ),
                  ],
                ),
                
                // Comments
                Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, color: Colors.white38, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      '$commentCount',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white38, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),

                // Bookmark
                IconButton(
                  icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border, size: 20),
                  color: isSaved ? AppTheme.primary : Colors.white38,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _handleBookmark(postId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  void _showReportDialog(BuildContext context, String postId, String authorId) {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              
              Navigator.pop(dialogCtx); // Close dialog

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



  void _showCreatePostSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    bool isPosting = false;
    PlatformFile? selectedFile;
    GiphyGif? selectedGif;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setModalState) => Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
                    ),
                    const Spacer(),
                    Text(
                      'Create Post',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: isPosting
                          ? null
                          : () async {
                              if (contentController.text.trim().isEmpty) return;
                              setModalState(() => isPosting = true);
                              try {
                                String? imageUrl;
                                if (selectedFile != null) {
                                  imageUrl = await CloudinaryService.uploadFile(selectedFile!);
                                } else if (selectedGif != null) {
                                  imageUrl = selectedGif!.images.original?.url;
                                }
                                
                                await _supabaseService.createPost(
                                  roomId: widget.roomId,
                                  title: titleController.text.trim(),
                                  content: contentController.text.trim(),
                                  userEmail: widget.userEmail,
                                  userName: _authService.displayName ?? widget.userEmail.split('@')[0],
                                  imageUrl: imageUrl,
                                );
                                
                                if (sheetCtx.mounted) {
                                  Navigator.pop(sheetCtx);
                                }
                                if (mounted) {
                                  _loadRoomData();
                                }
                              } catch (e) {
                                if (sheetCtx.mounted) {
                                  ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                  // setModalState might be risky if unmounted, but we checked sheetCtx.mounted
                                  setModalState(() => isPosting = false);
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: isPosting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Post', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              
              // Input fields
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      if (selectedFile != null || selectedGif != null)
                        Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(
                                  image: selectedFile != null 
                                      ? (selectedFile!.bytes != null 
                                          ? MemoryImage(selectedFile!.bytes!) 
                                          : (selectedFile!.path != null 
                                              ? FileImage(File(selectedFile!.path!)) 
                                              : const AssetImage('assets/images/placeholder.png'))) as ImageProvider
                                      : NetworkImage(selectedGif!.images.original?.url ?? ''),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: () => setModalState(() {
                                  selectedFile = null;
                                  selectedGif = null;
                                }),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                            color: AppTheme.textMuted.withValues(alpha: 0.5),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: contentController,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: isDark ? Colors.white : const Color(0xFF334155),
                          height: 1.5,
                        ),
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: 'What\'s on your mind?',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 16,
                            color: AppTheme.textMuted.withValues(alpha: 0.5),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Toolbar
              Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  // Account for both keyboard and system navigation
                  bottom: (MediaQuery.of(context).viewInsets.bottom > 0
                      ? MediaQuery.of(context).viewInsets.bottom
                      : MediaQuery.of(context).padding.bottom) + 12,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                ),
                child: Row(
                  children: [
                      IconButton(
                        icon: Icon(Icons.image_outlined, color: AppTheme.primary),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.image,
                            allowMultiple: false,
                          );
                          if (result != null) {
                            setModalState(() {
                               selectedFile = result.files.first;
                               selectedGif = null; // Clear GIF if image selected
                            });
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.gif_box_outlined, color: AppTheme.primary),
                        onPressed: () async {
                          // 1. Check Premium
                          final isPremium = await SubscriptionService().isPremium();
                          
                          if (!isPremium && mounted) {
                             showDialog(
                               context: context,
                               builder: (ctx) => AlertDialog(
                                 backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                 title: Text('Premium Feature', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                                 content: Text('Sending GIFs is a premium feature. Upgrade to unlock!', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                                 actions: [
                                   TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                   ElevatedButton(
                                     onPressed: () {
                                       Navigator.pop(ctx);
                                       // Navigate to subscription screen if implemented, or show upgrade info
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Navigate to profile to upgrade!')), // Placeholder until SubscriptionScreen is linked
                                        );
                                     },
                                     child: const Text('Upgrade'),
                                   ),
                                 ],
                               ),
                             );
                             return;
                          }

                          // 2. Open Giphy Picker
                          if (!mounted) return;
                          final gif = await GiphyPicker.pickGif(
                            context: context,
                            apiKey: AppConfig.giphyApiKey,
                          );

                          if (gif != null) {
                            setModalState(() {
                              selectedGif = gif;
                              selectedFile = null; // Clear image if GIF selected
                            });
                          }
                        },
                      ),
                    IconButton(
                      icon: Icon(Icons.link_rounded, color: AppTheme.textMuted),
                      onPressed: () {
                         showDialog(
                           context: context,
                           builder: (ctx) {
                             final linkCtrl = TextEditingController();
                             return AlertDialog(
                               backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                               title: Text('Add Link', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                               content: TextField(
                                 controller: linkCtrl,
                                 style: TextStyle(color: isDark ? Colors.white : Colors.black),
                                 decoration: InputDecoration(
                                   hintText: 'https://example.com',
                                   hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
                                 ),
                               ),
                               actions: [
                                 TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                 TextButton(
                                   onPressed: () {
                                      if (linkCtrl.text.isNotEmpty) {
                                        contentController.text += '\n${linkCtrl.text}';
                                        Navigator.pop(ctx);
                                      }
                                   }, 
                                   child: const Text('Add')
                                 ),
                               ],
                             );
                           }
                         );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  
  void _showRoomInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.roomName,
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        if (widget.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              widget.description,
                              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogCtx),
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildInfoRow(
                Icons.people_outline,
                'Total Members',
                '${_roomInfo?['member_count'] ?? 0}',
                isDark,
              ),
              const SizedBox(height: 16),
              _buildInfoRow(Icons.admin_panel_settings_outlined, 'Admin', '${_roomInfo?['created_by'] ?? "Unknown"}', isDark),
              
              if (_isAdmin && _roomInfo?['is_private'] == true) ...[
                 const SizedBox(height: 16),
                 Container(
                   padding: const EdgeInsets.all(16),
                   decoration: BoxDecoration(
                     color: AppTheme.primary.withValues(alpha: 0.1),
                     borderRadius: BorderRadius.circular(12),
                     border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                   ),
                   child: Row(
                     children: [
                       Icon(Icons.vpn_key_outlined, color: AppTheme.primary),
                       const SizedBox(width: 12),
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text(
                               'Room Code',
                               style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary),
                             ),
                             Text(
                               _roomInfo?['code'] ?? 'N/A',
                               style: GoogleFonts.inter(
                                 fontSize: 18,
                                 fontWeight: FontWeight.bold,
                                 color: AppTheme.primary,
                                 letterSpacing: 2,
                               ),
                             ),
                           ],
                         ),
                       ),
                       IconButton(
                         icon: Icon(Icons.copy_rounded, color: AppTheme.primary),
                         onPressed: () {
                           Clipboard.setData(ClipboardData(text: _roomInfo?['code'] ?? ''));
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('Code copied!')),
                           );
                         },
                       ),
                     ],
                   ),
                 ),
              ],
              
              if (_isMember) ...[
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: dialogCtx,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Leave Room?'),
                          content: const Text('Are you sure you want to leave this room?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      
                      if (confirm == true) {
                        try {
                          await BackendApiService().leaveChatRoom(
                            roomId: widget.roomId,
                            context: dialogCtx,
                          );
                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx); // Close dialog
                            Navigator.pop(context); // Close room screen (using outer context)
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Left room successfully')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to leave room: $e')),
                            );
                          }
                        }
                      }
                    },
                    icon: const Icon(Icons.exit_to_app_rounded, color: Colors.white),
                    label: const Text('Leave Room'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
              
              // Delete Room (Admin only)
              if (_isAdmin) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: dialogCtx,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Room?'),
                          content: const Text('This will permanently delete the room and all its posts. This action cannot be undone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true), 
                              child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                      
                      if (confirm == true) {
                        try {
                          await _supabaseService.deleteRoom(widget.roomId);
                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx); // Close dialog
                            Navigator.pop(context); // Close room screen
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Room deleted successfully')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to delete room: $e')),
                            );
                          }
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_forever_rounded, color: Colors.white),
                    label: const Text('Delete Room (Admin)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppTheme.textMuted),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
            ),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 7) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
