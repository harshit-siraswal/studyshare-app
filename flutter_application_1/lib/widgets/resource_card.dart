import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../data/academic_subjects_data.dart';
import '../models/resource.dart';
import '../screens/profile/user_profile_screen.dart';
import '../screens/viewer/pdf_viewer_screen.dart';
import '../services/download_service.dart';
import '../services/subscription_service.dart';
import '../services/supabase_service.dart';
import '../utils/link_navigation_utils.dart';
import '../utils/youtube_link_utils.dart';
import '../widgets/paywall_dialog.dart';
import 'user_badge.dart';

class ResourceCard extends StatefulWidget {
  final Resource resource;
  final String userEmail;
  final bool showModerationControls;
  final bool showStatusBadge;
  final VoidCallback? onApprove;
  final VoidCallback? onRetract;
  final VoidCallback? onReject;
  final VoidCallback? onDelete;
  final VoidCallback? onVoteChanged;

  /// When true, callers should either pre-populate cache or call
  /// [ResourceCardState.hydrateRemoteState] to avoid stale vote/bookmark UI.
  final bool deferRemoteStateHydration;

  const ResourceCard({
    super.key,
    required this.resource,
    required this.userEmail,
    this.showModerationControls = false,
    this.showStatusBadge = false,
    this.onApprove,
    this.onRetract,
    this.onReject,
    this.onDelete,
    this.onVoteChanged,
    this.deferRemoteStateHydration = false,
  });

  @override
  State<ResourceCard> createState() => ResourceCardState();
}

class ResourceCardState extends State<ResourceCard> {
  final SupabaseService _supabaseService = SupabaseService();
  final DownloadService _downloadService = DownloadService();

  int _upvotes = 0;
  int _downvotes = 0;
  int? _userVote;
  bool _isBookmarked = false;
  bool _isVoting = false;
  bool _isDownloaded = false;
  OverlayEntry? _peekOverlayEntry;

  @override
  void initState() {
    super.initState();
    _hydrateFromCacheAndMaybeRefresh();
    _refreshDownloadState();
  }

  @override
  void dispose() {
    _hidePeekPreview();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ResourceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource.id != widget.resource.id ||
        oldWidget.userEmail != widget.userEmail) {
      _hydrateFromCacheAndMaybeRefresh();
      _refreshDownloadState();
    }
  }

  void _hydrateFromCacheAndMaybeRefresh() {
    _userVote = null;
    _upvotes = widget.resource.upvotes;
    _downvotes = widget.resource.downvotes;
    _isBookmarked = false;

    final cachedVote = _supabaseService.getCachedVoteState(
      widget.resource.id,
      userEmail: widget.userEmail,
    );
    if (cachedVote != null) {
      _userVote = cachedVote.userVote;
      _upvotes = cachedVote.upvotes;
      _downvotes = cachedVote.downvotes;
    }

    final cachedBookmark = _supabaseService.getCachedBookmarkState(
      widget.userEmail,
      widget.resource.id,
    );
    if (cachedBookmark != null) {
      _isBookmarked = cachedBookmark;
    }

    if (!widget.deferRemoteStateHydration) {
      hydrateRemoteState();
    }
  }

  Future<void> hydrateRemoteState() async {
    await Future.wait<void>([_checkBookmark(), _refreshVoteState()]);
  }

  Future<void> _checkBookmark() async {
    final bookmarked = await _supabaseService.isBookmarked(
      widget.userEmail,
      widget.resource.id,
    );
    if (mounted) {
      setState(() => _isBookmarked = bookmarked);
    }
  }

  Future<void> _refreshVoteState() async {
    try {
      final voteStatus = await _supabaseService.getResourceVoteStatus(
        widget.resource.id,
        userEmail: widget.userEmail,
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
    if (mounted) {
      setState(() => _isDownloaded = downloaded);
    }
  }

  Future<void> _toggleBookmark() async {
    try {
      final result = await _supabaseService.toggleBookmark(
        widget.userEmail,
        widget.resource.id,
      );
      if (!mounted) return;

      setState(() => _isBookmarked = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result ? 'Bookmarked!' : 'Removed'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('Bookmark toggle error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update bookmark. Please try again.'),
        ),
      );
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
      if (mounted) {
        setState(() => _isVoting = false);
      }
    }
  }

  Future<void> _handleDownload(BuildContext context) async {
    if (await _downloadService.isDownloadedForUser(
      widget.resource.id,
      widget.userEmail,
    )) {
      final path = await _downloadService.getLocalPathForUser(
        widget.resource.id,
        widget.userEmail,
      );
      if (path != null && context.mounted) {
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

    final subService = SubscriptionService();
    final isPremium = await subService.isPremium();
    if (!context.mounted) return;
    if (!isPremium) {
      showDialog(
        context: context,
        builder: (_) => PaywallDialog(
          onSuccess: () {
            if (!mounted) return;
            setState(() {});
            _handleDownload(context);
          },
        ),
      );
      return;
    }

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
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Download Complete!')));
    } on DownloadCancelledException {
      return;
    } catch (e) {
      if (!context.mounted) return;
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
    final fileUrl = widget.resource.fileUrl.trim();
    final attachmentPath =
        Uri.tryParse(fileUrl)?.path.toLowerCase() ?? fileUrl.toLowerCase();
    final hasPdfAttachment = attachmentPath.endsWith('.pdf');

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
              if (fileUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: hasPdfAttachment
                      ? Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                this.context,
                                MaterialPageRoute(
                                  builder: (_) => PdfViewerScreen(
                                    pdfUrl: fileUrl,
                                    title: widget.resource.title,
                                    resourceId: widget.resource.id,
                                    collegeId: widget.resource.collegeId,
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.picture_as_pdf_rounded,
                                    color: AppTheme.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Open attached PDF in StudyShare',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            ),
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            fileUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
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
    if (!mounted) return;
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
    final rawUrl = widget.resource.fileUrl;
    try {
      final opened = await openStudyShareLink(
        context,
        rawUrl: rawUrl,
        title: widget.resource.title,
        resourceId: widget.resource.id,
        collegeId: widget.resource.collegeId,
        subject: widget.resource.subject,
        semester: widget.resource.semester,
        branch: widget.resource.branch,
      );
      if (opened || !mounted) return;
    } catch (e) {
      debugPrint('openStudyShareLink error: $e');
    }

    final uri = _buildExternalVideoUri(widget.resource.fileUrl);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid video URL')));
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !mounted) return;

    final fallbackLaunched = await launchUrl(uri);
    if (fallbackLaunched || !mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open video link')));
  }

  Uri? _buildExternalVideoUri(String rawUrl) {
    return buildExternalUri(rawUrl);
  }

  bool _looksLikeImageUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.webp') ||
        path.endsWith('.gif');
  }

  String? get _peekPreviewImageUrl {
    final thumbnail = widget.resource.thumbnailUrl?.trim() ?? '';
    if (thumbnail.isNotEmpty) return thumbnail;

    final fileUrl = widget.resource.fileUrl.trim();
    if (_looksLikeImageUrl(fileUrl)) return fileUrl;
    return null;
  }

  Widget _buildPeekPreviewVisual(bool isDark) {
    final previewUrl = _peekPreviewImageUrl;
    if (previewUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: ColoredBox(
            color: isDark ? Colors.black : Colors.white,
            child: Image.network(
              previewUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stackTrace) =>
                  _buildPeekPreviewFallback(isDark),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ),
      );
    }

    return _buildPeekPreviewFallback(isDark);
  }

  Widget _buildPeekPreviewFallback(bool isDark) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _getTypeColor().withValues(alpha: 0.2),
            (isDark ? AppTheme.darkCard : Colors.white),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _getTypeColor().withValues(alpha: 0.16),
          ),
          child: Icon(_getTypeIcon(), color: _getTypeColor(), size: 34),
        ),
      ),
    );
  }

  Widget _buildPeekPreviewCard(BuildContext overlayContext) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final description = widget.resource.description?.trim() ?? '';
    final maxWidth = MediaQuery.of(overlayContext).size.width > 460
        ? 420.0
        : MediaQuery.of(overlayContext).size.width - 28;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.94, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF12151D).withValues(alpha: 0.96)
                      : Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPeekPreviewVisual(isDark),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getTypeColor().withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.resource.type.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _getTypeColor(),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Release to close',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.resource.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.textOnDark
                            : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _resourceMetaText(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        description,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.45,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
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

  void _showPeekPreview() {
    if (_peekOverlayEntry != null || !mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    HapticFeedback.selectionClick();
    _peekOverlayEntry = OverlayEntry(
      builder: (overlayContext) => IgnorePointer(
        ignoring: true,
        child: Material(
          color: Colors.black.withValues(alpha: 0.32),
          child: _buildPeekPreviewCard(overlayContext),
        ),
      ),
    );
    overlay.insert(_peekOverlayEntry!);
  }

  void _hidePeekPreview() {
    _peekOverlayEntry?.remove();
    _peekOverlayEntry = null;
  }

  int get _netVotes => _upvotes - _downvotes;

  String _resourceMetaText() {
    final subject = _normalizedMetaValue(widget.resource.subject) ?? 'Unknown';
    final branch =
        _normalizedMetaValue(getBranchShortLabel(widget.resource.branch)) ??
        'General';
    return '$subject | $branch';
  }

  String? _normalizedMetaValue(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActionControls =
        widget.showModerationControls ||
        widget.showStatusBadge ||
        widget.onDelete != null;
    final isCompactCard = !hasActionControls;
    final moderationMetaRow = _buildModerationMetaRow();
    final moderationButtons = _buildModerationActionButtons();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _showPeekPreview(),
      onLongPressEnd: (_) => _hidePeekPreview(),
      child: Material(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _openResource,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.all(isCompactCard ? 8 : 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: isCompactCard ? 36 : 48,
                  height: isCompactCard ? 36 : 48,
                  decoration: BoxDecoration(
                    color: _getTypeColor().withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(isCompactCard ? 8 : 10),
                  ),
                  child: Icon(
                    _getTypeIcon(),
                    color: _getTypeColor(),
                    size: isCompactCard ? 18 : 24,
                  ),
                ),
                SizedBox(width: isCompactCard ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: isCompactCard ? 6 : 8,
                        runSpacing: isCompactCard ? 3 : 4,
                        children: [
                          Text(
                            widget.resource.title,
                            style: GoogleFonts.inter(
                              fontSize: isCompactCard ? 13 : 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTheme.textOnDark
                                  : AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompactCard ? 5 : 6,
                              vertical: isCompactCard ? 1.5 : 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getTypeColor().withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.resource.type.toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: isCompactCard ? 9 : 10,
                                fontWeight: FontWeight.w600,
                                color: _getTypeColor(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isCompactCard ? 2 : 4),
                      _buildAuthorWidget(compact: isCompactCard),
                      SizedBox(height: isCompactCard ? 2 : 4),
                      Text(
                        _resourceMetaText(),
                        style: GoogleFonts.inter(
                          fontSize: isCompactCard ? 10 : 11,
                          color: AppTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: isCompactCard ? 6 : 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompactCard ? 3 : 4,
                                vertical: isCompactCard ? 1 : 2,
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
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompactCard ? 4 : 6,
                                    ),
                                    child: Text(
                                      _netVotes > 0
                                          ? '+$_netVotes'
                                          : '$_netVotes',
                                      style: GoogleFonts.inter(
                                        fontSize: isCompactCard ? 11 : 12,
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
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _toggleBookmark,
                                child: Padding(
                                  padding: EdgeInsets.all(
                                    isCompactCard ? 6 : 8,
                                  ),
                                  child: Icon(
                                    _isBookmarked
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    size: isCompactCard ? 18 : 20,
                                    color: _isBookmarked
                                        ? AppTheme.warning
                                        : AppTheme.textMuted,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: isCompactCard ? 12 : 16),
                            if (widget.resource.type == 'notes' ||
                                widget.resource.type == 'pyq') ...[
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => _handleDownload(context),
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                      isCompactCard ? 6 : 8,
                                    ),
                                    child: _isDownloaded
                                        ? Icon(
                                            Icons.offline_pin,
                                            size: isCompactCard ? 18 : 20,
                                            color: AppTheme.success,
                                          )
                                        : Icon(
                                            Icons.download_rounded,
                                            size: isCompactCard ? 18 : 20,
                                            color: AppTheme.textMuted,
                                          ),
                                  ),
                                ),
                              ),
                              SizedBox(width: isCompactCard ? 8 : 12),
                            ],
                            Text(
                              widget.resource.formattedDate,
                              style: GoogleFonts.inter(
                                fontSize: isCompactCard ? 9 : 10,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasActionControls) ...[
                        const SizedBox(height: 10),
                        if (moderationMetaRow != null) ...[
                          moderationMetaRow,
                          if (moderationButtons.isNotEmpty)
                            const SizedBox(height: 8),
                        ],
                        ...moderationButtons,
                      ],
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
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
    final statusBadge = _buildStatusBadge();
    final teacherProfile = _buildTeacherProfileButton();
    final deleteButton = _buildDeleteIconButton();
    if (statusBadge == null && teacherProfile == null && deleteButton == null) {
      return null;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [?statusBadge, ?teacherProfile, ?deleteButton],
    );
  }

  Widget? _buildStatusBadge() {
    if (!widget.showStatusBadge) return null;

    final status = widget.resource.status.trim().toLowerCase();
    late final Color color;
    late final String label;
    late final IconData icon;

    switch (status) {
      case 'approved':
        color = AppTheme.success;
        label = 'Approved';
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'rejected':
        color = AppTheme.error;
        label = 'Rejected';
        icon = Icons.cancel_outlined;
        break;
      case 'pending':
      default:
        color = AppTheme.warning;
        label = 'Pending';
        icon = Icons.schedule_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
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
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        return AppTheme.error;
      case 'pyq':
        return AppTheme.warning;
      case 'notice':
        return AppTheme.noticeColor;
      case 'notes':
      default:
        return AppTheme.primary;
    }
  }

  Widget _buildAuthorWidget({bool compact = false}) {
    final name = widget.resource.uploadedByName;
    final email = widget.resource.uploadedByEmail;

    if (name == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: 'View profile for $name',
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _openUserProfile(email, name),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: compact ? 0 : 48,
              minHeight: compact ? 0 : 48,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: compact ? 2 : 8,
                horizontal: compact ? 2 : 4,
              ),
              child: Semantics(
                label: 'Open profile for $name',
                button: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'by $name',
                      style: GoogleFonts.inter(
                        fontSize: compact ? 11 : 12,
                        color: AppTheme.textMuted,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.textMuted,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      UserBadge(email: email, size: compact ? 11 : 12),
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
}
