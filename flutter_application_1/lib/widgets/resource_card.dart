import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
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
  final VoidCallback? onVoteChanged;

  const ResourceCard({
    super.key,
    required this.resource,
    required this.userEmail,
    this.onVoteChanged,
  });

  @override
  State<ResourceCard> createState() => _ResourceCardState();
}

class _ResourceCardState extends State<ResourceCard> {
  final SupabaseService _supabaseService = SupabaseService();
  int _upvotes = 0;
  int _downvotes = 0;
  int? _userVote;
  bool _isBookmarked = false;
  bool _isVoting = false;

  @override
  void initState() {
    super.initState();
    _upvotes = widget.resource.upvotes;
    _downvotes = widget.resource.downvotes;
    _checkBookmark();
  }

  Future<void> _checkBookmark() async {
    final bookmarked = await _supabaseService.isBookmarked(
      widget.userEmail,
      widget.resource.id,
    );
    if (mounted) setState(() => _isBookmarked = bookmarked);
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
          const SnackBar(content: Text('Unable to update bookmark. Please try again.')),
        );
      }
    }
  }
  Future<void> _vote(int direction) async {
    if (_isVoting) return;
    setState(() => _isVoting = true);
    try {
      final oldVote = _userVote;
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
      // Handle error
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  Future<void> _handleDownload(BuildContext context) async {
    final ds = DownloadService();
    // 1. Check if already downloaded
    if (ds.isDownloaded(widget.resource.id)) {
      final path = ds.getLocalPath(widget.resource.id);
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
        builder: (_) => PaywallDialog(onSuccess: () {
             setState(() {}); // refresh state to likely remove lock
             _handleDownload(context); // retry download
        }),
      );
      return;
    }

    // 3. Download
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading...')));
      await ds.downloadResource(
        widget.resource.fileUrl, 
        widget.resource, 
      );
      setState(() {}); // refresh icon
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download Complete!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
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
        title: Text(widget.resource.title, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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
                        errorBuilder: (_, __, ___) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey),
                              const SizedBox(height: 8),
                              Text('Image not found', style: GoogleFonts.inter(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 12),
              Text(widget.resource.description ?? '', style: GoogleFonts.inter(fontSize: 14)),
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

  void _showPDFViewer() {
    if (widget.resource.fileUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file available')),
      );
      return;
    }

    final downloadService = DownloadService();
    final localPath = downloadService.getLocalPath(widget.resource.id);
    final url = (localPath != null && File(localPath).existsSync()) 
        ? localPath 
        : widget.resource.fileUrl;

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
    // ... no change needed in build if _openResource is handling dispatch ...
    // But we need to update _getTypeIcon and _getTypeColor below
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
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
                child: Icon(
                  _getTypeIcon(),
                  color: _getTypeColor(),
                  size: 24,
                ),
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
                            color: isDark ? AppTheme.textLight : AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    _netVotes > 0 ? '+$_netVotes' : '$_netVotes',
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
                                  _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
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
                          if (widget.resource.type == 'notes' || widget.resource.type == 'pyq') ...[
                             GestureDetector(
                                onTap: () => _handleDownload(context),
                                child: DownloadService().isDownloaded(widget.resource.id)
                                    ? Icon(Icons.offline_pin, size: 20, color: AppTheme.success)
                                    : Icon(Icons.download_rounded, size: 20, color: AppTheme.textMuted),
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
                  ],
                ),
              ),
            ],
          ),
        ),
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
            color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
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
        return AppTheme.error;   // Red
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
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                  userEmail: email,
                  userName: name,
                ),
              ),
            );
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
                    const SizedBox(width: 4),
                    UserBadge(email: email, size: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  

  }
} // End of _ResourceCardState

// Embedded PDF Viewer Dialog
class _PDFViewerDialog extends StatelessWidget {
  final String url;
  final String title;

  const _PDFViewerDialog({
    required this.url,
    required this.title,
  });

  Future<void> _openInBrowser(BuildContext context) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: screenSize.width * 0.95,
        height: screenSize.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.grey.shade100,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _openInBrowser(context),
                    icon: Icon(
                      Icons.open_in_new,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    tooltip: 'Open in browser',
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            
            // PDF Preview Content
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkBackground : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.picture_as_pdf,
                        size: 64,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'PDF Document',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Click below to view',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _openInBrowser(context),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open PDF'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
}
