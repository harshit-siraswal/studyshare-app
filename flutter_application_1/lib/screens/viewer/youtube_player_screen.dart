import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  static const String _mobileChromeUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  WebViewController? _webViewController;
  int _currentStartSeconds = 0;
  String? _playerErrorMessage;
  int _loadProgress = 0;

  ParsedYoutubeLink get _activeLink =>
      widget.youtubeLink.copyWith(startSeconds: _currentStartSeconds);

  Uri get _embedUri => _activeLink.embedUri;

  bool _isAllowedPlayerNavigation(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    if (uri.scheme == 'about') return true;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final isYoutubeHost =
        host == 'www.youtube.com' ||
        host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'www.youtube-nocookie.com' ||
        host == 'youtube-nocookie.com';
    if (!isYoutubeHost) return false;
    return path.startsWith('/embed/') ||
        path.startsWith('/iframe_api') ||
        path.startsWith('/youtubei/') ||
        path.startsWith('/s/player/');
  }

  bool get _canUseAiStudio => widget.resourceId?.trim().isNotEmpty ?? false;

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
        _playerErrorMessage = 'In-app YouTube playback is not available here.';
        _loadProgress = 0;
      });
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(_mobileChromeUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url.trim();
            if (_isAllowedPlayerNavigation(url)) {
              return NavigationDecision.navigate;
            }
            _openExternally();
            return NavigationDecision.prevent;
          },
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _loadProgress = progress.clamp(0, 100));
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _playerErrorMessage = null;
              _loadProgress = 0;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loadProgress = 100);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _playerErrorMessage = error.description.trim().isNotEmpty
                  ? error.description.trim()
                  : _genericLoadErrorMessage;
            });
          },
        ),
      )
      ..loadRequest(_embedUri);

    setState(() {
      _webViewController = controller;
      _playerErrorMessage = null;
      _loadProgress = 0;
    });
  }

  Future<void> _openExternally() async {
    await launchUrl(_activeLink.watchUri, mode: LaunchMode.externalApplication);
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
    final controller = _webViewController;
    if (controller == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: _playerErrorMessage == null
            ? const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            : _buildPlayerError(),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: controller)),
          if (_loadProgress < 100 && _playerErrorMessage == null)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black12,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
            ),
          if (_playerErrorMessage != null)
            Positioned.fill(child: _buildPlayerError()),
          if (_loadProgress < 100 && _playerErrorMessage == null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(
                value: _loadProgress / 100,
                minHeight: 2.5,
                backgroundColor: Colors.white10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScreen() {
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: _buildPlayerSurface(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildScreen();
  }
}
