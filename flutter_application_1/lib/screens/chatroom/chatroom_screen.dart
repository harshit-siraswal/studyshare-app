import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../config/theme.dart';
import '../../services/cloudinary_service.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import 'post_detail_screen.dart';

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
  String _sortBy = 'recent'; // 'recent' or 'top'
  Map<String, dynamic>? _roomInfo;
  bool _isAdmin = false;
  bool _isMember = false;
  
  // Track which posts are saved (bookmarked)
  final Map<String, bool> _savedPosts = {};
  
  // Realtime subscription
  RealtimeChannel? _subscription;
  
  late AnimationController _fabAnimationController;

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
    super.dispose();
  }

  Future<void> _loadRoomData() async {
    setState(() => _isLoading = true);
    try {
      final posts = await _supabaseService.getRoomPosts(widget.roomId, sortBy: _sortBy);
      final info = await _supabaseService.getRoomInfo(widget.roomId);

      final isAdmin = await _supabaseService.isRoomAdmin(widget.roomId, widget.userEmail);
      final userRoomIds = await _supabaseService.getUserRoomIds(widget.userEmail);
      
      // Check saved status for all posts
      for (var post in posts) {
        final postId = post['id']?.toString() ?? '';
        if (postId.isNotEmpty) {
          final isSaved = await _supabaseService.isPostSaved(postId, widget.userEmail);
          _savedPosts[postId] = isSaved;
        }
      }
      
      if (mounted) {
        setState(() {
          _posts = posts;
          _roomInfo = info;
          _isAdmin = isAdmin;
          _isMember = userRoomIds.contains(widget.roomId);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinRoom() async {
    setState(() => _isLoading = true);
    try {
      // Direct insert for public room join.
      // Ensure backend RLS policies allow this for non-private rooms.
      await Supabase.instance.client.from('room_participants').insert({
        'room_id': widget.roomId,
        'user_email': widget.userEmail,
        'role': 'member',
        'joined_at': DateTime.now().toIso8601String(),
      });
      
      await _loadRoomData();
      if (mounted) {
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
    // Basic subscription to refresh on changes (simplified for now)
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
            _loadRoomData(); // Reload to respect sort order
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
      await _supabaseService.votePost(postId, widget.userEmail, direction);
      // Optimistic update could happen here, but for now we rely on reload
      _loadRoomData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error voting: $e')),
      );
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
        title: Column(
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
            icon: const Icon(Icons.search, color: Colors.white70),
            onPressed: () {},
          ),
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
                   color: AppTheme.primary.withOpacity(0.1),
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
                final double currentY = ui.lerpDouble(40, 16, Curves.bounceOut.transform(_fabAnimationController.value))!; // slide up slightly

                return Positioned(
                  left: currentX,
                  bottom: currentY,
                  child: Transform.rotate(
                    angle: (1.0 - _fabAnimationController.value) * -0.5, // Slight rotation effect
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                         color: const Color(0xFF4A90E2), // Specific blue from design
                         shape: BoxShape.circle,
                         boxShadow: [
                           BoxShadow(
                             color: Colors.black.withOpacity(0.3),
                             blurRadius: 10,
                             offset: const Offset(0, 4),
                           )
                         ]
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.add, color: Colors.white, size: 28),
                        onPressed: _showCreatePostSheet,
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
      if (_posts.isEmpty) {
        return _buildEmptyState(isDark);
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Bottom padding for FAB
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
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
    final fullContent = post['content'] as String? ?? '';
    final dbTitle = post['title'] as String?;
    
    // In strict replica, we might treat title/content similarly or merge them
    String displayContent = fullContent;
    if (dbTitle != null && dbTitle.isNotEmpty) {
      displayContent = "$dbTitle\n$fullContent";
    }
    
    final authorName = post['author_name'] ?? 'User';
    final createdAt = post['created_at'] != null ? DateTime.parse(post['created_at']) : DateTime.now();
    final upvotes = (post['upvotes'] ?? 0) as int;
    final voteScore = upvotes - ((post['downvotes'] ?? 0) as int);
    final commentCount = (post['comment_count'] ?? 0) as int;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151922), // Dark card background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
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
              const Spacer(),
              const Icon(Icons.more_horiz, color: Colors.white38, size: 20),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Content
          Text(
            displayContent,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: Colors.white.withOpacity(0.9),
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
            children: [
              // Upvote
              _buildActionIcon(Icons.arrow_upward, '${voteScore > 0 ? voteScore : "Vote"}', Colors.blue),
              const SizedBox(width: 16),
              // Downvote
              const Icon(Icons.arrow_downward, color: Colors.white38, size: 20),
              
              const SizedBox(width: 24),
              // Comments
              _buildActionIcon(Icons.chat_bubble_outline, '$commentCount', Colors.white38),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionIcon(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 13, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  void _showCreatePostSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    bool isPosting = false;
    PlatformFile? _selectedFile;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
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
                      onPressed: () => Navigator.pop(context),
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
                                if (_selectedFile != null) {
                                  imageUrl = await CloudinaryService.uploadFile(_selectedFile!);
                                }
                                
                                await _supabaseService.createPost(
                                  roomId: widget.roomId,
                                  title: titleController.text.trim(),
                                  content: contentController.text.trim(),
                                  userEmail: widget.userEmail,
                                  userName: _authService.displayName ?? widget.userEmail.split('@')[0],
                                  imageUrl: imageUrl,
                                );
                                if (mounted) {
                                  Navigator.pop(context);
                                  _loadRoomData();
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
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
                      if (_selectedFile != null)
                        Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(
                                  image: _selectedFile!.bytes != null 
                                      ? MemoryImage(_selectedFile!.bytes!) 
                                      : FileImage(File(_selectedFile!.path!)) as ImageProvider,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: () => setModalState(() => _selectedFile = null),
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
                            color: AppTheme.textMuted.withOpacity(0.5),
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
                            color: AppTheme.textMuted.withOpacity(0.5),
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
                          setModalState(() => _selectedFile = result.files.first);
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.link_rounded, color: AppTheme.textMuted),
                      onPressed: () {},
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
      builder: (context) => AlertDialog(
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
                    onPressed: () => Navigator.pop(context),
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
                     color: AppTheme.primary.withOpacity(0.1),
                     borderRadius: BorderRadius.circular(12),
                     border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
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
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Leave Room?'),
                          content: const Text('Are you sure you want to leave this room?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      
                      if (confirm == true) {
                        try {
                          await _supabaseService.leaveRoom(widget.roomId, widget.userEmail);
                          if (mounted) {
                            Navigator.pop(context); // Close dialog
                            Navigator.pop(context); // Close room screen
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Left room successfully')),
                            );
                          }
                        } catch (e) {
                          // Error
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
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
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
