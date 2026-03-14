import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../../config/theme.dart';
import '../../screens/ai_chat_screen.dart';
import '../../widgets/ai_study_tools_sheet.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? resourceId;
  final String? collegeId;
  final String? collegeName;
  final String? subject;
  final String? semester;
  final String? branch;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    this.resourceId,
    this.collegeId,
    this.collegeName,
    this.subject,
    this.semester,
    this.branch,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initController() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse(widget.videoUrl);
      final controller = uri.isScheme('http') || uri.isScheme('https')
          ? VideoPlayerController.networkUrl(uri)
          : VideoPlayerController.file(File(widget.videoUrl));
      await controller.initialize();
      controller.setLooping(false);
      setState(() {
        _controller = controller;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to play this video in-app.';
      });
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
      _scheduleControlsHide();
    }
    setState(() {});
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showControls = false);
    });
  }

  void _toggleControlsVisibility() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleControlsHide();
    }
  }

  void _openAiStudioSheet() {
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
        collegeName: widget.collegeName,
        subject: widget.subject,
        semester: widget.semester,
        branch: widget.branch,
        resourceType: 'video',
        videoUrl: widget.videoUrl,
        initialTabIndex: 3,
      ),
    );
  }

  Widget _buildPlayerSurface(bool isDark) {
    if (_isLoading) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white70),
          ),
        ),
      );
    }

    final controller = _controller!;
    return GestureDetector(
      onTap: _toggleControlsVisibility,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            children: [
              Positioned.fill(child: VideoPlayer(controller)),
              if (_showControls)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: IconButton(
                        iconSize: 56,
                        color: Colors.white,
                        onPressed: _togglePlay,
                        icon: Icon(
                          controller.value.isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 8,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: AppTheme.primary,
                    bufferedColor: Colors.white30,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canUseAi = (widget.resourceId?.trim().isNotEmpty ?? false);
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _buildPlayerSurface(isDark),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canUseAi ? _openAiStudioSheet : null,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('Open AI Studio'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AIChatScreen(
                collegeId: widget.collegeId ?? '',
                collegeName: widget.collegeName ?? '',
                resourceContext: canUseAi
                    ? ResourceContext(
                        fileId: widget.resourceId!,
                        title: widget.title,
                        subject: widget.subject,
                        semester: widget.semester,
                        branch: widget.branch,
                        videoUrl: widget.videoUrl,
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
}
