import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../config/theme.dart';
import '../../utils/youtube_link_utils.dart';
import '../../widgets/ai_study_tools_sheet.dart';
import '../../widgets/branded_loader.dart';
import '../ai_chat_screen.dart';

class YoutubePlayerScreen extends StatefulWidget {
  final ParsedYoutubeLink youtubeLink;
  final String title;
  final String? resourceId;
  final String? collegeId;
  final String? subject;
  final String? semester;
  final String? branch;
  final String? collegeName;

  const YoutubePlayerScreen({
    super.key,
    required this.youtubeLink,
    required this.title,
    this.resourceId,
    this.collegeId,
    this.subject,
    this.semester,
    this.branch,
    this.collegeName,
  });

  @override
  State<YoutubePlayerScreen> createState() => _YoutubePlayerScreenState();
}

class _YoutubePlayerScreenState extends State<YoutubePlayerScreen> {
  WebViewController? _webViewController;
  bool _isPlayerLoading = true;
  bool _isPlayerReady = false;
  int _currentStartSeconds = 0;
  String? _playerErrorMessage;
  int _playerLoadToken = 0;

  ParsedYoutubeLink get _activeLink =>
      widget.youtubeLink.copyWith(startSeconds: _currentStartSeconds);

  @override
  void initState() {
    super.initState();
    _currentStartSeconds = widget.youtubeLink.startSeconds;
    _setupPlayer();
  }

  @override
  void didUpdateWidget(covariant YoutubePlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeLink.videoId != widget.youtubeLink.videoId ||
        oldWidget.youtubeLink.startSeconds != widget.youtubeLink.startSeconds) {
      _currentStartSeconds = widget.youtubeLink.startSeconds;
      _setupPlayer();
    }
  }

  @override
  void dispose() {
    _playerLoadToken++;
    _webViewController = null;
    super.dispose();
  }

  void _setupPlayer({int? startSeconds}) {
    final nextStartSeconds = startSeconds ?? _currentStartSeconds;
    _playerLoadToken++;
    _webViewController = null;
    setState(() {
      _currentStartSeconds = nextStartSeconds;
      _isPlayerLoading = true;
      _isPlayerReady = false;
      _playerErrorMessage = null;
    });
    unawaited(_loadPlayerForLink(_activeLink));
  }

  Future<void> _loadPlayerForLink(ParsedYoutubeLink link) async {
    final token = _playerLoadToken;
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
    }
    await controller.setBackgroundColor(Colors.black);
    await controller.addJavaScriptChannel(
      'StudySharePlayer',
      onMessageReceived: (message) {
        if (!mounted || _playerLoadToken != token) return;
        if (message.message == 'player_ready') {
          setState(() {
            _isPlayerLoading = false;
            _isPlayerReady = true;
            _playerErrorMessage = null;
          });
          return;
        }
        if (message.message.startsWith('error:')) {
          setState(() {
            _isPlayerLoading = false;
            _playerErrorMessage = message.message
                .substring('error:'.length)
                .trim();
          });
        }
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onWebResourceError: (error) {
          if (!mounted || _playerLoadToken != token) return;
          setState(() {
            _isPlayerLoading = false;
            _playerErrorMessage = error.description.trim().isNotEmpty
                ? error.description.trim()
                : 'Unable to load this YouTube video right now.';
          });
        },
      ),
    );

    if (!mounted || _playerLoadToken != token) return;
    setState(() => _webViewController = controller);

    try {
      await controller.loadHtmlString(
        _buildPlayerHtml(link),
        baseUrl: link.watchUri.toString(),
      );
    } catch (error) {
      if (!mounted || _playerLoadToken != token) return;
      setState(() {
        _isPlayerLoading = false;
        _playerErrorMessage = 'Unable to load this YouTube video right now.';
      });
      debugPrint('YoutubePlayerScreen load error: $error');
    }
  }

  Future<void> _openInYoutube({bool showFailureSnackBar = true}) async {
    final opened = await openYoutubeExternally(_activeLink);
    if (opened || !showFailureSnackBar || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open YouTube right now.')),
    );
  }

  Future<void> _openInBrowser() async {
    final opened = await launchExternalUri(_activeLink.watchUri);
    if (opened || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the video link.')),
    );
  }

  Future<void> _jumpToSecond(int seconds) async {
    final bounded = seconds.clamp(0, 24 * 3600);
    if (_isPlayerReady && _webViewController != null) {
      try {
        await _webViewController!.runJavaScript(
          'if(window._ytPlayer&&window._ytPlayer.seekTo){window._ytPlayer.seekTo($bounded,true);}',
        );
        setState(() => _currentStartSeconds = bounded);
        return;
      } catch (e) {
        debugPrint('JS seekTo failed, falling back to full reload: $e');
      }
    }
    _setupPlayer(startSeconds: bounded);
  }

  List<int> _chapterJumpSeconds() {
    final markers = <int>{0, 300, 600, 900, 1200};
    if (widget.youtubeLink.startSeconds > 0) {
      markers.add(widget.youtubeLink.startSeconds);
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
        videoUrl: _activeLink.watchUri.toString(),
        initialTabIndex: initialTabIndex,
        autoGenerateType: autoGenerateType,
      ),
    );
  }

  /// Error codes 101 and 150 mean the video owner has disabled embedding.
  /// Error 2 = invalid video ID; error 5 = HTML5 player error.
  /// We treat 101, 150, and 152 as "embedding disabled" for messaging.
  static const _embeddingDisabledCodes = {101, 150, 152};

  bool get _isEmbeddingError {
    final msg = _playerErrorMessage ?? '';
    final codeMatch = RegExp(r'error code (\d+)').firstMatch(msg);
    if (codeMatch == null) return false;
    final code = int.tryParse(codeMatch.group(1)!) ?? -1;
    return _embeddingDisabledCodes.contains(code);
  }

  String _buildPlayerHtml(ParsedYoutubeLink link) {
    final videoId = link.videoId;
    final start = link.startSeconds;
    final origin = link.watchUri.origin;
    return '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"
    >
    <style>
      html, body {
        margin: 0;
        padding: 0;
        width: 100%;
        height: 100%;
        background: #000;
        overflow: hidden;
      }
      #player {
        position: fixed;
        inset: 0;
        width: 100%;
        height: 100%;
      }
    </style>
    <script>
      function studyShareNotify(message) {
        if (window.StudySharePlayer) {
          StudySharePlayer.postMessage(message);
        }
      }
      var tag = document.createElement('script');
      tag.src = 'https://www.youtube.com/iframe_api';
      var firstScriptTag = document.getElementsByTagName('script')[0];
      firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
      function onYouTubeIframeAPIReady() {
        window._ytPlayer = new YT.Player('player', {
          host: '$origin',
          videoId: '$videoId',
          playerVars: {
            autoplay: 1,
            start: $start,
            playsinline: 1,
            rel: 0,
            modestbranding: 1,
            enablejsapi: 1,
            origin: '$origin',
          },
          events: {
            onReady: function(event) {
              studyShareNotify('player_ready');
            },
            onError: function(event) {
              studyShareNotify('error:YouTube player error code ' + event.data);
            },
          },
        });
      }
    </script>
  </head>
  <body>
    <div id="player"></div>
  </body>
</html>
''';
  }



  Widget _buildPlayerError() {
    final isEmbedError = _isEmbeddingError;
    final message = isEmbedError
        ? 'This video cannot be played in-app.\nPlease open it in YouTube.'
        : (_playerErrorMessage == null || _playerErrorMessage!.isEmpty)
            ? 'Unable to load video.'
            : _playerErrorMessage!;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isEmbedError
                    ? Icons.videocam_off_rounded
                    : Icons.error_outline_rounded,
                color: Colors.white70,
                size: 28,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              // Primary action: Open in YouTube (especially for embed errors)
              FilledButton.icon(
                onPressed: _openInYoutube,
                icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                label: const Text('Open in YouTube'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 40),
                  textStyle: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (!isEmbedError) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _setupPlayer,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerSurface() {
    final controller = _webViewController;
    if (controller == null) {
      if (_playerErrorMessage != null) {
        return AspectRatio(aspectRatio: 16 / 9, child: _buildPlayerError());
      }
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: WebViewWidget(controller: controller),
              ),
            ),
            if (_isPlayerLoading && _playerErrorMessage == null)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: BrandedLoader(message: 'Loading video...'),
                  ),
                ),
              ),
            if (_playerErrorMessage != null)
              Positioned.fill(child: _buildPlayerError()),
          ],
        ),
      ),
    );
  }

  Widget _buildExternalActions() {
    return Row(
      children: [
        Expanded(
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
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openInBrowser,
            icon: const Icon(Icons.language_rounded),
            label: const Text('Open in browser'),
            style: OutlinedButton.styleFrom(
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
    );
  }

  Widget _buildAiActionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors.last.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          highlightColor: Colors.white.withValues(alpha: 0.1),
          splashColor: Colors.white.withValues(alpha: 0.2),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
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

  Widget _buildScreen({required bool isDark}) {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _buildPlayerSurface(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _buildExternalActions(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openAiStudioSheet,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('Open AI Studio'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: AIChatScreen(
                collegeId: widget.collegeId ?? '',
                collegeName: widget.collegeName ?? '',
                resourceContext: (widget.resourceId?.trim().isNotEmpty ?? false)
                    ? ResourceContext(
                        fileId: widget.resourceId!,
                        title: widget.title,
                        subject: widget.subject,
                        semester: widget.semester,
                        branch: widget.branch,
                        videoUrl: _activeLink.watchUri.toString(),
                      )
                    : null,
                embedded: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _buildScreen(isDark: isDark);
  }
}
