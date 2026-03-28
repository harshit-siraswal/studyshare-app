import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/profile_photo_utils.dart';
import '../profile/user_profile_screen.dart';
import '../../widgets/user_avatar.dart';

class RoomDetailsScreen extends StatefulWidget {
  final String roomId;
  final String roomName;
  final String description;
  final String userEmail;
  final bool isAdmin;
  final bool isMember;
  final int? activeMemberCount;
  final Map<String, dynamic>? initialRoomInfo;
  final VoidCallback? onManageMembers;

  const RoomDetailsScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.description,
    required this.userEmail,
    required this.isAdmin,
    required this.isMember,
    this.activeMemberCount,
    this.initialRoomInfo,
    this.onManageMembers,
  });

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final BackendApiService _backendApiService = BackendApiService();

  bool _isLoading = true;
  bool _isLeaving = false;
  String? _loadError;
  Map<String, dynamic>? _roomInfo;
  List<Map<String, dynamic>> _members = [];
  ({int total, int today}) _postCounts = (total: 0, today: 0);

  bool get _isAdmin {
    if (widget.isAdmin) return true;
    return _members.any((member) => _isAdminMember(member, widget.userEmail));
  }

  bool get _isMember {
    if (widget.isMember) return true;
    return _members.any((member) => _isSameUser(member, widget.userEmail));
  }

  @override
  void initState() {
    super.initState();
    _roomInfo = widget.initialRoomInfo;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _backendApiService.getChatRoomInfo(widget.roomId),
        _supabaseService.getRoomMembers(widget.roomId),
        _supabaseService.getRoomPostCounts(widget.roomId),
      ]);

      final roomPayload = (results[0] as Map?) ?? const {};
      final roomMapRaw = roomPayload['room'];
      final roomMap = roomMapRaw is Map
          ? Map<String, dynamic>.from(roomMapRaw)
          : Map<String, dynamic>.from(roomPayload);
      final membersRaw = (results[1] as List?) ?? const [];
      final members = membersRaw
          .whereType<Map>()
          .map((member) => Map<String, dynamic>.from(member))
          .toList();

      // Keep local room info shape compatible with existing UI fallbacks.
      roomMap['isMember'] = roomPayload['isMember'] == true;
      roomMap['isAdmin'] = roomPayload['isAdmin'] == true;
      if (roomMap['created_by_email'] == null &&
          roomMap['created_by'] != null) {
        roomMap['created_by_email'] = roomMap['created_by'];
      }
      if (roomMap['member_count'] == null) {
        roomMap['member_count'] = members.length;
      }

      if (!mounted) return;

      setState(() {
        _roomInfo = roomMap;
        _members = members;
        _postCounts = results[2] as ({int total, int today});
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('ROOM_DETAILS_ERROR: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Failed to load room details: $e';
      });
    }
  }

  Future<void> _updateRoomCodeVisibility(bool value) async {
    try {
      final result = await _backendApiService.updateRoomCodeVisibility(
        roomId: widget.roomId,
        showRoomCode: value,
      );
      if (!mounted) return;
      setState(() {
        _roomInfo = {
          ...?_roomInfo,
          'show_room_code': result['show_room_code'] ?? value,
        };
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update visibility: $e')),
      );
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
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = (member['user_email'] ?? '').toString().trim();
    if (email.isNotEmpty && email.contains('@')) {
      return email.split('@').first;
    }
    return 'Member';
  }

  bool _isSameUser(Map<String, dynamic> member, String email) {
    final memberEmail = (member['user_email'] ?? '').toString().toLowerCase();
    return memberEmail.isNotEmpty && memberEmail == email.trim().toLowerCase();
  }

  bool _isAdminMember(Map<String, dynamic> member, String email) {
    if (!_isSameUser(member, email)) return false;
    final role = (member['role'] ?? 'member').toString().toLowerCase();
    return role == 'admin';
  }

  Future<void> _handleLeaveRoom() async {
    if (_isLeaving) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Room?'),
        content: const Text('Are you sure you want to leave this room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _isLeaving = true);

    try {
      await _backendApiService.leaveChatRoom(
        roomId: widget.roomId,
        context: context,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLeaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to leave room: $e')));
    }
  }

  Future<void> _handleDeleteRoom() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete room?'),
        content: const Text(
          'This will permanently delete this room and all room posts.',
        ),
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

    if (confirm != true || !mounted) return;

    try {
      await _backendApiService.deleteChatRoom(widget.roomId);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Room deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete room: $e')));
    }
  }

  Widget _pill({
    required String label,
    required bool isDark,
    Color? background,
    Color? foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:
            background ??
            (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: foreground ?? (isDark ? Colors.white70 : Colors.black54),
        ),
      ),
    );
  }

  Widget _memberTile(
    Map<String, dynamic> member,
    bool isDark, {
    bool showFounderBadge = false,
  }) {
    final role = (member['role'] ?? 'member').toString().toLowerCase();
    final isFounder =
        member['is_founder'] == true ||
        showFounderBadge ||
        _isSameUser(member, (_roomInfo?['created_by_email'] ?? '').toString());
    final isSelf = _isSameUser(member, widget.userEmail);
    final photoUrl = _resolvePhotoUrl(member, const [
      'profile_photo_url',
      'photo_url',
      'avatar_url',
    ]);

    return InkWell(
      onTap: () => _openMemberProfile(member, photoUrl),
      onLongPress: () {
        if (!_isAdmin || isFounder || isSelf) return;
        _showMemberActions(member, role, isDark);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              radius: 18,
              displayName: _memberDisplayName(member),
              photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _memberDisplayName(member),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (isFounder)
                        _pill(
                          label: 'Founder',
                          isDark: isDark,
                          background: const Color(0x268B5CF6),
                          foreground: const Color(0xFF8B5CF6),
                        ),
                      if (!isFounder && role == 'admin')
                        _pill(
                          label: 'Admin',
                          isDark: isDark,
                          background: const Color(0x261EAEDB),
                          foreground: const Color(0xFF1EAEDB),
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

  void _openMemberProfile(Map<String, dynamic> member, String photoUrl) {
    final email = (member['user_email'] ?? '').toString().trim();
    if (email.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userEmail: email,
          userName: _memberDisplayName(member),
          userPhotoUrl: photoUrl.isNotEmpty ? photoUrl : null,
        ),
      ),
    );
  }

  void _showMemberActions(
    Map<String, dynamic> member,
    String role,
    bool isDark,
  ) {
    final email = (member['user_email'] ?? '').toString().trim();
    if (email.isEmpty) return;
    final isAdminRole = role == 'admin';

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              if (!isAdminRole)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Make Admin'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _updateMemberRole(email, 'admin');
                  },
                ),
              if (isAdminRole)
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Remove Admin'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _updateMemberRole(email, 'member');
                  },
                ),
              if (!isAdminRole)
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: const Text('Remove from Room'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _removeMember(email);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateMemberRole(String email, String role) async {
    try {
      await _backendApiService.updateRoomMemberRole(
        roomId: widget.roomId,
        targetEmail: email,
        role: role,
      );
      await _loadDetails();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update role: $e')));
    }
  }

  Future<void> _removeMember(String email) async {
    try {
      await _backendApiService.removeRoomMember(
        roomId: widget.roomId,
        targetEmail: email,
      );
      await _loadDetails();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove member: $e')));
    }
  }

  Widget _sectionTitle(String text, bool isDark) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white70 : Colors.black54,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading && _roomInfo == null && _members.isEmpty) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B1015) : Colors.white,
        appBar: AppBar(
          title: const Text('Room Page'),
          backgroundColor: isDark ? const Color(0xFF0B1015) : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final createdByEmail =
        ((_roomInfo?['created_by_email'] ??
                    _roomInfo?['created_by'] ??
                    _roomInfo?['createdBy'] ??
                    '')
                .toString())
            .trim()
            .toLowerCase();
    final memberCount = _members.isNotEmpty
        ? _members.length
        : (_roomInfo?['member_count'] ?? 0);
    final activeLabel = widget.activeMemberCount != null
        ? widget.activeMemberCount == 0
              ? 'No active members'
              : '${widget.activeMemberCount} active now'
        : null;

    final admins = _members.where((member) {
      final role = (member['role'] ?? '').toString().toLowerCase();
      return role == 'admin' ||
          member['is_founder'] == true ||
          _isSameUser(member, createdByEmail);
    }).toList();
    final nonAdmins = _members.where((member) {
      final role = (member['role'] ?? '').toString().toLowerCase();
      final isFounder =
          member['is_founder'] == true || _isSameUser(member, createdByEmail);
      return role != 'admin' && !isFounder;
    }).toList();
    final roomCode =
        ((_roomInfo?['room_code'] ?? _roomInfo?['code'] ?? '').toString())
            .trim();
    final isPrivate =
        _roomInfo?['is_private'] == true || _roomInfo?['is_private'] == 'true';
    final showRoomCode = (_roomInfo?['show_room_code'] ?? true) == true;
    final canShowRoomCode =
        isPrivate && roomCode.isNotEmpty && (showRoomCode || _isAdmin);
    final dividerColor = isDark ? Colors.white12 : Colors.black12;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1015) : Colors.white,
      appBar: AppBar(
        title: const Text('Room Page'),
        backgroundColor: isDark ? const Color(0xFF0B1015) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadDetails,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDetails,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
          children: [
            if (_isLoading) const LinearProgressIndicator(minHeight: 2),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _loadError!,
                  style: GoogleFonts.inter(color: Colors.redAccent),
                ),
              ),
            Text(
              widget.roomName,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            if (widget.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.description,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            if (activeLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  activeLabel,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Members $memberCount',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
                Text(
                  'Posts ${_postCounts.total}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Today ${_postCounts.today}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: dividerColor, height: 1),
            if (canShowRoomCode) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Room code: $roomCode',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy room code',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: roomCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')),
                      );
                    },
                    icon: Icon(Icons.copy_rounded, color: AppTheme.primary),
                  ),
                ],
              ),
            ],
            if (_isAdmin && isPrivate) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Show room code to members',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ),
                  Switch(
                    value: showRoomCode,
                    activeColor: AppTheme.primary,
                    onChanged: (value) => _updateRoomCodeVisibility(value),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            _sectionTitle('Admins', isDark),
            const SizedBox(height: 4),
            if (admins.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No admins found',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: admins.length,
                separatorBuilder: (_, __) => Divider(color: dividerColor),
                itemBuilder: (context, index) => _memberTile(
                  admins[index],
                  isDark,
                  showFounderBadge:
                      admins[index]['is_founder'] == true ||
                      _isSameUser(admins[index], createdByEmail),
                ),
              ),
            if (nonAdmins.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(color: dividerColor, height: 1),
              const SizedBox(height: 14),
              _sectionTitle('Members', isDark),
              const SizedBox(height: 4),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: nonAdmins.length,
                separatorBuilder: (_, __) => Divider(color: dividerColor),
                itemBuilder: (context, index) =>
                    _memberTile(nonAdmins[index], isDark),
              ),
            ],
            if (_isAdmin && widget.onManageMembers != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onManageMembers?.call();
                  },
                  icon: const Icon(Icons.group_outlined),
                  label: const Text('Manage Members'),
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
            if (_isAdmin) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleDeleteRoom,
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Delete Room'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
            if (_isMember) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLeaving ? null : _handleLeaveRoom,
                  icon: const Icon(Icons.exit_to_app_rounded),
                  label: Text(_isLeaving ? 'Leaving...' : 'Leave Room'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
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
    );
  }
}
