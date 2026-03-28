import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

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
  static const String _genericLoadErrorMessage =
      'Unable to load this YouTube video right now.';

  YoutubePlayerController? _playerController;
  int _currentStartSeconds = 0;
  String? _playerErrorMessage;

  ParsedYoutubeLink get _activeLink =>
      widget.youtubeLink.copyWith(startSeconds: _currentStartSeconds);

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

  @override
  void dispose() {
    unawaited(_playerController?.close() ?? Future<void>.value());
    super.dispose();
  }

  void _setupPlayer() {
    late final YoutubePlayerController nextController;
    nextController = YoutubePlayerController(
      key: widget.youtubeLink.videoId,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        showVideoAnnotations: false,
        interfaceLanguage: 'en',
        color: 'white',
      ),
      onWebResourceError: (error) {
        if (!mounted || _playerController != nextController) return;
        final description = error.description.trim();
        setState(() {
          _playerErrorMessage = description.isNotEmpty
              ? description
              : _genericLoadErrorMessage;
        });
      },
    );

    final previousController = _playerController;
    setState(() {
      _playerController = nextController;
      _playerErrorMessage = null;
    });

    unawaited(previousController?.close() ?? Future<void>.value());
    unawaited(
      nextController.loadVideoById(
        videoId: widget.youtubeLink.videoId,
        startSeconds: _currentStartSeconds.toDouble(),
      ).catchError((error) {
        if (!mounted || _playerController != nextController) return;
        final description = error?.toString().trim() ?? '';
        setState(() {
          _playerErrorMessage = description.isNotEmpty
              ? description
              : _genericLoadErrorMessage;
        });
      }),
    );
  }

  Future<void> _openInYoutubeApp() async {
    final opened = await openYoutubeInAppOnly(_activeLink);
    if (opened || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open the YouTube app right now.'),
      ),
    );
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
              Icon(
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
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerSurface() {
    final controller = _playerController;
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
        child: YoutubeValueBuilder(
          controller: controller,
          builder: (context, value) {
            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black,
                    child: YoutubePlayer(
                      controller: controller,
                      aspectRatio: 16 / 9,
                    ),
                  ),
                ),
                if (value.playerState == PlayerState.unknown &&
                    !value.hasError &&
                    _playerErrorMessage == null)
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
            );
          },
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
          if (_canUseAiStudio)
            IconButton(
              tooltip: 'AI Studio',
              onPressed: _openAiStudioSheet,
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
          IconButton(
            tooltip: 'Open in YouTube app',
            onPressed: _openInYoutubeApp,
            icon: const Icon(Icons.ondemand_video_rounded),
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
