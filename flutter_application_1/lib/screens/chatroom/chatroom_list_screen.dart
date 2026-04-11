import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../services/supabase_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/auth_service.dart';

import '../profile/saved_posts_screen.dart';
import '../../services/subscription_service.dart';
import '../../utils/admin_access.dart';
import 'chatroom_screen.dart';
import 'discover_rooms_screen.dart';

class ChatroomListScreen extends StatefulWidget {
  final String collegeId;
  final String collegeDomain;
  final String userEmail;

  const ChatroomListScreen({
    super.key,
    required this.collegeId,
    required this.collegeDomain,
    required this.userEmail,
  });

  @override
  State<ChatroomListScreen> createState() => _ChatroomListScreenState();
}

class _ChatroomListScreenState extends State<ChatroomListScreen> {
  // Bottom bar reserve = nav bar (~96) + safe-area/inset (~24) + visual gap (~28).
  static const double _bottomNavSpacing = 148.0;

  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchFocused = false;
  bool _isTeacherOrAdmin = false;

  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _filteredRooms = [];
  Set<String> _joinedRoomIds = {};
  bool _isLoading = true;

  bool get _isReadOnly {
    if (_isTeacherOrAdmin) return false;
    if (_hasCollegeEmailAccess) return false;
    return true;
  }

  bool get _hasCollegeEmailAccess {
    final email = widget.userEmail.trim().toLowerCase();
    final domain = widget.collegeDomain.trim().toLowerCase();
    if (email.isEmpty || domain.isEmpty) return false;
    final normalizedDomain = domain.startsWith('@') ? domain : '@$domain';
    return email.endsWith(normalizedDomain);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _supabaseService.attachContext(context);
      }
    });
    _searchFocusNode.addListener(_onSearchFocusChange);
    if (_hasCollegeEmailAccess) {
      _loadRooms();
    }
    _loadWriterRole(loadRoomsWhenFinished: !_hasCollegeEmailAccess);
  }

  void _onSearchFocusChange() {
    if (!mounted) return;
    setState(() {
      _isSearchFocused = _searchFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    if (_isReadOnly) {
      if (mounted) {
        setState(() {
          _rooms = [];
          _filteredRooms = [];
          _joinedRoomIds = <String>{};
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final results = await Future.wait<Object?>([
        _supabaseService.getChatRooms(widget.userEmail, widget.collegeId),
        _supabaseService.getUserRoomIds(widget.userEmail),
      ]);
      final rooms = (results[0] as List).cast<Map<String, dynamic>>();
      final joinedIds = results[1] as List;
      final joinedIdSet = joinedIds
          .map((id) => id.toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      // Filter to show only joined rooms
      final joinedRooms = rooms.where((r) {
        final roomId = r['id']?.toString().trim() ?? '';
        return roomId.isNotEmpty && joinedIdSet.contains(roomId);
      }).toList();

      if (mounted) {
        setState(() {
          _rooms = joinedRooms;
          _filteredRooms = joinedRooms;
          _joinedRoomIds = joinedIdSet;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ChatroomListScreen._loadRooms failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterRooms(String query) {
    setState(() {
      _filteredRooms = _rooms.where((room) {
        final name = room['name']?.toString().toLowerCase() ?? '';
        return name.contains(query.toLowerCase());
      }).toList();
    });
  }

  Future<void> _loadWriterRole({bool loadRoomsWhenFinished = false}) async {
    try {
      final authIdentity = _authService.currentIdentity;
      if (authIdentity != null) {
        if (!mounted) return;
        setState(() {
          _isTeacherOrAdmin = authIdentity.canPostNotices;
        });
        if (loadRoomsWhenFinished) {
          await _loadRooms();
        }
        return;
      }

      final profile = await _supabaseService.getCurrentUserProfile(
        maxAttempts: 1,
      );
      if (!mounted) return;
      setState(() {
        _isTeacherOrAdmin =
            profile.isNotEmpty && isTeacherOrAdminProfile(profile);
      });
      if (loadRoomsWhenFinished) {
        await _loadRooms();
      }
    } catch (e, st) {
      debugPrint('ChatroomListScreen._loadWriterRole failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isTeacherOrAdmin = false;
      });
      if (loadRoomsWhenFinished) {
        await _loadRooms();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Force dark mode look if user wants strict adherence to the dark UI image
    // But respecting theme toggle is better practice.
    // Given "strict adherence", I will follow the image style which is Dark.
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Minimalist Design Colors (Image 1)
    // Bg: Black
    // Card: Dark Grey ~#1C1C1E

    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      resizeToAvoidBottomInset: false, // Fix bottom actions/nav from jumping up
      body: SafeArea(
        bottom: false,
        child: _isReadOnly
            ? _buildAccessLockedState(isDark)
            : Column(
                children: [
                  const SizedBox(height: 16),
                  _buildSearchRow(isDark),
                  const SizedBox(height: 24),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadRooms,
                      color: Colors.white,
                      backgroundColor: const Color(0xFF1C1C1E),
                      child: _isLoading
                          ? _buildLoadingSkeleton(isDark)
                          : _filteredRooms.isEmpty
                          ? _buildEmptyState(isDark)
                          : _buildRoomList(isDark, cardColor),
                    ),
                  ),
                ],
              ),
      ),
      // Image 1 shows + button in header range, not as FAB
      // But if scrolling list, FAB is standard.
      // Image 1 has + button at TOP RIGHT next to search bar.
      // So I will implement that and remove FAB.
    );
  }

  Widget _buildSearchRow(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _filterRooms,
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: 'Search rooms...',
                hintStyle: GoogleFonts.inter(
                  color: isDark
                      ? const Color(0xFF8E8E93)
                      : Colors.grey.shade400,
                  fontSize: 16,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? Colors.grey : Colors.black54,
                ),
                // Show clear button when focused
                suffixIcon: _isSearchFocused
                    ? IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark ? Colors.grey : Colors.black54,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _filterRooms('');
                          _searchFocusNode.unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: isDark
                      ? const BorderSide(color: Colors.white24)
                      : const BorderSide(color: Colors.black12),
                ),
              ),
            ),
          ),
          if (!_isSearchFocused) ...[
            const SizedBox(width: 12),
            // Saved Button
            Tooltip(
              message: 'Saved Posts',
              child: Material(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SavedPostsScreen(userEmail: widget.userEmail),
                      ),
                    );
                    _loadRooms();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.bookmark_border_rounded,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Add Button
            Material(
              color: isDark ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(30),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _navigateToDiscoverRooms,
                borderRadius: BorderRadius.circular(30),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.add_rounded,
                    color: isDark ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget buildCollegeAccessGate(bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, _bottomNavSpacing),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Rooms are locked for this account',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Login with college ID to access it.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.45,
                  color: isDark
                      ? const Color(0xFFB0B0B8)
                      : const Color(0xFF5B6472),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoomList(bool isDark, Color cardColor) {
    final extraBottomPadding =
        MediaQuery.of(context).padding.bottom + _bottomNavSpacing;
    return ListView.separated(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 0,
        bottom: extraBottomPadding,
      ),
      itemCount: _filteredRooms.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final room = _filteredRooms[index];
        return _buildRoomCard(room, isDark, cardColor);
      },
    );
  }

  Widget _buildRoomCard(
    Map<String, dynamic> room,
    bool isDark,
    Color cardColor,
  ) {
    final memberCount = _safeMemberCount(room['member_count']);

    // "Last activity: 2m ago" - dummy for now or based on updated_at
    final updatedAt = room['updated_at'] ?? room['created_at'];
    final timeStr = _formatTimeAgo(updatedAt);
    final roomName = _roomText(room, 'name', fallback: 'Untitled');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async => _handleRoomTap(room),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                roomName,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.w500, // Medium weight as per image look
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),

              // Member Row
              Row(
                children: [
                  Icon(
                    Icons.group_outlined,
                    size: 18,
                    color: const Color(0xFF8E8E93),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$memberCount Members', // Formatting K? e.g. 4.2K
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: const Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Activity Row
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 18,
                    color: const Color(0xFF8E8E93),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Last activity: $timeStr',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: const Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),

              // If private, maybe an icon? Image 1 doesn't explicitly show private lock but it's good UX.
              // I will add a small lock icon top right if private, subtle.
            ],
          ),
        ),
      ),
    );
  }

  // ... helper methods ...

  Future<void> _handleRoomTap(Map<String, dynamic> room) async {
    if (_isReadOnly) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Read-only access')));
      return;
    }

    final roomId = room['id']?.toString().trim() ?? '';
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open this room right now.')),
      );
      return;
    }

    final isPrivate = room['is_private'] == true;
    final isMember = _joinedRoomIds.contains(roomId);

    if (isPrivate && !isMember) {
      _showJoinRoomDialog();
      return;
    }

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatRoomScreen(
            roomId: roomId,
            roomName: _roomText(room, 'name', fallback: 'Chat Room'),
            description: _roomText(room, 'description'),
            userEmail: widget.userEmail,
            collegeDomain: widget.collegeDomain,
          ),
        ),
      );
    } catch (e) {
      debugPrint('ChatroomListScreen._handleRoomTap failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open room right now.')),
      );
    }
  }

  int _extractCountFromMap(Map raw) {
    final nested = raw['count'];
    if (nested is int) return nested;
    return int.tryParse(nested?.toString() ?? '') ?? 0;
  }

  int _safeMemberCount(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? 0;
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map) {
        return _extractCountFromMap(first);
      }
    }
    if (raw is Map) {
      return _extractCountFromMap(raw);
    }
    return 0;
  }

  String _formatTimeAgo(dynamic rawDate) {
    final dateStr = rawDate?.toString().trim() ?? '';
    if (dateStr.isEmpty) return 'Recently';
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';
      return 'Long ago';
    } catch (e) {
      return 'Recently';
    }
  }

  String _roomText(
    Map<String, dynamic> room,
    String key, {
    String fallback = '',
  }) {
    final value = room[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  // Simplify Dialogs for brevity in this rewrite, keeping styles consistent

  // ignore: unused_element
  void _showCreateOrJoinDialog() {
    // Standard bottom sheet selector
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.blue),
              ),
              title: Text(
                'Create Room',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _showCreateRoomDialog();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.login, color: Colors.green),
              ),
              title: Text(
                'Join Room',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              onTap: () {
                Navigator.pop(context);
                _showJoinRoomDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showJoinRoomDialog() async {
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
    // Implementation same as before but minimal style
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeController = TextEditingController();
    try {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          title: Text(
            'Join Room',
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
          content: TextField(
            controller: codeController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Enter Code',
              filled: true,
              fillColor: isDark ? Colors.black45 : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final parentContext = this.context;
                final messenger = ScaffoldMessenger.of(parentContext);
                // Join logic
                if (codeController.text.isNotEmpty) {
                  try {
                    await BackendApiService().joinChatRoom(
                      codeController.text.trim(),
                      widget.userEmail,
                      widget.collegeId,
                    );
                    if (!parentContext.mounted) return;
                    Navigator.of(parentContext).pop();
                    _loadRooms();
                  } catch (e) {
                    if (!parentContext.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('Failed to join room: $e')),
                    );
                  }
                }
              },
              child: const Text('Join'),
            ),
          ],
        ),
      );
    } finally {
      codeController.dispose();
    }
  }

  Future<void> _showCreateRoomDialog() async {
    if (_isReadOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Read-only access. Use your college email to create rooms.',
          ),
        ),
      );
      return;
    }
    // Minimal implementation
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController();
    bool isPrivate = false;
    bool isPermanent = false;

    // Check premium status
    final subService = SubscriptionService();
    final isPremium = await subService.isPremium();

    if (!mounted) return;

    try {
      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            title: Text(
              'Create Room',
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Room Name',
                    filled: true,
                    fillColor: isDark ? Colors.black45 : Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: Text(
                    'Private',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  value: isPrivate,
                  onChanged: (v) => setDialogState(() => isPrivate = v),
                  activeThumbColor: isDark ? Colors.white : Colors.black,
                ),
                SwitchListTile(
                  title: Row(
                    children: [
                      Text(
                        'Permanent Room',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      if (!isPremium) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PRO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    isPremium
                        ? 'Room will not expire'
                        : 'Upgrade to create permanent rooms (7 days expiry for free)',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.grey,
                    ),
                  ),
                  value: isPermanent,
                  onChanged: isPremium
                      ? (v) => setDialogState(() => isPermanent = v)
                      : null, // Disabled for free users
                  activeThumbColor: isDark ? Colors.white : Colors.black,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  final parentContext = this.context;
                  final messenger = ScaffoldMessenger.of(parentContext);
                  if (nameCtrl.text.isNotEmpty) {
                    try {
                      // Duration
                      final duration = isPermanent
                          ? SupabaseService.kUnlimitedDuration
                          : SupabaseService.kDefaultExpiryDays;
                      await _supabaseService.createChatRoom(
                        name: nameCtrl.text,
                        description: '',
                        isPrivate: isPrivate,
                        userEmail: widget.userEmail,
                        collegeId: widget.collegeId,
                        durationInDays: duration,
                      );
                      if (!parentContext.mounted) return;
                      Navigator.of(parentContext).pop();
                      _loadRooms();
                    } catch (e) {
                      if (!parentContext.mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Failed to create room. Please try again.',
                          ),
                        ),
                      );
                      // Log the actual error for debugging
                      debugPrint('Create room error: $e');
                    }
                  }
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  Widget _buildLoadingSkeleton(bool isDark) {
    final extraBottomPadding =
        MediaQuery.of(context).padding.bottom + _bottomNavSpacing;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(20, 0, 20, extraBottomPadding),
      itemCount: 5,
      separatorBuilder: (_, index) => const SizedBox(height: 16),
      itemBuilder: (_, index) => Shimmer.fromColors(
        baseColor: isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade300,
        highlightColor: isDark ? const Color(0xFF3A3A3C) : Colors.grey.shade100,
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToDiscoverRooms() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoverRoomsScreen(
          collegeId: widget.collegeId,
          collegeDomain: widget.collegeDomain,
          userEmail: widget.userEmail,
        ),
      ),
    );
    if (!mounted) return;
    _loadRooms();
  }

  Widget _buildEmptyState(bool isDark) {
    final extraBottomPadding =
        MediaQuery.of(context).padding.bottom + _bottomNavSpacing;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(32, 64, 32, extraBottomPadding),
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 64,
                color: isDark ? Colors.white24 : Colors.grey.shade300,
              ),
              const SizedBox(height: 16),
              Text(
                'No rooms joined yet',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Join a room to start chatting!',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white54 : Colors.grey,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _navigateToDiscoverRooms,
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Discover Rooms'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : Colors.black,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccessLockedState(bool isDark) {
    final extraBottomPadding =
        MediaQuery.of(context).padding.bottom + _bottomNavSpacing;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(28, 96, 28, extraBottomPadding),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 30,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Login with college ID to access it.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Rooms are only available to college-linked accounts and approved teacher/admin accounts.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  height: 1.45,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
