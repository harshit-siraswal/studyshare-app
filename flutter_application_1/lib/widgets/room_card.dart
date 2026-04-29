import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../screens/chatroom/chatroom_screen.dart';
import '../services/backend_api_service.dart';

class RoomCard extends StatefulWidget {
  static const String _defaultRoomName = 'Unnamed Room';

  const RoomCard({
    super.key,
    required this.room,
    required this.userEmail,
    required this.collegeDomain,
    this.onReturn,
  });

  final Map<String, dynamic> room;
  final String userEmail;
  final String collegeDomain;
  final VoidCallback? onReturn;

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard> {
  final BackendApiService _api = BackendApiService();
  late Map<String, dynamic> _room;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _room = Map<String, dynamic>.from(widget.room);
  }

  bool get _isJoined => _room['isMember'] == true || _room['is_member'] == true;

  bool get _isPrivate =>
      _room['is_private'] == true || _room['isPrivate'] == true;

  bool get _hasJoinAccess {
    final email = widget.userEmail.trim().toLowerCase();
    final domain = widget.collegeDomain.trim().toLowerCase();
    if (email.isEmpty || domain.isEmpty) return false;
    final normalizedDomain = domain.startsWith('@') ? domain : '@$domain';
    return email.endsWith(normalizedDomain);
  }

  String _roomValue(String key, {String fallback = ''}) {
    final value = _room[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  List<String> _extractTags(dynamic rawTags) {
    if (rawTags is List) {
      return rawTags
          .map((entry) => entry?.toString().trim() ?? '')
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    final normalized = rawTags?.toString().trim() ?? '';
    if (normalized.isEmpty) return const <String>[];
    if (normalized.contains(',')) {
      return normalized
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    return <String>[normalized];
  }

  Future<void> _openRoom() async {
    final roomName = _roomValue('name', fallback: RoomCard._defaultRoomName);
    final roomId = _room['id']?.toString() ?? '';
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error: Room ID missing')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatRoomScreen(
          roomId: roomId,
          roomName: roomName,
          description: _roomValue('description'),
          userEmail: widget.userEmail,
          collegeDomain: widget.collegeDomain,
          initialIsAdmin: _room['isAdmin'] == true || _room['is_admin'] == true,
          initialIsMember: _isJoined,
          initialRoomInfo: Map<String, dynamic>.from(_room),
        ),
      ),
    );
    widget.onReturn?.call();
  }

  Future<void> _joinRoom() async {
    final roomId = _room['id']?.toString() ?? '';
    if (roomId.isEmpty || _isJoining || _isJoined) {
      await _openRoom();
      return;
    }

    final previousRoom = Map<String, dynamic>.from(_room);
    final previousCount = _room['member_count'];
    setState(() {
      _isJoining = true;
      _room = {
        ..._room,
        'is_member': true,
        'isMember': true,
        if (previousCount is int) 'member_count': previousCount + 1,
      };
    });

    try {
      await _api.joinChatRoomById(roomId);
      if (!mounted) return;
      setState(() => _isJoining = false);
      await _openRoom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isJoining = false;
        _room = previousRoom;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to join room: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final tags = _extractTags(_room['tags']);
    final roomName = _roomValue('name', fallback: RoomCard._defaultRoomName);
    final description = _roomValue('description', fallback: 'No description');
    final canJoinDirectly = !_isJoined && !_isPrivate && _hasJoinAccess;

    return GestureDetector(
      onTap: _openRoom,
      child: Container(
        constraints: const BoxConstraints(minHeight: 176),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.tag, color: AppTheme.primary, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      roomName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                description,
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  fontSize: 12,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 4,
                children: tags.isNotEmpty
                    ? tags.take(2).map((t) => _buildTagChip(t, isDark)).toList()
                    : [_buildTagChip('#notag', isDark, isPlaceholder: true)],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade50,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 14,
                          color: isDark ? Colors.white54 : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_room['member_count'] ?? 0}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white54 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: canJoinDirectly ? _joinRoom : _openRoom,
                      borderRadius: BorderRadius.circular(20),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: canJoinDirectly
                              ? AppTheme.primary
                              : AppTheme.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: _isJoining
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                canJoinDirectly ? 'Join' : 'Open',
                                style: TextStyle(
                                  color: canJoinDirectly
                                      ? Colors.white
                                      : AppTheme.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagChip(
    String label,
    bool isDark, {
    bool isPlaceholder = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPlaceholder
            ? (isDark ? Colors.white10 : Colors.grey.shade200)
            : AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: isPlaceholder
              ? (isDark ? Colors.white38 : Colors.grey)
              : AppTheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
