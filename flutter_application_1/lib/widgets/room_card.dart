import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../screens/chatroom/chatroom_screen.dart';

class RoomCard extends StatelessWidget {
  static const String _defaultRoomName = 'Unnamed Room';

  final Map<String, dynamic> room;
  final String userEmail;
  final String collegeDomain;
  final VoidCallback? onReturn;

  const RoomCard({
    super.key,
    required this.room,
    required this.userEmail,
    required this.collegeDomain,
    this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    final tagsList = room['tags'] as List?;
    final tags = tagsList?.map((e) => e.toString()).toList() ?? [];

    void openRoom() {
      final roomId = room['id']?.toString() ?? '';
      if (roomId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Room ID missing')));
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatRoomScreen(
            roomId: roomId,
            roomName: room['name'] ?? _defaultRoomName,
            description: room['description'] ?? '',
            userEmail: userEmail,
            collegeDomain: collegeDomain,
          ),
        ),
      ).then((_) {
        onReturn?.call();
      });
    }

    return GestureDetector(
      onTap: openRoom,
      child: Container(
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
          children: [
            // Header with Icon
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
                      room['name'] ?? _defaultRoomName,
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

            // Description
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  room['description'] ?? 'No description',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                    fontSize: 12,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Tags
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 4,
                children: tags.isNotEmpty
                    ? tags.take(2).map((t) => _buildTagChip(t, isDark)).toList()
                    : [_buildTagChip('#notag', isDark, isPlaceholder: true)],
              ),
            ),

            // Footer
            Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade50,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.people_outline,
                            size: 14, color: isDark ? Colors.white54 : Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '${room['member_count'] ?? 0}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white54 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: openRoom,
                      borderRadius: BorderRadius.circular(20),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('View',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),    );
  }

  Widget _buildTagChip(String label, bool isDark, {bool isPlaceholder = false}) {
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
