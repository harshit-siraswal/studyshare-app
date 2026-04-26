import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/theme.dart';
import '../../utils/youtube_link_utils.dart';
import '../../widgets/ai_study_tools_sheet.dart';
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

  Uri get _watchUri => _activeLink.watchUri;

  bool get _canUseAiStudio => widget.resourceId?.trim().isNotEmpty ?? false;
  bool get _hasVideoTranscriptContext =>
      (widget.resourceId?.trim().isNotEmpty ?? false) ||
      _activeLink.watchUri.toString().trim().isNotEmpty;

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
      ..loadRequest(_watchUri);

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

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 800,
                    maxHeight: 420,
                  ),
                  child: _buildPlayerSurface(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AIChatScreen(
                collegeId: widget.collegeId ?? '',
                collegeName: widget.collegeName ?? '',
                resourceContext: _hasVideoTranscriptContext
                    ? ResourceContext(
                        fileId: widget.resourceId?.trim().isEmpty == true
                            ? null
                            : widget.resourceId?.trim(),
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
