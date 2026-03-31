import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:giphy_picker/giphy_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/full_screen_image_viewer.dart';
import '../profile/user_profile_screen.dart';
import '../../widgets/user_badge.dart';
import 'post_detail_screen.dart';
import 'room_details_screen.dart';
import '../../services/cloudinary_service.dart';
import '../../services/subscription_service.dart';
import '../../config/app_config.dart';
import '../../models/user.dart';
import '../../widgets/paywall_dialog.dart';
import '../../widgets/user_avatar.dart';
import '../../utils/link_navigation_utils.dart';
import '../../utils/profile_photo_utils.dart';

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

class _ChatRoomScreenState extends State<ChatRoomScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();
  final BackendApiService _backendApiService = BackendApiService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  bool _isTeacherOrAdmin = false;

  bool get _isReadOnly {
    if (_isTeacherOrAdmin) return false;
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

  // Track user votes: local state for optimistic updates
  // postId -> vote direction (1, -1, 0)
  final Map<String, int> _userVotes = {};
  final Map<String, String> _profilePhotoCache = {};
  final Set<String> _profilePhotoFetchInFlight = {};

  // Realtime subscription
  RealtimeChannel? _subscription;
  RealtimeChannel? _presenceChannel;
  Timer? _reloadDebounce;
  Timer? _presenceRetryTimer;
  int _presenceRetryCount = 0;
  static const int _maxPresenceRetries = 5;
  int _activeMemberCount = 0;

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

    _loadWriterRole();
    _loadRoomData();
    if (_supabaseService.hasConfiguredSupabaseAnonKey) {
      _subscribeToPosts();
      _subscribeToPresence();
    } else {
      debugPrint(
        'Supabase anon key missing; room realtime subscriptions disabled.',
      );
    }
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    _subscription?.unsubscribe();
    _presenceChannel?.untrack();
    _presenceChannel?.unsubscribe();
    _reloadDebounce?.cancel();
    _presenceRetryTimer?.cancel();
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

      final posts = _coerceMapList(
        results[0],
      ).map(_normalizePostMetrics).toList();
      final info = _coerceMapOrNull(results[1]);
      final isAdmin = results[2] is bool ? results[2] as bool : false;

      // Handle User Room IDs (List -> Set)
      final rawUserRoomIds = results[3];
      final Set<String> memberCheckIds = (rawUserRoomIds is List)
          ? rawUserRoomIds.map((e) => e.toString()).toSet()
          : (rawUserRoomIds is Set)
          ? rawUserRoomIds.map((e) => e.toString()).toSet()
          : <String>{};

      // Handle Saved Post IDs (Set or List -> Set)
      final rawSavedPostIds = results[4];
      final Set<String> savedPostIds = (rawSavedPostIds is List)
          ? rawSavedPostIds.map((e) => e.toString()).toSet()
          : (rawSavedPostIds is Set)
          ? rawSavedPostIds.map((e) => e.toString()).toSet()
          : <String>{};

      final userVotes = _coerceStringIntMap(results[5]);

      // Update saved status from batch
      for (var post in posts) {
        final postId = post['id']?.toString() ?? '';
        if (postId.isNotEmpty) {
          _savedPosts[postId] = savedPostIds.contains(postId);
          _userVotes[postId] = userVotes[postId] ?? 0;
        }
      }
      _primePhotoCacheFromPosts(posts);

      if (mounted && requestId == _loadRequestId) {
        final bool prevFABVisible = !_isMember && !_isLoading && !_isReadOnly;

        setState(() {
          _posts = posts;
          _roomInfo = info;
          _isAdmin = isAdmin || (info?['isAdmin'] == true);
          _isMember =
              memberCheckIds.contains(widget.roomId) ||
              (info?['isMember'] == true);
          _isLoading = false;
        });

        final bool newFABVisible = !_isMember && !_isLoading && !_isReadOnly;
        if (!prevFABVisible && newFABVisible) {
          _fabAnimationController.reset();
          _fabAnimationController.forward();
        }
      }
    } catch (e) {
      debugPrint('Error loading room data: $e');
      if (mounted && requestId == _loadRequestId) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadWriterRole() async {
    try {
      final role = await _supabaseService.getCurrentUserRole();
      if (!mounted) return;
      setState(() {
        _isTeacherOrAdmin = role != AppRoles.readOnly;
      });
    } catch (e, st) {
      debugPrint('ChatRoomScreen._loadWriterRole failed: $e\n$st');
      if (!mounted) return;
      setState(() => _isTeacherOrAdmin = false);
    }
  }

  Future<void> _joinRoom() async {
    if (_isReadOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Read-only access. Use your college email to join rooms.',
          ),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      await _backendApiService.joinChatRoomById(widget.roomId);
      if (!mounted) return;
      await _loadRoomData();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Joined room successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Error joining room: $e')));
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToPosts() {
    if (!_supabaseService.hasConfiguredSupabaseAnonKey) {
      return;
    }

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

  String _getAnonymizedUserId() {
    // Create a deterministic non-PII identifier from email hash
    final bytes = utf8.encode("${widget.userEmail}_room_salt_${widget.roomId}");
    final digest = sha256.convert(bytes);
    return 'user_${digest.toString().substring(0, 12)}';
  }

  Future<void> _retryPresenceSubscription() async {
    if (_presenceRetryCount >= _maxPresenceRetries) {
      debugPrint(
        'Presence subscription failed after $_maxPresenceRetries attempts',
      );
      return;
    }

    // Exponential backoff: 2^retryCount seconds, capped at 30 seconds
    final delaySeconds = (pow(2, _presenceRetryCount)).clamp(1, 30).toInt();
    _presenceRetryTimer?.cancel();
    _presenceRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted) {
        debugPrint(
          'Retrying presence subscription (attempt ${_presenceRetryCount + 1})',
        );
        _subscribeToPresence();
      }
    });
  }

  void _subscribeToPresence() {
    if (!_supabaseService.hasConfiguredSupabaseAnonKey) {
      return;
    }

    _presenceRetryCount++;
    final anonymizedUserId = _getAnonymizedUserId();

    _presenceChannel = Supabase.instance.client.channel(
      'presence:room:${widget.roomId}',
      opts: RealtimeChannelConfig(
        self: true,
        enabled: true,
        key: anonymizedUserId,
      ),
    );

    _presenceChannel!
        .onPresenceSync((_) => _syncActiveMembersCount())
        .onPresenceJoin((_) => _syncActiveMembersCount())
        .onPresenceLeave((_) => _syncActiveMembersCount())
        .subscribe((status, [error]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _presenceRetryCount = 0; // Reset retry count on success
            await _presenceChannel!.track({
              'user_id': anonymizedUserId,
              'room_id': widget.roomId,
              'online_at': DateTime.now().toIso8601String(),
            });
            _syncActiveMembersCount();
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed ||
              error != null) {
            debugPrint('Presence subscribe error (status: $status): $error');
            // Retry with backoff on errors
            await _retryPresenceSubscription();
          }
        });
  }

  void _syncActiveMembersCount() {
    final states = _presenceChannel?.presenceState() ?? const [];
    if (!mounted) return;
    setState(() {
      _activeMemberCount = states.length;
    });
  }

  Future<void> _handleVote(String postId, int direction) async {
    try {
      if (_isReadOnly) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Read-only users cannot vote. Use your college email to unlock.',
            ),
          ),
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
              updatedPost['upvotes'] = max(
                0,
                _asSafeInt(updatedPost['upvotes']) - 1,
              );
            } else {
              updatedPost['downvotes'] = max(
                0,
                _asSafeInt(updatedPost['downvotes']) - 1,
              );
            }
            _userVotes[postId] = 0;
          } else {
            // Switch or Add vote
            if (currentVote == 1) {
              // Remove old upvote
              updatedPost['upvotes'] = max(
                0,
                _asSafeInt(updatedPost['upvotes']) - 1,
              );
            } else if (currentVote == -1) {
              // Remove old downvote
              updatedPost['downvotes'] = max(
                0,
                _asSafeInt(updatedPost['downvotes']) - 1,
              );
            }

            // Add new vote
            if (direction == 1) {
              updatedPost['upvotes'] = _asSafeInt(updatedPost['upvotes']) + 1;
            } else {
              updatedPost['downvotes'] =
                  _asSafeInt(updatedPost['downvotes']) + 1;
            }
            _userVotes[postId] = direction;
          }

          _posts[index] = _normalizePostMetrics(updatedPost);
        });
      }

      await _supabaseService.votePost(postId, widget.userEmail, direction);
      // Logic handled by subscription reload, or silent reload here if needed
      // _loadRoomData(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error voting: $e')));
        _loadRoomData(silent: true);
      }
    }
  }

  Future<void> _handleBookmark(String postId) async {
    final currentlySaved = _savedPosts[postId] ?? false;
    final originalState = currentlySaved;

    try {
      if (_authService.currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please sign in to save posts')),
          );
        }
        return;
      }
      if (_isReadOnly) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Read-only users cannot save posts. Use your college email to unlock.',
            ),
          ),
        );
        return;
      }

      // Optimistic UI update
      setState(() {
        _savedPosts[postId] = !currentlySaved;
      });

      if (currentlySaved) {
        await _supabaseService.unsavePost(
          postId,
          widget.userEmail,
          roomId: widget.roomId,
        );
      } else {
        await _supabaseService.savePost(
          postId,
          widget.userEmail,
          roomId: widget.roomId,
        );
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
      setState(() {
        _savedPosts[postId] = originalState;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  ImageProvider _getImageProvider(PlatformFile? file, GiphyGif? gif) {
    if (gif != null) {
      final url = gif.images.original?.url;
      if (url != null && url.isNotEmpty) {
        return NetworkImage(url);
      }
    }
    if (file != null) {
      if (file.bytes != null) return MemoryImage(file.bytes!);
      if (file.path != null) return FileImage(File(file.path!));
    }
    return const AssetImage('assets/images/placeholder.png');
  }

  @override
  Widget build(BuildContext context) {
    // Respect system theme/settings
    final isDark = Theme.of(context).brightness == Brightness.dark;
    assert(() {
      _showRoomInfo;
      return true;
    }());

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0B1015)
          : const Color(0xFFF5F5F7), // Deep dark or light grey
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0B1015) : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : Colors.black,
                ),
                decoration: InputDecoration(
                  hintText: 'Search posts...',
                  hintStyle: GoogleFonts.inter(
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {}); // Trigger rebuild to filter posts
                },
              )
            : InkWell(
                onTap: _openRoomDetails,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.roomName,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        _activeMemberCount <= 0
                            ? 'No active members'
                            : '$_activeMemberCount active now',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
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
            PopupMenuButton<String>(
              tooltip: 'Room options',
              padding: EdgeInsets.zero,
              color: isDark ? const Color(0xFF111827) : Colors.white,
              elevation: 8,
              offset: const Offset(0, 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (value) async {
                if (value == 'sort_recent') {
                  if (_sortBy == 'recent') return;
                  setState(() => _sortBy = 'recent');
                  await _loadRoomData();
                } else if (value == 'sort_top') {
                  if (_sortBy == 'top') return;
                  setState(() => _sortBy = 'top');
                  await _loadRoomData();
                } else if (value == 'refresh') {
                  await _loadRoomData();
                } else if (value == 'leave') {
                  if (!_isMember) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('You are not in this room')),
                    );
                    return;
                  }

                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Leave Room?'),
                      content: const Text(
                        'Are you sure you want to leave this room?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            'Leave',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (confirm != true) return;
                  if (!context.mounted) return;

                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  try {
                    await _backendApiService.leaveChatRoom(
                      roomId: widget.roomId,
                      context: context,
                    );
                    if (!context.mounted) return;
                    navigator.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Left room successfully')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('Failed to leave room: $e')),
                    );
                  }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  height: 36,
                  child: Text(
                    'Sort posts',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'sort_recent',
                  height: 44,
                  child: Row(
                    children: [
                      Icon(
                        _sortBy == 'recent'
                            ? Icons.check_circle
                            : Icons.schedule,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Most Recent',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sort_top',
                  height: 44,
                  child: Row(
                    children: [
                      Icon(
                        _sortBy == 'top'
                            ? Icons.check_circle
                            : Icons.trending_up,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Top Voted',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'refresh',
                  height: 44,
                  child: Row(
                    children: [
                      Icon(
                        Icons.refresh,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Refresh',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isMember) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'leave',
                    height: 44,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.exit_to_app_rounded,
                          size: 18,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Leave Room',
                          style: GoogleFonts.inter(color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.more_vert,
                  color: isDark ? Colors.white70 : Colors.black54,
                  size: 18,
                ),
              ),
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
                    _isReadOnly
                        ? 'Read-only access. Use your college email to join this room.'
                        : 'Join this room to post and interact.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildPostList(isDark),
              ),
            ],
          ),

          // Custom FAB (Bottom Right)
          if (_isMember && !_isReadOnly)
            Positioned(
              right: 16,
              bottom: 32,
              child: Hero(
                tag: 'room_fab_main',
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
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _showCreatePostSheet,
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      // Floating Animated Join Button
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (!_isMember && !_isLoading && !_isReadOnly)
          ? AnimatedBuilder(
              animation: _fabAnimationController,
              builder: (context, child) {
                final value = Curves.elasticOut.transform(
                  _fabAnimationController.value.clamp(0.0, 1.0),
                );
                return Transform.translate(
                  offset: Offset(0, 50 * (1 - value)),
                  child: Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.9,
                      height: 56,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF4A90E2,
                            ).withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: _joinRoom,
                          child: Center(
                            child: Text(
                              'Join Room',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
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
      return title.contains(query) ||
          content.contains(query) ||
          author.contains(query);
    }).toList();

    if (displayPosts.isEmpty && _posts.isNotEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: GoogleFonts.inter(
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      );
    }

    if (_posts.isEmpty) {
      return _buildEmptyState(isDark);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        18,
        18,
        18,
        108,
      ), // Bottom padding for FAB
      itemCount: displayPosts.length,
      itemBuilder: (context, index) {
        final post = displayPosts[index];
        final stablePostKey = ValueKey(
          post['id']?.toString() ?? post['postId']?.toString() ?? 'post_$index',
        );
        return TweenAnimationBuilder<double>(
          key: stablePostKey,
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 400 + (index * 50).clamp(0, 400)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 30 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: _buildPostCard(post, isDark),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 16),
          Text(
            'No discussions yet',
            style: GoogleFonts.inter(
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, bool isDark) {
    final postId = post['id']?.toString() ?? '';
    final parts = _extractPostParts(post);
    final titleText = parts.title;
    final bodyText = parts.body;
    final displayContent = [
      if (titleText.isNotEmpty) titleText,
      if (bodyText.isNotEmpty) bodyText,
    ].join('\n');

    final authorName = post['author_name'] ?? 'User';
    final authorEmail = (post['author_email'] ?? post['user_email'] ?? '')
        .toString();
    final isAuthor =
        authorEmail.isNotEmpty &&
        authorEmail.toLowerCase() == widget.userEmail.toLowerCase();
    final canEdit = !_isReadOnly && isAuthor;
    final canDelete = !_isReadOnly && (isAuthor || _isAdmin);
    final createdAt =
        DateTime.tryParse(post['created_at']?.toString() ?? '') ??
        DateTime.now();
    final upvotes = _asSafeInt(post['upvotes']);
    final downvotes = _asSafeInt(post['downvotes']);
    final commentCount = _asSafeInt(post['comment_count']);
    final isSaved = _savedPosts[postId] ?? false;

    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.white38 : Colors.black54;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E8F0);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(
              post: post,
              userEmail: widget.userEmail,
              collegeDomain: widget.collegeDomain,
              roomId: widget.roomId,
              isRoomAdmin: _isAdmin,
            ),
          ),
        ).then((_) => _loadRoomData(silent: true));
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) {
                final normalizedEmail = _normalizeEmail(authorEmail);
                final cachedPhoto = _profilePhotoCache[normalizedEmail];
                final photoUrl = _resolvePhotoUrl(post, const [
                  'author_photo_url',
                  'profile_photo_url',
                  'photo_url',
                  'avatar_url',
                ]);
                final resolvedPhoto =
                    (cachedPhoto != null && cachedPhoto.isNotEmpty)
                    ? cachedPhoto
                    : photoUrl;
                if (resolvedPhoto.isEmpty && normalizedEmail.isNotEmpty) {
                  _ensureProfilePhotoCached(normalizedEmail);
                }
                final bool hasPhoto = resolvedPhoto.isNotEmpty;

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserProfileScreen(
                          userEmail: authorEmail,
                          userName: authorName,
                          userPhotoUrl: hasPhoto ? resolvedPhoto : null,
                        ),
                      ),
                    );
                  },
                  child: UserAvatar(
                    radius: 18,
                    displayName: authorName,
                    photoUrl: hasPhoto ? resolvedPhoto : null,
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      UserBadge(email: authorEmail, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(createdAt),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        tooltip: 'Post options',
                        padding: EdgeInsets.zero,
                        color: isDark ? const Color(0xFF111827) : Colors.white,
                        elevation: 10,
                        offset: const Offset(0, 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white10
                                : Colors.black.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.more_horiz_rounded,
                            color: secondaryTextColor,
                            size: 18,
                          ),
                        ),
                        onSelected: (value) async {
                          if (value == 'copy') {
                            Clipboard.setData(
                              ClipboardData(text: displayContent),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                              ),
                            );
                          } else if (value == 'edit') {
                            await _showEditPostSheet(post);
                          } else if (value == 'delete') {
                            await _confirmDeletePost(post);
                          } else if (value == 'report') {
                            _showReportDialog(
                              context,
                              postId,
                              post['author_id'] ?? '',
                            );
                          }
                        },
                        itemBuilder: (context) {
                          final items = <PopupMenuEntry<String>>[
                            PopupMenuItem(
                              value: 'copy',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.copy_rounded,
                                    color: textColor,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Copy Text',
                                    style: GoogleFonts.inter(color: textColor),
                                  ),
                                ],
                              ),
                            ),
                          ];

                          if (canEdit) {
                            items.add(
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit_rounded,
                                      color: textColor,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Edit Post',
                                      style: GoogleFonts.inter(
                                        color: textColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          if (canDelete) {
                            items.add(
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.redAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Delete Post',
                                      style: GoogleFonts.inter(
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          items.add(const PopupMenuDivider());
                          items.add(
                            PopupMenuItem(
                              value: 'report',
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.flag_outlined,
                                    color: Colors.redAccent,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Report',
                                    style: GoogleFonts.inter(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );

                          return items;
                        },
                      ),
                    ],
                  ),
                  if (titleText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      titleText,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (bodyText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableLinkify(
                      text: bodyText,
                      onOpen: (link) async {
                        try {
                          final launched = await openStudyShareLink(
                            context,
                            rawUrl: link.url,
                            title: 'Shared link',
                          );
                          if (!launched) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Could not open: ${link.url}'),
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Failed to launch URL: $e');
                        }
                      },
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: textColor.withValues(alpha: 0.92),
                        height: 1.45,
                      ),
                      linkStyle: GoogleFonts.inter(
                        color: const Color(0xFF3B82F6),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                  if (post['image_url'] != null &&
                      post['image_url'].toString().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FullScreenImageViewer(
                              imageUrl: post['image_url'],
                              heroTag: 'post_image_$postId',
                            ),
                          ),
                        );
                      },
                      child: Hero(
                        tag: 'post_image_$postId',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            post['image_url'],
                            height: 206,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                height: 206,
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  height: 206,
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.grey.shade200,
                                  child: Icon(
                                    Icons.broken_image,
                                    color: secondaryTextColor,
                                  ),
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPostAction(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: '$commentCount',
                          color: secondaryTextColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PostDetailScreen(
                                  post: post,
                                  userEmail: widget.userEmail,
                                  collegeDomain: widget.collegeDomain,
                                  roomId: widget.roomId,
                                  isRoomAdmin: _isAdmin,
                                ),
                              ),
                            ).then((_) => _loadRoomData(silent: true));
                          },
                        ),
                      ),
                      Expanded(
                        child: _buildPostAction(
                          icon: Icons.arrow_upward_rounded,
                          label: '$upvotes',
                          color: (_userVotes[postId] == 1)
                              ? const Color(0xFFFB923C)
                              : secondaryTextColor,
                          onTap: () => _handleVote(postId, 1),
                        ),
                      ),
                      Expanded(
                        child: _buildPostAction(
                          icon: Icons.arrow_downward_rounded,
                          label: '$downvotes',
                          color: (_userVotes[postId] == -1)
                              ? const Color(0xFF38BDF8)
                              : secondaryTextColor,
                          onTap: () => _handleVote(postId, -1),
                        ),
                      ),
                      Expanded(
                        child: _buildPostAction(
                          icon: isSaved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          label: isSaved ? 'Saved' : 'Save',
                          color: isSaved
                              ? AppTheme.primary
                              : secondaryTextColor,
                          onTap: () => _handleBookmark(postId),
                        ),
                      ),
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

  Widget _buildPostAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
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
        title: Text(
          'Report Post',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Why are you reporting this post?',
              style: GoogleFonts.inter(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              style: GoogleFonts.inter(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter reason...',
                hintStyle: GoogleFonts.inter(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
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
              style: GoogleFonts.inter(color: Colors.white60),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;

              Navigator.pop(dialogCtx);

              try {
                final currentUser = _authService.currentUser;
                final reporterId = currentUser?.uid;
                if (reporterId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please sign in to report posts.'),
                    ),
                  );
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Submitting report...')),
                );

                await _backendApiService.reportPost(postId, reason, reporterId);

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Report submitted successfully.'),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to submit report: $e')),
                );
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
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(color: AppTheme.textMuted),
                      ),
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
                              if (selectedGif != null) {
                                final hasGifAccess =
                                    await _ensurePremiumGifAccess();
                                if (!hasGifAccess) return;
                              }
                              setModalState(() => isPosting = true);
                              try {
                                String? imageUrl;
                                if (selectedFile != null) {
                                  imageUrl = await CloudinaryService.uploadFile(
                                    selectedFile!,
                                  );
                                } else if (selectedGif != null) {
                                  imageUrl = selectedGif!.images.original?.url;
                                }

                                await _supabaseService.createPost(
                                  roomId: widget.roomId,
                                  title: titleController.text.trim(),
                                  content: contentController.text.trim(),
                                  userEmail: widget.userEmail,
                                  userName:
                                      _authService.displayName ??
                                      widget.userEmail.split('@')[0],
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: isPosting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Post',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                                  image: _getImageProvider(
                                    selectedFile,
                                    selectedGif,
                                  ),
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
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 20,
                                  ),
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
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF334155),
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
                  bottom:
                      (MediaQuery.of(context).viewInsets.bottom > 0
                          ? MediaQuery.of(context).viewInsets.bottom
                          : MediaQuery.of(context).padding.bottom) +
                      12,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
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
                      icon: Icon(
                        Icons.gif_box_outlined,
                        color: AppTheme.primary,
                      ),
                      onPressed: () async {
                        final hasGifAccess = await _ensurePremiumGifAccess();
                        if (!mounted || !hasGifAccess) return;
                        final gif = await GiphyPicker.pickGif(
                          context: context,
                          apiKey: AppConfig.giphyApiKey,
                          showPreviewPage: true,
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
                              backgroundColor: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : Colors.white,
                              title: Text(
                                'Add Link',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              content: TextField(
                                controller: linkCtrl,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'https://example.com',
                                  hintStyle: TextStyle(
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    if (linkCtrl.text.isNotEmpty) {
                                      contentController.text +=
                                          '\n${linkCtrl.text}';
                                      Navigator.pop(ctx);
                                    }
                                  },
                                  child: const Text('Add'),
                                ),
                              ],
                            );
                          },
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

  Future<bool> _ensurePremiumGifAccess() async {
    final hasPremium = await _subscriptionService.isPremium();
    if (hasPremium) return true;
    if (!mounted) return false;

    final messenger = ScaffoldMessenger.of(context);
    await showDialog(
      context: context,
      builder: (_) => PaywallDialog(
        onSuccess: () {
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Premium unlocked! GIF feature enabled.'),
            ),
          );
        },
      ),
    );

    if (!mounted) return false;
    return _subscriptionService.isPremium();
  }

  Future<void> _showEditPostSheet(Map<String, dynamic> post) async {
    if (_isReadOnly) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Read-only users cannot edit posts. Use your college email to unlock.',
          ),
        ),
      );
      return;
    }

    final postId = post['id']?.toString() ?? '';
    if (postId.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parts = _extractPostParts(post);
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
                                  final index = _posts.indexWhere(
                                    (entry) =>
                                        entry['id']?.toString() == postId,
                                  );
                                  if (index != -1) {
                                    final updated = Map<String, dynamic>.from(
                                      _posts[index],
                                    );
                                    updated['content'] = updatedContent;
                                    if (title.isNotEmpty) {
                                      updated['title'] = title;
                                    } else {
                                      updated.remove('title');
                                    }
                                    _posts[index] = updated;
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

  Future<void> _confirmDeletePost(Map<String, dynamic> post) async {
    if (_isReadOnly) return;
    final postId = post['id']?.toString() ?? '';
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
      setState(() {
        _posts.removeWhere((entry) => entry['id']?.toString() == postId);
        _savedPosts.remove(postId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _openRoomDetails() async {
    final didLeave = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RoomDetailsScreen(
          roomId: widget.roomId,
          roomName: widget.roomName,
          description: widget.description,
          userEmail: widget.userEmail,
          isAdmin: _isAdmin,
          isMember: _isMember,
          activeMemberCount: _activeMemberCount,
          initialRoomInfo: _roomInfo,
          onManageMembers: _isAdmin ? _showManageMembersSheet : null,
        ),
      ),
    );

    if (!mounted || didLeave != true) return;
    if (!mounted) return;
    Navigator.pop(context);
  }

  // ignore: unused_element
  void _showRoomInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
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
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: AppTheme.textMuted,
                                ),
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
                  onTap: _isAdmin
                      ? () {
                          Navigator.pop(dialogCtx);
                          _showManageMembersSheet();
                        }
                      : null,
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  Icons.admin_panel_settings_outlined,
                  'Created By',
                  '${_roomInfo?['created_by'] ?? "Unknown"}',
                  isDark,
                ),
                const SizedBox(height: 16),
                Text(
                  'Admins & Members',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _supabaseService.getRoomMembers(widget.roomId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return Text(
                        'Could not load members right now',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      );
                    }

                    final members = snapshot.data ?? const [];
                    if (members.isEmpty) {
                      return Text(
                        'No members found',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      );
                    }

                    final admins = members
                        .where(
                          (m) =>
                              (m['role'] ?? 'member')
                                  .toString()
                                  .toLowerCase() ==
                              'admin',
                        )
                        .toList();
                    final nonAdmins = members
                        .where(
                          (m) =>
                              (m['role'] ?? 'member')
                                  .toString()
                                  .toLowerCase() !=
                              'admin',
                        )
                        .toList();
                    final preview = [...admins, ...nonAdmins].take(6).toList();

                    return Column(
                      children: [
                        ...preview.map((member) {
                          final email = (member['user_email'] ?? '')
                              .toString()
                              .trim();
                          final role = (member['role'] ?? 'member')
                              .toString()
                              .toLowerCase();
                          final photoUrl = _resolvePhotoUrl(member, const [
                            'profile_photo_url',
                            'photo_url',
                            'avatar_url',
                          ]);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                UserAvatar(
                                  radius: 14,
                                  displayName: _memberDisplayName(member),
                                  photoUrl: photoUrl.isNotEmpty
                                      ? photoUrl
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _memberDisplayName(member),
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: role == 'admin'
                                        ? AppTheme.primary.withValues(
                                            alpha: 0.14,
                                          )
                                        : Colors.grey.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    role == 'admin' ? 'Admin' : 'Member',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: role == 'admin'
                                          ? AppTheme.primary
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                                if (email.toLowerCase() ==
                                    widget.userEmail.toLowerCase())
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Text(
                                      'You',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                        if (members.length > preview.length)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '+${members.length - preview.length} more',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),

                if (_isAdmin) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        _showManageMembersSheet();
                      },
                      icon: const Icon(Icons.group_outlined),
                      label: const Text('Manage Members / Make Admin'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],

                if (_isAdmin && _roomInfo?['is_private'] == true) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                      ),
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
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.primary,
                                ),
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
                          icon: Icon(
                            Icons.copy_rounded,
                            color: AppTheme.primary,
                          ),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: _roomInfo?['code'] ?? ''),
                            );
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
                            content: const Text(
                              'Are you sure you want to leave this room?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  'Leave',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          if (!dialogCtx.mounted) return;
                          if (!mounted) return;
                          final roomNavigator = Navigator.of(context);
                          final dialogNavigator = Navigator.of(dialogCtx);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await _backendApiService.leaveChatRoom(
                              roomId: widget.roomId,
                              context: dialogCtx,
                            );
                            if (!dialogCtx.mounted || !mounted) return;
                            dialogNavigator.pop(); // Close dialog
                            roomNavigator.pop(); // Close room screen
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Left room successfully'),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Failed to leave room: $e'),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(
                        Icons.exit_to_app_rounded,
                        color: Colors.white,
                      ),
                      label: const Text('Leave Room'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                            content: const Text(
                              'This will permanently delete the room and all its posts. This action cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          if (!dialogCtx.mounted) return;
                          if (!mounted) return;
                          final roomNavigator = Navigator.of(context);
                          final dialogNavigator = Navigator.of(dialogCtx);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await _supabaseService.deleteRoom(widget.roomId);
                            if (!dialogCtx.mounted || !mounted) return;
                            dialogNavigator.pop(); // Close dialog
                            roomNavigator.pop(); // Close room screen
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Room deleted successfully'),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Failed to delete room: $e'),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.white,
                      ),
                      label: const Text('Delete Room (Admin)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade900,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showManageMembersSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<Map<String, dynamic>> members = [];
    bool isLoading = true;
    bool isRemoving = false;
    bool isUpdatingRole = false;
    bool didStartLoading = false;
    String? loadError;

    Future<void> loadMembers(StateSetter setModalState) async {
      try {
        final fetched = await _supabaseService.getRoomMembers(widget.roomId);
        if (!mounted) return;
        setModalState(() {
          members = fetched;
          isLoading = false;
          loadError = null;
        });
      } catch (e) {
        if (!mounted) return;
        setModalState(() {
          isLoading = false;
          loadError = 'Failed to load members';
        });
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          if (!didStartLoading) {
            didStartLoading = true;
            Future.microtask(() => loadMembers(setModalState));
          }

          final activeUsers = (_presenceChannel?.presenceState() ?? const [])
              .map((state) => state.key.toLowerCase())
              .toSet();

          return SafeArea(
            child: Container(
              height: MediaQuery.of(context).size.height * 0.82,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Room Members',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          color: AppTheme.textMuted,
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                  ),
                  if (isLoading)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (loadError != null)
                    Expanded(
                      child: Center(
                        child: Text(
                          loadError!,
                          style: GoogleFonts.inter(color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  else if (members.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'No members found',
                          style: GoogleFonts.inter(color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: members.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final member = members[index];
                          final email = (member['user_email'] ?? '').toString();
                          final role = (member['role'] ?? 'member')
                              .toString()
                              .toLowerCase();
                          final isSelf =
                              email.toLowerCase() ==
                              widget.userEmail.toLowerCase();
                          final ownerEmail = (_roomInfo?['created_by'] ?? '')
                              .toString()
                              .toLowerCase();
                          final isOwner =
                              ownerEmail.isNotEmpty &&
                              ownerEmail == email.toLowerCase();
                          final canRemove =
                              !isSelf &&
                              !isOwner &&
                              email.isNotEmpty &&
                              !isRemoving &&
                              !isUpdatingRole;
                          final canToggleRole =
                              !isSelf &&
                              !isOwner &&
                              email.isNotEmpty &&
                              !isRemoving &&
                              !isUpdatingRole;
                          final isActive =
                              email.isNotEmpty &&
                              activeUsers.contains(email.toLowerCase());
                          final memberPhotoUrl = _resolvePhotoUrl(
                            member,
                            const [
                              'profile_photo_url',
                              'photo_url',
                              'avatar_url',
                            ],
                          );
                          final hasMemberPhoto = memberPhotoUrl.isNotEmpty;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                UserAvatar(
                                  radius: 18,
                                  displayName: _memberDisplayName(member),
                                  photoUrl: hasMemberPhoto
                                      ? memberPhotoUrl
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _memberDisplayName(member),
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        email,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${role.toUpperCase()}${isActive ? ' - Active now' : ''}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: isActive
                                              ? AppTheme.success
                                              : AppTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelf)
                                  Text(
                                    'You',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      if (canToggleRole)
                                        TextButton(
                                          onPressed: () async {
                                            final nextRole = role == 'admin'
                                                ? 'member'
                                                : 'admin';
                                            if (sheetCtx.mounted) {
                                              setModalState(
                                                () => isUpdatingRole = true,
                                              );
                                            }
                                            try {
                                              await _supabaseService
                                                  .updateRoomMemberRole(
                                                    roomId: widget.roomId,
                                                    userEmail: email,
                                                    role: nextRole,
                                                  );
                                              if (sheetCtx.mounted) {
                                                setModalState(() {
                                                  isUpdatingRole = false;
                                                  members[index] = {
                                                    ...member,
                                                    'role': nextRole,
                                                  };
                                                });
                                              }
                                              await _loadRoomData(silent: true);
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      '${nextRole == 'admin' ? 'Promoted' : 'Updated'} $email',
                                                    ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              if (sheetCtx.mounted) {
                                                setModalState(
                                                  () => isUpdatingRole = false,
                                                );
                                              }
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Failed to update role: $e',
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          child: Text(
                                            role == 'admin'
                                                ? 'Remove Admin'
                                                : 'Make Admin',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                      if (canRemove)
                                        TextButton.icon(
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: sheetCtx,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text(
                                                  'Remove member?',
                                                ),
                                                content: Text(
                                                  'Remove $email from this room?',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          false,
                                                        ),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          true,
                                                        ),
                                                    child: const Text(
                                                      'Remove',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm != true) return;

                                            if (sheetCtx.mounted) {
                                              setModalState(
                                                () => isRemoving = true,
                                              );
                                            }

                                            try {
                                              await _supabaseService
                                                  .removeRoomMember(
                                                    roomId: widget.roomId,
                                                    userEmail: email,
                                                  );

                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Removed $email from room',
                                                    ),
                                                  ),
                                                );
                                              }

                                              await _loadRoomData(silent: true);

                                              if (sheetCtx.mounted) {
                                                setModalState(() {
                                                  isRemoving = false;
                                                  members.removeAt(index);
                                                });
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Failed to remove member: $e',
                                                    ),
                                                  ),
                                                );
                                              }
                                              if (sheetCtx.mounted) {
                                                setModalState(
                                                  () => isRemoving = false,
                                                );
                                              }
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.person_remove_outlined,
                                            size: 16,
                                            color: Colors.redAccent,
                                          ),
                                          label: const Text(
                                            'Remove',
                                            style: TextStyle(
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  int _asSafeInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  List<Map<String, dynamic>> _coerceMapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Map<String, dynamic>? _coerceMapOrNull(dynamic value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  Map<String, int> _coerceStringIntMap(dynamic value) {
    if (value is! Map) return const <String, int>{};
    final normalized = <String, int>{};
    value.forEach((key, val) {
      final textKey = key.toString().trim();
      if (textKey.isEmpty) return;
      normalized[textKey] = _asSafeInt(val);
    });
    return normalized;
  }

  Map<String, dynamic> _normalizePostMetrics(Map<String, dynamic> post) {
    final normalized = Map<String, dynamic>.from(post);
    normalized['upvotes'] = _asSafeInt(normalized['upvotes']);
    normalized['downvotes'] = _asSafeInt(normalized['downvotes']);
    normalized['comment_count'] = _asSafeInt(normalized['comment_count']);
    return normalized;
  }

  String _normalizeEmail(String value) => value.trim().toLowerCase();

  void _primePhotoCacheFromPosts(List<Map<String, dynamic>> posts) {
    for (final post in posts) {
      final email = _normalizeEmail(
        post['author_email']?.toString() ??
            post['user_email']?.toString() ??
            '',
      );
      if (email.isEmpty || _profilePhotoCache.containsKey(email)) continue;
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

  String _resolvePhotoUrl(Map<String, dynamic> data, List<String> keys) {
    return resolveProfilePhotoUrl(data, preferredKeys: keys) ?? '';
  }

  String _memberDisplayName(Map<String, dynamic> member) {
    final displayName =
        (member['user_name'] ?? member['display_name'] ?? member['full_name'])
            ?.toString()
            .trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = (member['user_email'] ?? '').toString();
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return email.isNotEmpty ? email : 'Member';
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    bool isDark, {
    VoidCallback? onTap,
  }) {
    final child = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppTheme.textMuted),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
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
        ),
        if (onTap != null)
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppTheme.textMuted,
          ),
      ],
    );

    if (onTap == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: child,
      ),
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
