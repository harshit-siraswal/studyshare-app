import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/theme.dart';
import '../../utils/youtube_link_utils.dart';
import '../../widgets/ai_study_tools_sheet.dart';
import '../../widgets/branded_loader.dart';

class YoutubePlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? resourceId;
  final String? collegeId;
  final String? subject;
  final String? semester;
  final String? branch;

  const YoutubePlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    this.resourceId,
    this.collegeId,
    this.subject,
    this.semester,
    this.branch,
  });

  @override
  State<YoutubePlayerScreen> createState() => _YoutubePlayerScreenState();
}

class _YoutubePlayerScreenState extends State<YoutubePlayerScreen> {
  ParsedYoutubeLink? _youtubeLink;
  WebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  bool _didTryWatchFallback = false;
  int _currentStartSeconds = 0;
  String _errorMessage = 'Unable to load video.';

  bool _isTrustedYoutubeHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'youtube.com' ||
        normalized == 'www.youtube.com' ||
        normalized == 'm.youtube.com' ||
        normalized == 'youtu.be' ||
        normalized == 'www.youtu.be' ||
        normalized == 'youtube-nocookie.com' ||
        normalized == 'www.youtube-nocookie.com';
  }

  bool _isAllowedYoutubeNavigation(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    if (uri.scheme == 'about') return true;
    if (uri.scheme != 'https') return false;
    return _isTrustedYoutubeHost(uri.host);
  }

  @override
  void initState() {
    super.initState();
    _setupPlayer();
  }

  void _setupPlayer() {
    _didTryWatchFallback = false;
    final parsed = parseYoutubeLink(widget.videoUrl);
    if (parsed == null) {
      setState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage = 'Invalid YouTube link';
      });
      return;
    }

    _youtubeLink = parsed;
    _currentStartSeconds = parsed.startSeconds;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_isAllowedYoutubeNavigation(request.url)) {
              return NavigationDecision.navigate;
            }
            debugPrint(
              'Blocked unexpected YouTube WebView URL: ${request.url}',
            );
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() => _isLoading = true);
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true &&
                !_didTryWatchFallback &&
                _youtubeLink != null) {
              _didTryWatchFallback = true;
              _webViewController?.loadRequest(_youtubeLink!.watchUri);
              return;
            }
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
                _errorMessage = error.description;
              });
            }
          },
        ),
      )
      ..loadRequest(parsed.embedUri);
    _webViewController = controller;
  }

  List<int> _chapterJumpSeconds() {
    final markers = <int>{0, 300, 600, 900, 1200};
    if (_youtubeLink != null && _youtubeLink!.startSeconds > 0) {
      markers.add(_youtubeLink!.startSeconds);
    }
    final sorted = markers.toList()..sort();
    return sorted.where((seconds) => seconds <= 3600).toList();
  }

  String _formatTimestamp(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final secs = safe % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _jumpToSecond(int seconds) async {
    final link = _youtubeLink;
    if (link == null || _webViewController == null) return;
    final bounded = seconds.clamp(0, 24 * 3600).toInt();
    setState(() {
      _currentStartSeconds = bounded;
      _hasError = false;
      _isLoading = true;
      _didTryWatchFallback = false;
    });
    final embedUri = buildYoutubeEmbedUri(link.videoId, startSeconds: bounded);
    await _webViewController!.loadRequest(embedUri);
  }

  Future<void> _openInYoutube() async {
    final link = _youtubeLink;
    if (link == null) return;
    if (await launchUrl(link.appUri, mode: LaunchMode.externalApplication)) {
      return;
    }
    if (await launchUrl(link.watchUri, mode: LaunchMode.externalApplication)) {
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open YouTube app')));
  }

  void _openAiStudioSheet({int initialTabIndex = 0, String? autoGenerateType}) {
    final resourceId = widget.resourceId?.trim() ?? '';
    if (resourceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI Studio is not linked to this video.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => AiStudyToolsSheet(
        resourceId: resourceId,
        resourceTitle: widget.title,
        collegeId: widget.collegeId,
        subject: widget.subject,
        semester: widget.semester,
        branch: widget.branch,
        resourceType: 'video',
        videoUrl: _youtubeLink?.watchUri.toString() ?? widget.videoUrl,
        initialTabIndex: initialTabIndex,
        autoGenerateType: autoGenerateType,
      ),
    );
  }

  Widget _buildStudioFeatureChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : color.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPanel() {
    if (_hasError) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white70),
            const SizedBox(height: 10),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                    });
                    if (_webViewController == null) {
                      _setupPlayer();
                      return;
                    }
                    _jumpToSecond(_currentStartSeconds);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry in app'),
                ),
                FilledButton.icon(
                  onPressed: _openInYoutube,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open in YouTube'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (_webViewController == null) {
      return Container(color: Colors.black);
    }
    return Stack(
      children: [
        WebViewWidget(controller: _webViewController!),
        if (_isLoading)
          const ColoredBox(
            color: Colors.black,
            child: Center(child: BrandedLoader(message: 'Loading video...')),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Open in YouTube',
            onPressed: _openInYoutube,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: _buildVideoPanel()),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openInYoutube,
                  icon: const Icon(Icons.play_circle_fill_rounded),
                  label: const Text('Open in YouTube'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: const Color(0xFFE11D48),
                    foregroundColor: Colors.white,
                    textStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.darkBorder
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Studio',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Generate smart outputs from this video instantly.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF475569),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Chapter jumps',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _chapterJumpSeconds().map((seconds) {
                          final selected = _currentStartSeconds == seconds;
                          return ChoiceChip(
                            selected: selected,
                            label: Text(_formatTimestamp(seconds)),
                            onSelected: (_) => _jumpToSecond(seconds),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white12
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Study assist',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _openAiStudioSheet(
                                    initialTabIndex: 0,
                                    autoGenerateType: 'summary',
                                  ),
                                  icon: const Icon(
                                    Icons.subtitles_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Transcript Highlights'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _openAiStudioSheet(
                                    initialTabIndex: 0,
                                    autoGenerateType: 'summary',
                                  ),
                                  icon: const Icon(
                                    Icons.notes_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('AI Notes'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _openAiStudioSheet(initialTabIndex: 3),
                                  icon: const Icon(
                                    Icons.chat_bubble_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Ask AI'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildStudioFeatureChip(
                            icon: Icons.summarize_rounded,
                            label: 'Summary',
                            color: const Color(0xFF2563EB),
                            isDark: isDark,
                          ),
                          _buildStudioFeatureChip(
                            icon: Icons.quiz_rounded,
                            label: 'Quiz',
                            color: const Color(0xFFF97316),
                            isDark: isDark,
                          ),
                          _buildStudioFeatureChip(
                            icon: Icons.style_rounded,
                            label: 'Flash Cards',
                            color: const Color(0xFF14B8A6),
                            isDark: isDark,
                          ),
                          _buildStudioFeatureChip(
                            icon: Icons.chat_bubble_rounded,
                            label: 'AI Chat',
                            color: const Color(0xFF7C3AED),
                            isDark: isDark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _openAiStudioSheet,
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text('Open AI Studio'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            textStyle: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
