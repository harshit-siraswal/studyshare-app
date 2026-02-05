import 'package:flutter/material.dart';
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

class NoticeCard extends StatefulWidget {
  final Map<String, dynamic> notice;
  final DepartmentAccount account;
  final bool isDark;
  
  const NoticeCard({
    super.key,
    required this.notice,
    required this.account,
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
    
    final saved = await _supabaseService.isNoticeSaved(widget.notice['id'], email);
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
        setState(() => _isSaved = false);
      } else {
        await _supabaseService.saveNotice(widget.notice['id'], email);
        setState(() => _isSaved = true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notice saved to bookmarks')),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error toggling saved status: $e\n$stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  




  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final secondaryColor = widget.isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final cardColor = widget.isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = widget.isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    
    final title = widget.notice['title'] ?? 'Untitled';
    final content = widget.notice['content'] ?? '';
    final createdAt = widget.notice['created_at'];
    final timeAgo = _formatTimeAgo(createdAt);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (!widget.isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NoticeDetailScreen(
                  notice: widget.notice,
                  account: widget.account,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
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
                            fontSize: 12,
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
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.account.name,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.verified_rounded, size: 12, color: AppTheme.primary),
                            ],
                          ),
                          Text(
                            timeAgo,
                            style: GoogleFonts.inter(fontSize: 11, color: secondaryColor),
                          ),
                        ],
                      ),
                    ),
                    // Removed 3-dot menu
                  ],
                ),
                const SizedBox(height: 12),
                
                // Title
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
                  Text(
                    content,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: secondaryColor,
                      height: 1.4,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                
                const SizedBox(height: 12),
                
                // Actions
                Row(
                  children: [
                    _buildActionButton(
                      icon: Icons.mode_comment_outlined, 
                      count: 'Comments', 
                      color: secondaryColor,
                      onTap: () {
                         Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => NoticeDetailScreen(
                              notice: widget.notice,
                              account: widget.account,
                            ),
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                    // Bookmark Button
                    InkWell(
                      onTap: _isLoading ? null : _toggleSaved,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                          size: 20,
                          color: _isSaved ? AppTheme.primary : secondaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.share_outlined,
                      count: null,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            if (count != null) ...[
              const SizedBox(width: 4),
              Text(
                count,
                style: GoogleFonts.inter(fontSize: 11, color: color),
              ),
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
  Future<void> _shareAsImage() async {
    final controller = ScreenshotController();

    try {
      final bytes = await controller.captureFromWidget(
        Material(
          color: Colors.white,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: widget.account.color,
                      radius: 20,
                      child: Text(
                        widget.account.avatarLetter,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.account.name,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          'MyStudySpace Notice',
                          style: GoogleFonts.inter(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  widget.notice['title'] ?? 'Untitled',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                // Content
                Text(
                  widget.notice['content'] ?? '',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFF334155),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 30),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'via MyStudySpace',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatTimeAgo(widget.notice['created_at']),
                      style: GoogleFonts.inter(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        delay: const Duration(milliseconds: 50),
        pixelRatio: 2.0,
      );

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/notice_share.png').create();
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Check out this notice on MyStudySpace!',
      );
      
      // Clean up temporary file
      await file.delete();    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate image: $e')),
      );
    }
  }
}


