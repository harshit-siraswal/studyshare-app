import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../utils/youtube_link_utils.dart';

class NoticeCard extends StatefulWidget {
  final Map<String, dynamic> notice;
  final DepartmentAccount account;
  final String? collegeId;
  final bool isDark;

  const NoticeCard({
    super.key,
    required this.notice,
    required this.account,
    this.collegeId,
    required this.isDark,
  });

  @override
  State<NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<NoticeCard> {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();

  bool _isSaved = false;
  bool _isLoading = false;

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
    final rawCount =
        widget.notice['comments'] ?? widget.notice['comment_count'];
    final commentCount = rawCount is int
        ? rawCount
        : int.tryParse(rawCount?.toString() ?? '');

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

    /*
    Notice-board layout kept here intentionally for future widget use.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[boardTop, boardBottom],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(top: 8, left: 22, child: _buildTapePiece(rotation: -0.18)),
          Positioned(top: 8, right: 22, child: _buildTapePiece(rotation: 0.18)),
          // Existing board/paper composition intentionally commented out.
        ],
      ),
    );
    */

    return Hero(
      tag: 'notice_card_${widget.notice['id'] ?? identityHashCode(widget.notice)}',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: <BoxShadow>[
            if (!widget.isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: openDetail,
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: widget.account.color,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: widget.account.color,
                              borderRadius: BorderRadius.circular(19),
                            ),
                            child: Center(
                              child: Text(
                                widget.account.avatarLetter,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(
                                        widget.account.name,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: textColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: widget.isDark
                                            ? Colors.white10
                                            : Colors.black.withValues(
                                                alpha: 0.06,
                                              ),
                                        borderRadius: BorderRadius.circular(10),
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
                                    if (priority == 'urgent') ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.error.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'URGENT',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
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
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      if (content.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Linkify(
                          onOpen: (link) => _openNoticeLink(link.url),
                          text: content,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: secondaryColor,
                            height: 1.4,
                          ),
                          linkStyle: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.primary,
                            decoration: TextDecoration.underline,
                            height: 1.4,
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
                            count: commentCount != null ? '$commentCount' : 'Comment',
                            color: secondaryColor,
                            onTap: openDetail,
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: _isLoading ? null : _toggleSaved,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
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

  /// Share the notice as a PNG image instead of plain text.
  Future<void> _openNoticeLink(String rawUrl) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = buildExternalUri(rawUrl);
      if (uri == null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not open: $rawUrl')),
        );
        return;
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
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
