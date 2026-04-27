import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/app_config.dart';
import '../../utils/youtube_link_utils.dart';
import '../../widgets/ai_study_tools_sheet.dart';

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
  static const String _genericLoadErrorMessage =
      'Unable to load this YouTube video right now.';
  static const String _webUnavailableMessage =
      'In-app YouTube playback is only available in the mobile app.';
  static const String _mobileChromeUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  WebViewController? _webViewController;
  int _currentStartSeconds = 0;
  int _loadingProgress = 0;
  String? _playerErrorMessage;

  ParsedYoutubeLink get _activeLink =>
      widget.youtubeLink.copyWith(startSeconds: _currentStartSeconds);

  bool get _canUseAiStudio => widget.resourceId?.trim().isNotEmpty ?? false;

  Uri get _embedPageUri =>
      Uri.https(AppConfig.webDomain, '/youtube-embed.html', <String, String>{
        'videoId': widget.youtubeLink.videoId,
        if (_currentStartSeconds > 0) 'start': _currentStartSeconds.toString(),
        if (widget.title.trim().isNotEmpty) 'title': widget.title.trim(),
      });

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

  void _setupPlayer() {
    if (kIsWeb) {
      setState(() {
        _webViewController = null;
        _loadingProgress = 0;
        _playerErrorMessage = _webUnavailableMessage;
      });
      return;
    }

    final embedPageUri = _embedPageUri;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(_mobileChromeUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _loadingProgress = progress.clamp(0, 100));
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loadingProgress = 0;
              _playerErrorMessage = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loadingProgress = 100);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            if (!mounted) return;
            setState(() {
              _playerErrorMessage = error.description.trim().isNotEmpty
                  ? error.description.trim()
                  : _genericLoadErrorMessage;
            });
          },
          onNavigationRequest: (request) {
            final requestedUri = Uri.tryParse(request.url);
            if (requestedUri == null) {
              return NavigationDecision.prevent;
            }

            final isHostedEmbedPage =
                requestedUri.host == AppConfig.webDomain &&
                requestedUri.path == '/youtube-embed.html';
            if (isHostedEmbedPage) {
              return NavigationDecision.navigate;
            }

            final isYouTubeNavigation =
                requestedUri.host.contains('youtube.com') ||
                requestedUri.host.contains('youtu.be');
            if (isYouTubeNavigation) {
              _openExternally();
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(embedPageUri);

    setState(() {
      _webViewController = controller;
      _loadingProgress = 0;
      _playerErrorMessage = null;
    });
  }

  Future<void> _openExternally() async {
    await openYoutubeExternally(_activeLink);
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

  Widget _buildPlayerError() {
    final message = (_playerErrorMessage ?? '').trim().isEmpty
        ? _genericLoadErrorMessage
        : _playerErrorMessage!;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
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
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
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
                  FilledButton.icon(
                    onPressed: _openExternally,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open in YouTube'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerSurface() {
    if (_playerErrorMessage != null) {
      return _buildPlayerError();
    }

    final controller = _webViewController;
    if (controller == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: controller),
        if (_loadingProgress < 100)
          Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(
              value: _loadingProgress <= 0 ? null : _loadingProgress / 100,
              minHeight: 2,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF2563EB),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Open in YouTube',
            onPressed: _openExternally,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          if (_canUseAiStudio)
            IconButton(
              tooltip: 'AI Studio',
              onPressed: _openAiStudioSheet,
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
        ],
      ),
      body: SafeArea(child: _buildPlayerSurface()),
    );
  }
}
