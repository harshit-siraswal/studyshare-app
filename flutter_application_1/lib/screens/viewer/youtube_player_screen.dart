import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

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

  YoutubePlayerController? _playerController;
  int _currentStartSeconds = 0;
  String? _playerErrorMessage;

  ParsedYoutubeLink get _activeLink =>
      widget.youtubeLink.copyWith(startSeconds: _currentStartSeconds);

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

  @override
  void dispose() {
    final controller = _playerController;
    _playerController = null;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      ),
    );
    if (controller != null) {
      unawaited(controller.close());
    }
    super.dispose();
  }

  void _setupPlayer() {
    final existingController = _playerController;
    if (existingController != null) {
      unawaited(existingController.close());
    }

    final controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        userAgent: _mobileChromeUserAgent,
      ),
      onWebResourceError: (error) {
        if (!mounted) return;
        setState(() {
          _playerErrorMessage = error.description.trim().isNotEmpty
              ? error.description.trim()
              : _genericLoadErrorMessage;
        });
      },
    );

    unawaited(
      controller.cueVideoById(
        videoId: widget.youtubeLink.videoId,
        startSeconds: _currentStartSeconds.toDouble(),
      ),
    );

    controller.setFullScreenListener((isFullScreen) {
      if (!mounted) return;
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: isFullScreen
            ? const <SystemUiOverlay>[]
            : SystemUiOverlay.values,
      );
    });

    setState(() {
      _playerController = controller;
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
    final controller = _playerController;
    if (controller == null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    if (_playerErrorMessage != null) {
      return AspectRatio(aspectRatio: 16 / 9, child: _buildPlayerError());
    }

    return YoutubePlayer(
      key: ValueKey<String>(
        '${widget.youtubeLink.videoId}-${_currentStartSeconds.toString()}',
      ),
      controller: controller,
      aspectRatio: 16 / 9,
      backgroundColor: Colors.black,
      enableFullScreenOnVerticalDrag: false,
      keepAlive: true,
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
