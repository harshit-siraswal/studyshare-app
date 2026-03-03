import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../models/resource.dart';
import '../services/supabase_service.dart';
import '../screens/viewer/pdf_viewer_screen.dart';
import '../services/download_service.dart';
import '../services/subscription_service.dart';
import '../widgets/paywall_dialog.dart';
import '../screens/profile/user_profile_screen.dart';
import 'user_badge.dart';

class ResourceCard extends StatefulWidget {
  final Resource resource;
  final String userEmail;
  final bool showModerationControls;
  final VoidCallback? onApprove;
  final VoidCallback? onRetract;
  final VoidCallback? onReject;
  final VoidCallback? onDelete;
  final VoidCallback? onVoteChanged;

  const ResourceCard({
    super.key,
    required this.resource,
    required this.userEmail,
    this.showModerationControls = false,
    this.onApprove,
    this.onRetract,
    this.onReject,
    this.onDelete,
    this.onVoteChanged,
  });

  @override
  State<ResourceCard> createState() => _ResourceCardState();
}

class _ResourceCardState extends State<ResourceCard> {
  final SupabaseService _supabaseService = SupabaseService();
  final DownloadService _downloadService = DownloadService();
  int _upvotes = 0;
  int _downvotes = 0;
  int? _userVote;
  bool _isBookmarked = false;
  bool _isVoting = false;
  bool _isDownloaded = false;

  @override
  void initState() {
    super.initState();
    _upvotes = widget.resource.upvotes;
    _downvotes = widget.resource.downvotes;
    _checkBookmark();
    _refreshVoteState();
    _refreshDownloadState();
  }

  @override
  void didUpdateWidget(covariant ResourceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource.id != widget.resource.id ||
        oldWidget.userEmail != widget.userEmail) {
      _refreshDownloadState();
      _checkBookmark();
      _refreshVoteState();
    }
  }

  Future<void> _checkBookmark() async {
    final bookmarked = await _supabaseService.isBookmarked(
      widget.userEmail,
      widget.resource.id,
    );
    if (mounted) setState(() => _isBookmarked = bookmarked);
  }

  Future<void> _refreshVoteState() async {
    try {
      final voteStatus = await _supabaseService.getResourceVoteStatus(
        widget.resource.id,
      );
      if (!mounted) return;
      setState(() {
        _userVote = voteStatus.userVote;
        _upvotes = voteStatus.upvotes;
        _downvotes = voteStatus.downvotes;
      });
    } catch (e) {
      debugPrint('Error refreshing vote state: $e');
    }
  }

  Future<void> _refreshDownloadState() async {
    final downloaded = await _downloadService.isDownloadedForUser(
      widget.resource.id,
      widget.userEmail,
    );
    if (!mounted) return;
    setState(() => _isDownloaded = downloaded);
  }

  Future<void> _toggleBookmark() async {
    try {
      final result = await _supabaseService.toggleBookmark(
        widget.userEmail,
        widget.resource.id,
      );
      if (mounted) {
        setState(() => _isBookmarked = result);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result ? 'Bookmarked!' : 'Removed'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Bookmark toggle error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update bookmark. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _vote(int direction) async {
    if (_isVoting) return;
    final oldVote = _userVote;
    final oldUpvotes = _upvotes;
    final oldDownvotes = _downvotes;
    setState(() => _isVoting = true);
    try {
      final newVote = _userVote == direction ? null : direction;

      setState(() {
        if (oldVote == 1) _upvotes--;
        if (oldVote == -1) _downvotes--;
        if (newVote == 1) _upvotes++;
        if (newVote == -1) _downvotes++;
        _userVote = newVote;
      });

      await _supabaseService.voteResource(
        widget.userEmail,
        widget.resource.id,
        direction,
      );
      widget.onVoteChanged?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _upvotes = oldUpvotes;
          _downvotes = oldDownvotes;
          _userVote = oldVote;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to cast vote. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  Future<void> _handleDownload(BuildContext context) async {
    // 1. Check if already downloaded
    if (await _downloadService.isDownloadedForUser(
      widget.resource.id,
      widget.userEmail,
    )) {
      final path = await _downloadService.getLocalPathForUser(
        widget.resource.id,
        widget.userEmail,
      );
      if (path != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              pdfUrl: path,
              title: widget.resource.title,
              resourceId: widget.resource.id,
              collegeId: widget.resource.collegeId,
            ),
          ),
        );
      }
      return;
    }

    // 2. Check Premium
    final subService = SubscriptionService();
    final isPremium = await subService.isPremium();

    if (!isPremium) {
      showDialog(
        context: context,
        builder: (_) => PaywallDialog(
          onSuccess: () {
            if (!mounted) return;
            setState(() {}); // refresh state to likely remove lock
            _handleDownload(context); // retry download
          },
        ),
      );
      return;
    }

    // 3. Download
    if (widget.resource.fileUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file available to download')),
      );
      return;
    }
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Downloading...')));
      await _downloadService.downloadResource(
        widget.resource.fileUrl,
        widget.resource,
        ownerEmail: widget.userEmail,
      );
      await _refreshDownloadState();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Download Complete!')));
    } on DownloadCancelledException {
      return;
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  void _openResource() {
    if (widget.resource.type == 'video') {
      _openVideo();
    } else if (widget.resource.type == 'notice') {
      _showNoticeDialog();
    } else {
      _showPDFViewer();
    }
  }

  void _showNoticeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.resource.title,
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.resource.fileUrl.isNotEmpty) // If notice has image
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.resource.fileUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (ctx, err, trace) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.broken_image_outlined,
                              size: 48,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Image not found',
                              style: GoogleFonts.inter(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                widget.resource.description ?? '',
                style: GoogleFonts.inter(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPDFViewer() async {
    if (widget.resource.fileUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No file available')));
      return;
    }

    final localPath = await _downloadService.getLocalPathForUser(
      widget.resource.id,
      widget.userEmail,
    );

    bool hasLocalFile = false;
    if (!kIsWeb &&
        localPath != null &&
        await _downloadService.isDownloadedForUser(
          widget.resource.id,
          widget.userEmail,
        )) {
      hasLocalFile = true;
    }

    final url = hasLocalFile ? localPath! : widget.resource.fileUrl;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(
          pdfUrl: url,
          title: widget.resource.title,
          resourceId: widget.resource.id,
          collegeId: widget.resource.collegeId,
        ),
      ),
    );
  }

  Future<void> _openVideo() async {
    final url = widget.resource.fileUrl;
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  int get _netVotes => _upvotes - _downvotes;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final moderationMetaRow = _buildModerationMetaRow();

    return Material(
      color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _openResource,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getTypeColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getTypeIcon(), color: _getTypeColor(), size: 24),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and Badge
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          widget.resource.title,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppTheme.textOnDark
                                : AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _getTypeColor().withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.resource.type.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _getTypeColor(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Author
                    _buildAuthorWidget(),
                    const SizedBox(height: 4),
                    // Subject & Branch
                    Text(
                      '${widget.resource.subject ?? 'Unknown'} • ${widget.resource.branch ?? 'General'}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Actions row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Vote buttons
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildVoteButton(
                                  icon: Icons.thumb_up_outlined,
                                  isActive: _userVote == 1,
                                  color: AppTheme.success,
                                  onTap: () => _vote(1),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Text(
                                    _netVotes > 0
                                        ? '+$_netVotes'
                                        : '$_netVotes',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _netVotes > 0
                                          ? AppTheme.success
                                          : _netVotes < 0
                                          ? AppTheme.error
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                                _buildVoteButton(
                                  icon: Icons.thumb_down_outlined,
                                  isActive: _userVote == -1,
                                  color: AppTheme.error,
                                  onTap: () => _vote(-1),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Bookmark button
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _toggleBookmark,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Icon(
                                  _isBookmarked
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  size: 20,
                                  color: _isBookmarked
                                      ? AppTheme.warning
                                      : AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Download Button
                          if (widget.resource.type == 'notes' ||
                              widget.resource.type == 'pyq') ...[
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => _handleDownload(context),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: _isDownloaded
                                      ? Icon(
                                          Icons.offline_pin,
                                          size: 20,
                                          color: AppTheme.success,
                                        )
                                      : Icon(
                                          Icons.download_rounded,
                                          size: 20,
                                          color: AppTheme.textMuted,
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],

                          // Date
                          Text(
                            widget.resource.formattedDate,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.showModerationControls) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.verified_user_rounded,
                                  size: 14,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Moderation',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? AppTheme.textOnDark
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            if (moderationMetaRow != null) ...[
                              const SizedBox(height: 8),
                              moderationMetaRow,
                            ],
                            const SizedBox(height: 10),
                            ..._buildModerationActionButtons(),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildModerationActionButtons() {
    final buttons = <Widget>[];

    if (widget.onReject != null) {
      buttons.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: widget.onReject,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: Text(
              'Reject',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              side: BorderSide(color: AppTheme.error.withValues(alpha: 0.45)),
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      );
    }

    if (widget.onRetract != null) {
      buttons.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: widget.onRetract,
            icon: const Icon(Icons.undo_rounded, size: 16),
            label: Text(
              'Retract',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.warning,
              side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.4)),
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      );
    }

    if (widget.onApprove != null) {
      buttons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: widget.onApprove,
            icon: const Icon(Icons.check_rounded, size: 16),
            label: Text(
              'Approve',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      );
    }

    if (buttons.isEmpty) return const [];

    return [
      Row(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            buttons[i],
          ],
        ],
      ),
    ];
  }

  Widget? _buildModerationMetaRow() {
    final teacherProfile = _buildTeacherProfileButton();
    final deleteButton = _buildDeleteIconButton();
    if (teacherProfile == null && deleteButton == null) return null;

    return Row(
      children: [
        if (teacherProfile != null) ...[
          Expanded(child: teacherProfile),
          if (deleteButton != null) const SizedBox(width: 8),
        ],
        ?deleteButton,
      ],
    );
  }

  Widget? _buildTeacherProfileButton() {
    if (!widget.resource.isTeacherUpload) return null;
    final email = widget.resource.uploadedByEmail.trim();
    if (email.isEmpty) return null;
    final name = widget.resource.uploadedByName?.trim().isNotEmpty == true
        ? widget.resource.uploadedByName!.trim()
        : email.split('@').first;

    return OutlinedButton.icon(
      onPressed: () => _openUserProfile(email, name),
      icon: const Icon(Icons.school_rounded, size: 14),
      label: Text(
        'Teacher profile',
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primary,
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.35)),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget? _buildDeleteIconButton() {
    if (widget.onDelete == null) return null;
    return OutlinedButton.icon(
      onPressed: widget.onDelete,
      icon: const Icon(Icons.delete_outline_rounded, size: 14),
      label: Text(
        'Delete',
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.error,
        side: BorderSide(color: AppTheme.error.withValues(alpha: 0.4)),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildVoteButton({
    required IconData icon,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? color : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  IconData _getTypeIcon() {
    switch (widget.resource.type.toLowerCase()) {
      case 'video':
        return Icons.play_circle_fill;
      case 'pyq':
        return Icons.help_outline;
      case 'notice':
        return Icons.campaign_rounded;
      case 'notes':
      default:
        return Icons.description;
    }
  }

  Color _getTypeColor() {
    switch (widget.resource.type.toLowerCase()) {
      case 'video':
        return AppTheme.error; // Red
      case 'pyq':
        return AppTheme.warning; // Amber
      case 'notice':
        return AppTheme.noticeColor; // Purple for notices
      case 'notes':
      default:
        return AppTheme.primary; // Blue (now #2563EB)
    }
  }

  Widget _buildAuthorWidget() {
    final name = widget.resource.uploadedByName;
    final email = widget.resource.uploadedByEmail;

    if (name == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: 'View profile for $name',
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            _openUserProfile(email, name);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Semantics(
                label: 'Open profile for $name',
                button: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'by $name',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.textMuted,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      UserBadge(email: email, size: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openUserProfile(String email, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userEmail: email, userName: name),
      ),
    );
  }
} // End of _ResourceCardState
