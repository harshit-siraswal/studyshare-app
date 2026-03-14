import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/profile_photo_utils.dart';
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
        _supabaseService.getRoomInfo(widget.roomId),
        _supabaseService.getRoomMembers(widget.roomId),
        _supabaseService.getRoomPostCounts(widget.roomId),
      ]);

      if (!mounted) return;

      setState(() {
        _roomInfo = results[0] as Map<String, dynamic>?;
        _members = (results[1] as List<Map<String, dynamic>>?) ?? [];
        _postCounts = results[2] as ({int total, int today});
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Failed to load room details';
      });
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
    return memberEmail.isNotEmpty &&
        memberEmail == email.trim().toLowerCase();
  }

  bool _isAdminMember(Map<String, dynamic> member, String email) {
    if (!_isSameUser(member, email)) return false;
    final role = (member['role'] ?? 'member').toString().toLowerCase();
    return role == 'admin';
  }

  String _createdAtLabel() {
    final raw = _roomInfo?['created_at'] ?? _roomInfo?['createdAt'];
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return 'Unknown';
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')} '
        '${_monthLabel(local.month)} ${local.year}';
  }

  String _monthLabel(int month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (month < 1 || month > 12) return '';
    return months[month - 1];
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
            child: const Text(
              'Leave',
              style: TextStyle(color: Colors.red),
            ),
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

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
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
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> member, bool isDark) {
    final email = (member['user_email'] ?? '').toString().trim();
    final role = (member['role'] ?? 'member').toString().toLowerCase();
    final photoUrl = _resolvePhotoUrl(member, const [
      'profile_photo_url',
      'photo_url',
      'avatar_url',
    ]);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Row(
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
                Text(
                  _memberDisplayName(member),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email.isNotEmpty ? email : 'Unknown email',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: role == 'admin'
                  ? AppTheme.primary.withValues(alpha: 0.14)
                  : Colors.grey.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              role == 'admin' ? 'Admin' : 'Member',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: role == 'admin' ? AppTheme.primary : AppTheme.textMuted,
              ),
            ),
          ),
          if (_isSameUser(member, widget.userEmail))
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

    final createdBy =
        (_roomInfo?['created_by'] ?? _roomInfo?['createdBy'] ?? 'Unknown')
            .toString();
    final memberCount =
        _members.isNotEmpty ? _members.length : (_roomInfo?['member_count'] ?? 0);
    final activeLabel = widget.activeMemberCount != null
        ? widget.activeMemberCount == 0
            ? 'No active members'
            : '${widget.activeMemberCount} active now'
        : null;

    final admins = _members
        .where((m) => (m['role'] ?? '').toString().toLowerCase() == 'admin')
        .toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1015) : const Color(0xFFF5F5F7),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_isLoading)
              const LinearProgressIndicator(minHeight: 2),
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
                padding: const EdgeInsets.only(top: 6),
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
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  activeLabel,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            _metricTile(
              icon: Icons.people_outline,
              label: 'Members',
              value: memberCount.toString(),
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _metricTile(
                    icon: Icons.forum_outlined,
                    label: 'Total Posts',
                    value: _postCounts.total.toString(),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricTile(
                    icon: Icons.today_outlined,
                    label: 'Posts Today',
                    value: _postCounts.today.toString(),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle('Room Details', isDark),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111827) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  _detailRow('Created by', createdBy, isDark),
                  const SizedBox(height: 8),
                  _detailRow('Created on', _createdAtLabel(), isDark),
                  if (admins.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _detailRow(
                      'Admins',
                      admins.map(_memberDisplayName).join(', '),
                      isDark,
                    ),
                  ],
                ],
              ),
            ),
            if (_isAdmin &&
                (_roomInfo?['is_private'] == true ||
                    _roomInfo?['is_private'] == 'true')) ...[
              const SizedBox(height: 18),
              _sectionTitle('Room Code', isDark),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
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
                      child: Text(
                        (_roomInfo?['code'] ?? 'N/A').toString(),
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _roomInfo?['code']?.toString() ?? ''),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied!')),
                        );
                      },
                      icon: Icon(Icons.copy_rounded, color: AppTheme.primary),
                    ),
                  ],
                ),
              ),
            ],
            if (_isAdmin && widget.onManageMembers != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onManageMembers?.call();
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
            const SizedBox(height: 18),
            _sectionTitle('Members', isDark),
            const SizedBox(height: 8),
            if (_members.isEmpty)
              Text(
                'No members found',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _members.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    _memberTile(_members[index], isDark),
              ),
            if (_isMember) ...[
              const SizedBox(height: 24),
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

  Widget _detailRow(String label, String value, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
