import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/profile_photo_utils.dart';
import '../../widgets/user_avatar.dart';
import '../profile/user_profile_screen.dart';

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
  List<Map<String, dynamic>> _members = <Map<String, dynamic>>[];

  bool get _isAdmin {
    if (widget.isAdmin) return true;
    if (_roomInfo?['isAdmin'] == true || _roomInfo?['is_admin'] == true) {
      return true;
    }
    return _members.any((member) => _isAdminMember(member, widget.userEmail));
  }

  bool get _isMember {
    if (widget.isMember) return true;
    if (_roomInfo?['isMember'] == true || _roomInfo?['is_member'] == true) {
      return true;
    }
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

      roomMap['isMember'] = roomPayload['isMember'] == true;
      roomMap['isAdmin'] = roomPayload['isAdmin'] == true;
      if (roomMap['created_by_email'] == null &&
          roomMap['created_by'] != null) {
        roomMap['created_by_email'] = roomMap['created_by'];
      }
      final currentUserEmail = widget.userEmail.trim().toLowerCase();
      final creatorEmail =
          ((roomMap['created_by_email'] ??
                      roomMap['created_by'] ??
                      roomMap['createdBy'] ??
                      '')
                  .toString())
              .trim()
              .toLowerCase();
      final isCreator =
          currentUserEmail.isNotEmpty && currentUserEmail == creatorEmail;
      roomMap['isMember'] =
          roomMap['isMember'] == true ||
          roomMap['is_member'] == true ||
          roomPayload['isMember'] == true ||
          widget.isMember ||
          isCreator;
      roomMap['isAdmin'] =
          roomMap['isAdmin'] == true ||
          roomMap['is_admin'] == true ||
          roomPayload['isAdmin'] == true ||
          widget.isAdmin ||
          isCreator;
      if (roomMap['member_count'] == null) {
        roomMap['member_count'] = members.length;
      }

      if (!mounted) return;
      setState(() {
        _roomInfo = roomMap;
        _members = members;
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
        title: const Text('Leave room?'),
        content: const Text('You will need the room code to join again.'),
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

    if (confirm != true || !mounted) return;

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
          'This permanently deletes the room and all of its posts.',
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

  DateTime? _parseExpiryDate() {
    final raw = _roomInfo?['expiry_date'] ?? _roomInfo?['expiryDate'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  String _formatExpiry(DateTime? date) {
    if (date == null) return 'Not set';
    final local = date.isUtc ? date.toLocal() : date;
    return DateFormat('d MMM yyyy').format(local);
  }

  String _formatMemberCount(int count) {
    return '$count member${count == 1 ? '' : 's'}';
  }

  Widget _memberTile(
    Map<String, dynamic> member,
    bool isDark, {
    required bool showFounderBadge,
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              radius: 20,
              displayName: _memberDisplayName(member),
              photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _memberDisplayName(member),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      if (isFounder)
                        _buildRoleBadge(
                          'Founder',
                          isDark: isDark,
                          background: const Color(0x268B5CF6),
                          foreground: const Color(0xFF8B5CF6),
                        )
                      else if (role == 'admin')
                        _buildRoleBadge(
                          'Admin',
                          isDark: isDark,
                          background: const Color(0x261EAEDB),
                          foreground: const Color(0xFF1EAEDB),
                        ),
                    ],
                  ),
                  if (isSelf) ...[
                    const SizedBox(height: 3),
                    Text(
                      'You',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(
    String label, {
    required bool isDark,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: foreground,
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
                  title: const Text('Make admin'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _updateMemberRole(email, 'admin');
                  },
                ),
              if (isAdminRole)
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Remove admin'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _updateMemberRole(email, 'member');
                  },
                ),
              if (!isAdminRole)
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: const Text('Remove from room'),
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

  Future<void> _openAddMembersSheet() async {
    if (!_isAdmin) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _AddMembersSheet(
          roomId: widget.roomId,
          onInviteSent: _loadDetails,
        ),
      ),
    );
  }

  Widget _buildSectionBlock({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white70 : const Color(0xFF64748B),
      ),
    );
  }

  Widget _buildInfoRow({
    required bool isDark,
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
    bool accent = false,
  }) {
    final valueColor = accent
        ? AppTheme.primary
        : (isDark ? Colors.white : const Color(0xFF0F172A));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing],
      ],
    );
  }

  Widget _buildActionRow({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Color? foreground,
  }) {
    final resolvedForeground =
        foreground ?? (isDark ? Colors.white : const Color(0xFF0F172A));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: resolvedForeground.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: resolvedForeground, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: resolvedForeground,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark ? const Color(0xFF070B12) : Colors.white;
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE2E8F0);

    if (_isLoading && _roomInfo == null && _members.isEmpty) {
      return Scaffold(
        backgroundColor: pageColor,
        appBar: AppBar(
          title: const Text('Group info'),
          backgroundColor: pageColor,
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
        : (_roomInfo?['member_count'] as int? ?? 0);
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
    final roomDescription =
        ((_roomInfo?['description'] ?? widget.description).toString()).trim();
    final isPrivate =
        _roomInfo?['is_private'] == true || _roomInfo?['is_private'] == 'true';
    final showRoomCode = (_roomInfo?['show_room_code'] ?? true) == true;
    final canShowRoomCode =
        roomCode.isNotEmpty && (!isPrivate || showRoomCode || _isAdmin);
    final expiryDate = _parseExpiryDate();

    return Scaffold(
      backgroundColor: pageColor,
      appBar: AppBar(
        title: const Text('Group info'),
        backgroundColor: pageColor,
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
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 26),
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
            Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(
                      alpha: isDark ? 0.18 : 0.1,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: AppTheme.primary,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.roomName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                if (roomDescription.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    roomDescription,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.45,
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  _formatMemberCount(memberCount),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
                if (activeLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    activeLabel,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionBlock(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Details', isDark),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    isDark: isDark,
                    icon: isPrivate ? Icons.lock_rounded : Icons.public_rounded,
                    label: 'Visibility',
                    value: isPrivate ? 'Private room' : 'Public room',
                  ),
                  const SizedBox(height: 16),
                  Divider(color: dividerColor, height: 1),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    isDark: isDark,
                    icon: Icons.schedule_rounded,
                    label: 'Expiry',
                    value: _formatExpiry(expiryDate),
                  ),
                  if (canShowRoomCode) ...[
                    const SizedBox(height: 16),
                    Divider(color: dividerColor, height: 1),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      isDark: isDark,
                      icon: Icons.key_rounded,
                      label: 'Room code',
                      value: roomCode,
                      accent: true,
                      trailing: IconButton(
                        tooltip: 'Copy room code',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: roomCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code copied')),
                          );
                        },
                        icon: const Icon(
                          Icons.copy_rounded,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                  if (_isAdmin && isPrivate) ...[
                    const SizedBox(height: 16),
                    Divider(color: dividerColor, height: 1),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Show room code to members',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                showRoomCode
                                    ? 'Members can copy the code from this page.'
                                    : 'Only admins can view and share the code.',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: isDark
                                      ? Colors.white60
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch(
                          value: showRoomCode,
                          activeThumbColor: AppTheme.primary,
                          onChanged: _updateRoomCodeVisibility,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionBlock(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Administrators', isDark),
                  const SizedBox(height: 10),
                  if (admins.isEmpty)
                    Text(
                      'No admins found',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF64748B),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: admins.length,
                      separatorBuilder: (_, _) =>
                          Divider(color: dividerColor, height: 1),
                      itemBuilder: (context, index) => _memberTile(
                        admins[index],
                        isDark,
                        showFounderBadge:
                            admins[index]['is_founder'] == true ||
                            _isSameUser(admins[index], createdByEmail),
                      ),
                    ),
                  if (nonAdmins.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _buildSectionTitle('Members', isDark),
                    const SizedBox(height: 10),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: nonAdmins.length,
                      separatorBuilder: (_, _) =>
                          Divider(color: dividerColor, height: 1),
                      itemBuilder: (context, index) => _memberTile(
                        nonAdmins[index],
                        isDark,
                        showFounderBadge: false,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionBlock(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Actions', isDark),
                  const SizedBox(height: 10),
                  if (_isAdmin && widget.onManageMembers != null) ...[
                    _buildActionRow(
                      isDark: isDark,
                      icon: Icons.person_add_alt_1_rounded,
                      title: 'Add members',
                      subtitle:
                          'Invite students from your college into this room.',
                      onTap: _openAddMembersSheet,
                      foreground: AppTheme.primary,
                    ),
                    Divider(color: dividerColor, height: 1),
                    _buildActionRow(
                      isDark: isDark,
                      icon: Icons.group_outlined,
                      title: 'Manage members',
                      subtitle:
                          'Promote admins or remove members from this room.',
                      onTap: () {
                        Navigator.pop(context);
                        widget.onManageMembers?.call();
                      },
                      foreground: AppTheme.primary,
                    ),
                    Divider(color: dividerColor, height: 1),
                  ],
                  if (_isMember) ...[
                    _buildActionRow(
                      isDark: isDark,
                      icon: Icons.exit_to_app_rounded,
                      title: _isLeaving ? 'Leaving...' : 'Leave room',
                      subtitle:
                          'You will stop receiving updates from this room.',
                      onTap: _isLeaving ? null : _handleLeaveRoom,
                      foreground: Colors.redAccent,
                    ),
                    if (_isAdmin) Divider(color: dividerColor, height: 1),
                  ],
                  if (_isAdmin)
                    _buildActionRow(
                      isDark: isDark,
                      icon: Icons.delete_forever_rounded,
                      title: 'Delete room',
                      subtitle: 'Remove the room and all posts permanently.',
                      onTap: _handleDeleteRoom,
                      foreground: Colors.redAccent,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMembersSheet extends StatefulWidget {
  const _AddMembersSheet({required this.roomId, required this.onInviteSent});

  final String roomId;
  final Future<void> Function() onInviteSent;

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final BackendApiService _api = BackendApiService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _candidates = <Map<String, dynamic>>[];
  final Set<String> _pendingInviteEmails = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final rows = await _api.getRoomInviteCandidates(
        roomId: widget.roomId,
        query: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _candidates = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendInvite(Map<String, dynamic> candidate) async {
    final email = (candidate['email'] ?? '').toString().trim().toLowerCase();
    if (email.isEmpty || _pendingInviteEmails.contains(email)) return;

    setState(() {
      _pendingInviteEmails.add(email);
    });

    try {
      await _api.sendRoomInvite(roomId: widget.roomId, inviteeEmail: email);
      if (!mounted) return;
      setState(() {
        final index = _candidates.indexWhere(
          (entry) =>
              (entry['email'] ?? '').toString().trim().toLowerCase() == email,
        );
        if (index != -1) {
          final updated = Map<String, dynamic>.from(_candidates[index]);
          updated['invite_sent'] = true;
          _candidates[index] = updated;
        }
      });
      await widget.onInviteSent();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite sent')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send invite: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _pendingInviteEmails.remove(email);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final borderColor = isDark ? Colors.white10 : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Text(
                    'Add Members',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => _loadCandidates(),
                decoration: InputDecoration(
                  hintText: 'Search by name or username',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    )
                  : _candidates.isEmpty
                  ? Center(
                      child: Text(
                        'No students found.',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: _candidates.length,
                      separatorBuilder: (_, _) =>
                          Divider(color: borderColor, height: 1),
                      itemBuilder: (context, index) {
                        final candidate = _candidates[index];
                        final email = (candidate['email'] ?? '')
                            .toString()
                            .trim()
                            .toLowerCase();
                        final displayName =
                            (candidate['display_name'] ?? 'Student').toString();
                        final username = (candidate['username'] ?? '')
                            .toString()
                            .trim();
                        final photoUrl = (candidate['profile_photo_url'] ?? '')
                            .toString()
                            .trim();
                        final alreadyInRoom =
                            candidate['already_in_room'] == true;
                        final inviteSent = candidate['invite_sent'] == true;
                        final isSending = _pendingInviteEmails.contains(email);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              UserAvatar(
                                radius: 22,
                                displayName: displayName,
                                photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    if (username.isNotEmpty || email.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(
                                          username.isNotEmpty
                                              ? username
                                              : email,
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            color: isDark
                                                ? Colors.white60
                                                : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (alreadyInRoom)
                                _InviteStateChip(
                                  label: 'Already in Room',
                                  background: isDark
                                      ? Colors.white12
                                      : const Color(0xFFF1F5F9),
                                  foreground: isDark
                                      ? Colors.white70
                                      : const Color(0xFF64748B),
                                )
                              else if (inviteSent)
                                const _InviteStateChip(
                                  label: 'Invite Sent',
                                  background: Color(0x1A2563EB),
                                  foreground: Color(0xFF2563EB),
                                )
                              else
                                TextButton(
                                  onPressed: isSending
                                      ? null
                                      : () => _sendInvite(candidate),
                                  child: isSending
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Send Invite'),
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
  }
}

class _InviteStateChip extends StatelessWidget {
  const _InviteStateChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
