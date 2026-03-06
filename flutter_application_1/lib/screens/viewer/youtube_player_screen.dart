import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/app_config.dart';
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
  static const Duration _inAppLoadTimeout = Duration(seconds: 28);
  static final Uri _youtubeOriginUri = Uri.parse(
    'https://${AppConfig.webDomain}/',
  );

  ParsedYoutubeLink? _youtubeLink;
  WebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  bool _didAutoFallbackToExternal = false;
  int _currentStartSeconds = 0;
  String _errorMessage = 'Unable to load video.';
  Timer? _loadTimeoutTimer;

  bool _isTrustedYoutubeHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'youtube.com' ||
        normalized == 'www.youtube.com' ||
        normalized == 'm.youtube.com' ||
        normalized == 'music.youtube.com' ||
        normalized == 'youtu.be' ||
        normalized == 'www.youtu.be' ||
        normalized == 'consent.youtube.com' ||
        normalized == 'youtube-nocookie.com' ||
        normalized == 'www.youtube-nocookie.com' ||
        normalized == 'google.com' ||
        normalized == 'www.google.com' ||
        normalized == 'accounts.google.com';
  }

  bool _isAllowedYoutubeNavigation(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    if (uri.scheme == 'about') return true;
    if (uri.scheme == 'intent' ||
        uri.scheme == 'vnd.youtube' ||
        uri.scheme == 'youtube') {
      return true;
    }
    if (uri.scheme != 'https') return false;
    return _isTrustedYoutubeHost(uri.host);
  }

  void _scheduleLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(_inAppLoadTimeout, () {
      if (!mounted || !_isLoading || _youtubeLink == null) return;
      debugPrint('YouTube WebView timed out; falling back to external launch.');
      unawaited(_autoFallbackToExternal('webview_timeout'));
    });
  }

  void _cancelLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
  }

  Uri _buildEmbedUri(String videoId, {int startSeconds = 0}) {
    return buildYoutubeEmbedUri(
      videoId,
      startSeconds: startSeconds,
      origin: _youtubeOriginUri.origin,
    );
  }

  Map<String, String> _youtubeRequestHeaders() {
    return <String, String>{
      'Referer': _youtubeOriginUri.toString(),
      'Origin': _youtubeOriginUri.origin,
      'X-Requested-With': AppConfig.androidBundleId,
    };
  }

  Future<void> _inspectLoadedPageForEmbedErrors() async {
    final controller = _webViewController;
    if (controller == null || _didAutoFallbackToExternal) return;
    try {
      final jsResult = await controller.runJavaScriptReturningResult(
        "(() => (document?.body?.innerText || '').slice(0, 2000).toLowerCase())();",
      );
      final pageText = jsResult.toString().toLowerCase();
      final hasEmbedConfigError =
          pageText.contains('watch video on youtube') ||
          pageText.contains('video player configuration error') ||
          pageText.contains('error 153') ||
          pageText.contains('playback on other websites has been disabled');
      if (hasEmbedConfigError) {
        unawaited(_autoFallbackToExternal('youtube_embed_error_153'));
      }
    } catch (_) {
      // Some pages disallow script evaluation during load; ignore and rely on
      // WebView/network callbacks and timeout fallback.
    }
  }

  @override
  void initState() {
    super.initState();
    _setupPlayer();
  }

  @override
  void dispose() {
    _cancelLoadTimeout();
    super.dispose();
  }

  void _setupPlayer() {
    _didAutoFallbackToExternal = false;
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
            final blockedUri = Uri.tryParse(request.url);
            if (blockedUri != null &&
                (blockedUri.scheme == 'intent' ||
                    blockedUri.scheme == 'vnd.youtube' ||
                    blockedUri.scheme == 'youtube')) {
              debugPrint(
                'YouTube WebView emitted app-intent URL; opening externally: '
                '${request.url}',
              );
              unawaited(_autoFallbackToExternal('intent_navigation'));
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
            _scheduleLoadTimeout();
          },
          onPageFinished: (_) {
            _cancelLoadTimeout();
            if (mounted) {
              setState(() => _isLoading = false);
            }
            unawaited(_inspectLoadedPageForEmbedErrors());
          },
          onWebResourceError: (error) {
            debugPrint(
              'YouTube WebView error(main=${error.isForMainFrame}, '
              'code=${error.errorCode}, type=${error.errorType}, '
              'url=${error.url}, desc=${error.description})',
            );
            final description = error.description.toLowerCase();
            final hasTlsOrCertIssue =
                description.contains('ssl') ||
                description.contains('cert') ||
                description.contains('trust anchor') ||
                description.contains('net::err');

            if (hasTlsOrCertIssue) {
              unawaited(_autoFallbackToExternal('webview_tls_or_cert_error'));
            }

            if (error.isForMainFrame == true && mounted) {
              _cancelLoadTimeout();
              setState(() {
                _isLoading = false;
                _hasError = true;
                _errorMessage = error.description;
              });
              unawaited(
                _autoFallbackToExternal('main_frame_web_resource_error'),
              );
            }
          },
        ),
      )
      ..loadRequest(
        _buildEmbedUri(parsed.videoId, startSeconds: parsed.startSeconds),
        headers: _youtubeRequestHeaders(),
      );
    _scheduleLoadTimeout();
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
    });
    final embedUri = _buildEmbedUri(link.videoId, startSeconds: bounded);
    _scheduleLoadTimeout();
    await _webViewController!.loadRequest(
      embedUri,
      headers: _youtubeRequestHeaders(),
    );
  }

  void _setExternalFallbackState(String message) {
    _cancelLoadTimeout();
    if (!mounted) {
      _isLoading = false;
      _hasError = true;
      _errorMessage = message;
      _webViewController = null;
      return;
    }
    setState(() {
      _isLoading = false;
      _hasError = true;
      _errorMessage = message;
      _webViewController = null;
    });
  }

  Future<bool> _launchYoutubeExternally() async {
    final link = _youtubeLink;
    if (link == null) return false;
    if (await launchUrl(link.appUri, mode: LaunchMode.externalApplication)) {
      return true;
    }
    if (await launchUrl(link.watchUri, mode: LaunchMode.externalApplication)) {
      return true;
    }
    return false;
  }

  Future<void> _autoFallbackToExternal(String reason) async {
    if (_didAutoFallbackToExternal) return;
    _didAutoFallbackToExternal = true;
    debugPrint('Auto external YouTube fallback triggered: $reason');
    _setExternalFallbackState(
      'In-app playback is unavailable on this network/device.',
    );
    final opened = await _launchYoutubeExternally();
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open YouTube automatically.')),
    );
  }

  Future<void> _openInYoutube({bool showFailureSnackBar = true}) async {
    final opened = await _launchYoutubeExternally();
    if (opened) return;
    if (!showFailureSnackBar) return;
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
