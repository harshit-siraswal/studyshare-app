import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../config/theme.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../models/department_account.dart';
import '../screens/notices/notice_detail_screen.dart';
import 'notice_share_preview.dart';
import '../utils/link_navigation_utils.dart';

enum _NoticeManageAction { hide, show, delete }

class NoticeCard extends StatefulWidget {
  final Map<String, dynamic> notice;
  final DepartmentAccount account;
  final String? collegeId;
  final bool isDark;
  final bool canManage;
  final VoidCallback? onNoticeUpdated;

  const NoticeCard({
    super.key,
    required this.notice,
    required this.account,
    this.collegeId,
    required this.isDark,
    this.canManage = false,
    this.onNoticeUpdated,
  });

  @override
  State<NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<NoticeCard> {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();

  bool _isSaved = false;
  bool _isLoading = false;
  bool _manageLoading = false;

  @override
  void initState() {
    super.initState();
    _checkSavedStatus();
  }

  Future<void> _checkSavedStatus() async {
    final email = _authService.userEmail;
    if (email == null) return;

    final saved = await _supabaseService.isNoticeSaved(
      widget.notice['id'],
      email,
    );
    if (mounted) {
      setState(() => _isSaved = saved);
    }
  }

  Future<void> _toggleSaved() async {
    final email = _authService.userEmail;
    if (email == null) return;

    setState(() => _isLoading = true);

    try {
      if (_isSaved) {
        await _supabaseService.unsaveNotice(widget.notice['id'], email);
        if (!mounted) return;
        setState(() => _isSaved = false);
      } else {
        await _supabaseService.saveNotice(widget.notice['id'], email);
        if (!mounted) return;
        setState(() => _isSaved = true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notice saved to bookmarks')),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error toggling saved status: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setNoticeVisibility(bool isActive) async {
    final noticeId = widget.notice['id']?.toString().trim() ?? '';
    if (noticeId.isEmpty) return;

    setState(() => _manageLoading = true);
    try {
      await _supabaseService.setNoticeVisibility(
        noticeId: noticeId,
        isActive: isActive,
      );
      if (!mounted) return;
      setState(() => widget.notice['is_active'] = isActive);
      widget.onNoticeUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isActive ? 'Notice is now visible' : 'Notice hidden',
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Error updating notice visibility: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update notice visibility right now.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _manageLoading = false);
    }
  }

  Future<void> _deleteNotice() async {
    final noticeId = widget.notice['id']?.toString().trim() ?? '';
    if (noticeId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete notice?'),
        content: const Text('This will permanently remove the notice.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _manageLoading = true);
    try {
      await _supabaseService.deleteNotice(noticeId: noticeId);
      if (!mounted) return;
      widget.onNoticeUpdated?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Notice deleted')));
    } catch (e, stackTrace) {
      debugPrint('Error deleting notice: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to delete notice right now.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _manageLoading = false);
    }
  }

  Future<void> _handleManageAction(_NoticeManageAction action) async {
    switch (action) {
      case _NoticeManageAction.hide:
        await _setNoticeVisibility(false);
        break;
      case _NoticeManageAction.show:
        await _setNoticeVisibility(true);
        break;
      case _NoticeManageAction.delete:
        await _deleteNotice();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final secondaryColor = widget.isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final cardColor = widget.isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = widget.isDark
        ? AppTheme.darkBorder
        : AppTheme.lightBorder;

    final title = widget.notice['title'] ?? 'Untitled';
    final content = widget.notice['content'] ?? '';
    final createdAt = widget.notice['created_at'];
    final timeAgo = _formatTimeAgo(createdAt);
    final priority = widget.notice['priority']?.toString();
    final isActive = widget.notice['is_active'] != false;
    final rawCount =
        widget.notice['comments'] ?? widget.notice['comment_count'];
    final commentCount = rawCount is int
        ? rawCount
        : int.tryParse(rawCount?.toString() ?? '');
    final boardTop = widget.isDark
        ? const Color(0xFF3A2F22)
        : const Color(0xFFC79863);
    final boardBottom = widget.isDark
        ? const Color(0xFF2A2118)
        : const Color(0xFFAA7C4C);
    final paperTop = widget.isDark
        ? cardColor.withValues(alpha: 0.95)
        : const Color(0xFFFFF7E6);
    final paperBottom = widget.isDark
        ? cardColor.withValues(alpha: 0.82)
        : const Color(0xFFF6E5BC);
    final paperBorder = widget.isDark
        ? borderColor.withValues(alpha: 0.85)
        : const Color(0xFFD8BE88);
    final manageMenu = widget.canManage
        ? Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _manageLoading
                ? SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                : PopupMenuButton<_NoticeManageAction>(
                    tooltip: 'Manage notice',
                    padding: EdgeInsets.zero,
                    color: widget.isDark
                        ? const Color(0xFF111827)
                        : Colors.white,
                    elevation: 10,
                    offset: const Offset(0, 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: _handleManageAction,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: isActive
                            ? _NoticeManageAction.hide
                            : _NoticeManageAction.show,
                        child: Text(isActive ? 'Hide' : 'Show'),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: _NoticeManageAction.delete,
                        child: Text(
                          'Delete',
                          style: TextStyle(color: AppTheme.error),
                        ),
                      ),
                    ],
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? Colors.white10
                            : Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: secondaryColor,
                      ),
                    ),
                  ),
          )
        : null;

    void openDetail() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NoticeDetailScreen(
            notice: widget.notice,
            account: widget.account,
            collegeId:
                widget.collegeId ??
                widget.notice['college_id']?.toString() ??
                '',
          ),
        ),
      );
    }

    return Hero(
      tag:
          'notice_card_${widget.notice['id'] ?? identityHashCode(widget.notice)}',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[boardTop, boardBottom],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFF8F6438).withValues(alpha: 0.35),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isDark ? 0.25 : 0.14),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(top: 8, left: 22, child: _buildTapePiece(rotation: -0.18)),
            Positioned(top: 8, right: 22, child: _buildTapePiece(rotation: 0.18)),
            Positioned(
              top: -8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFFE34F47), Color(0xFFC8302A)],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.push_pin_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: openDetail,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[paperTop, paperBottom],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: paperBorder),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: widget.isDark ? 0.18 : 0.08,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: widget.account.color,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Center(
                                  child: Text(
                                    widget.account.avatarLetter,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  widget.account.name,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: textColor,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.verified_rounded,
                                                size: 12,
                                                color: AppTheme.primary,
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: widget.isDark
                                                      ? Colors.white10
                                                      : Colors.black.withValues(
                                                          alpha: 0.05,
                                                        ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        10,
                                                      ),
                                                ),
                                                child: Text(
                                                  widget.account.handle,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    color: secondaryColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        ?manageMenu,
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: <Widget>[
                                        Text(
                                          timeAgo,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: secondaryColor,
                                          ),
                                        ),
                                        if (!isActive) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: widget.isDark
                                                  ? Colors.white12
                                                  : Colors.black.withValues(
                                                      alpha: 0.08,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              'HIDDEN',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (priority == 'urgent') ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.error.withValues(
                                                alpha: 0.16,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              'URGENT',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.error,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                              height: 1.2,
                            ),
                          ),
                          if (content.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Linkify(
                              onOpen: (link) => _openNoticeLink(link.url),
                              text: content,
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                color: secondaryColor,
                                height: 1.35,
                              ),
                              linkStyle: GoogleFonts.inter(
                                fontSize: 13.5,
                                color: AppTheme.primary,
                                decoration: TextDecoration.underline,
                                height: 1.35,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: <Widget>[
                              _buildActionButton(
                                icon: Icons.mode_comment_outlined,
                                count: commentCount != null
                                    ? '$commentCount'
                                    : 'Comment',
                                color: secondaryColor,
                                onTap: openDetail,
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: _isLoading ? null : _toggleSaved,
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    _isSaved
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_border_rounded,
                                    size: 20,
                                    color: _isSaved
                                        ? AppTheme.primary
                                        : secondaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(
                                icon: Icons.share_outlined,
                                count: 'Share',
                                color: secondaryColor,
                                onTap: _shareAsImage,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTapePiece({required double rotation}) {
    final tapeColor = widget.isDark
        ? const Color(0x55E7D7AF)
        : const Color(0x99F4E7C9);
    return Transform.rotate(
      angle: rotation,
      child: Container(
        width: 44,
        height: 14,
        decoration: BoxDecoration(
          color: tapeColor,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String? count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: widget.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            if (count != null) ...[
              const SizedBox(width: 4),
              Text(count, style: GoogleFonts.inter(fontSize: 11, color: color)),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }

  /// Opens the notice URL in a browser or in-app viewer.
  Future<void> _openNoticeLink(String rawUrl) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final launched = await openStudyShareLink(
        context,
        rawUrl: rawUrl,
        title: widget.notice['title']?.toString() ?? 'Notice link',
      );
      if (!mounted) return;
      if (!launched) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not open: $rawUrl')),
        );
      }
    } catch (e) {
      debugPrint('Failed to launch URL: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to open link')),
      );
    }
  }

  /// Share the notice as a PNG image instead of plain text.
  Future<void> _shareAsImage() async {
    final controller = ScreenshotController();

    try {
      final bytes = await controller.captureFromWidget(
        NoticeSharePreview(
          notice: widget.notice,
          account: widget.account,
          brandLabel: 'StudyShare',
          timestampLabel: _formatTimeAgo(widget.notice['created_at']),
        ),
        delay: const Duration(milliseconds: 50),
        pixelRatio: 2.0,
      );

      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = await File('${tempDir.path}/notice_share_$ts.png').create();
      try {
        await file.writeAsBytes(bytes);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'Check out this notice on StudyShare!',
          ),
        );
      } finally {
        // Delay deletion to avoid Android race condition
        unawaited(
          Future.delayed(const Duration(seconds: 8), () async {
            try {
              await file.delete();
            } catch (_) {}
          }),
        );
      }
    } catch (e, st) {
      debugPrint('Notice share image generation failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to generate image. Please try again.'),
        ),
      );
    }
  }
}
