import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

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
  ParsedYoutubeLink? _youtubeLink;
  YoutubePlayerController? _playerController;
  StreamSubscription<YoutubePlayerValue>? _playerSubscription;
  bool _playerReady = false;
  bool _didAutoFallbackToExternal = false;
  int _currentStartSeconds = 0;
  String? _playerErrorMessage;

  @override
  void initState() {
    super.initState();
    _setupPlayer();
  }

  @override
  void dispose() {
    _playerSubscription?.cancel();
    final controller = _playerController;
    if (controller != null) {
      unawaited(controller.close());
    }
    super.dispose();
  }

  void _setupPlayer() {
    final parsed = parseYoutubeLink(widget.videoUrl);
    if (parsed == null) {
      setState(() {
        _youtubeLink = null;
        _playerController = null;
        _playerReady = false;
        _playerErrorMessage = 'Invalid YouTube link';
      });
      return;
    }

    _playerSubscription?.cancel();
    final previousController = _playerController;
    if (previousController != null) {
      unawaited(previousController.close());
    }

    final controller = YoutubePlayerController.fromVideoId(
      videoId: parsed.videoId,
      autoPlay: false,
      startSeconds: parsed.startSeconds > 0
          ? parsed.startSeconds.toDouble()
          : null,
      params: YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        enableCaption: true,
        strictRelatedVideos: true,
        interfaceLanguage: 'en',
        playsInline: true,
        origin: 'https://${AppConfig.webDomain}',
      ),
    );

    _playerSubscription = controller.stream.listen(_handlePlayerValueChanged);

    setState(() {
      _youtubeLink = parsed;
      _playerController = controller;
      _playerReady = false;
      _didAutoFallbackToExternal = false;
      _currentStartSeconds = parsed.startSeconds;
      _playerErrorMessage = null;
    });
  }

  void _handlePlayerValueChanged(YoutubePlayerValue value) {
    if (!mounted) return;

    final ready =
        value.metaData.videoId.isNotEmpty ||
        value.playerState == PlayerState.cued ||
        value.playerState == PlayerState.playing ||
        value.playerState == PlayerState.paused ||
        value.playerState == PlayerState.buffering ||
        value.playerState == PlayerState.ended;

    if (ready != _playerReady) {
      setState(() => _playerReady = ready);
    }

    if (!value.hasError) {
      if (_playerErrorMessage != null) {
        setState(() => _playerErrorMessage = null);
      }
      return;
    }

    final message = _youtubeErrorMessage(value.error);
    if (_playerErrorMessage != message) {
      setState(() => _playerErrorMessage = message);
    }

    if (_shouldAutoOpenExternal(value.error)) {
      unawaited(_autoFallbackToExternal('iframe_error_${value.error.code}'));
    }
  }

  String _youtubeErrorMessage(YoutubeError error) {
    switch (error) {
      case YoutubeError.invalidParam:
        return 'This video link is invalid.';
      case YoutubeError.videoNotFound:
      case YoutubeError.cannotFindVideo:
        return 'This video is unavailable.';
      case YoutubeError.notEmbeddable:
      case YoutubeError.sameAsNotEmbeddable:
        return 'This video cannot play inline. Open it in YouTube.';
      case YoutubeError.html5Error:
        return 'In-app playback failed on this device/network.';
      case YoutubeError.unknown:
        return 'Unable to load this YouTube video right now.';
      case YoutubeError.none:
        return '';
    }
  }

  bool _shouldAutoOpenExternal(YoutubeError error) {
    return error == YoutubeError.notEmbeddable ||
        error == YoutubeError.sameAsNotEmbeddable ||
        error == YoutubeError.html5Error;
  }

  Future<bool> _launchYoutubeExternally() async {
    final link = _youtubeLink;
    if (link == null) return false;

    if (await launchUrl(
      link.appUri,
      mode: LaunchMode.externalNonBrowserApplication,
    )) {
      return true;
    }
    if (await launchUrl(
      link.watchUri,
      mode: LaunchMode.externalNonBrowserApplication,
    )) {
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
    final opened = await _launchYoutubeExternally();
    if (opened || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open YouTube automatically.')),
    );
  }

  Future<void> _openInYoutube({bool showFailureSnackBar = true}) async {
    final opened = await _launchYoutubeExternally();
    if (opened || !showFailureSnackBar || !mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open YouTube app')));
  }

  Future<void> _jumpToSecond(int seconds) async {
    final controller = _playerController;
    if (controller == null) return;

    final bounded = seconds.clamp(0, 24 * 3600);
    setState(() {
      _currentStartSeconds = bounded;
      _playerErrorMessage = null;
    });
    await controller.seekTo(seconds: bounded.toDouble(), allowSeekAhead: true);
    await controller.playVideo();
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

  Widget _buildPlayerError() {
    final message =
        (_playerErrorMessage == null || _playerErrorMessage!.isEmpty)
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
              const Icon(Icons.error_outline_rounded, color: Colors.white70),
              const SizedBox(height: 10),
              Text(
                message,
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
                    onPressed: _setupPlayer,
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
        ),
      ),
    );
  }

  Widget _buildPlayerSurface(Widget player) {
    if (_playerController == null) {
      return AspectRatio(aspectRatio: 16 / 9, child: _buildPlayerError());
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: Colors.black, child: player),
          ),
          if (!_playerReady && _playerErrorMessage == null)
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
    );
  }

  Widget _buildScreen({required bool isDark, required Widget playerSection}) {
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
              child: playerSection,
            ),
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _openAiStudioSheet(
                              initialTabIndex: 0,
                              autoGenerateType: 'transcript',
                            ),
                            icon: const Icon(Icons.subtitles_rounded, size: 16),
                            label: const Text('Transcript Highlights'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _openAiStudioSheet(
                              initialTabIndex: 0,
                              autoGenerateType: 'notes',
                            ),
                            icon: const Icon(Icons.notes_rounded, size: 16),
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
                                    autoGenerateType: 'transcript',
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
                                    autoGenerateType: 'notes',
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = _playerController;

    if (controller == null) {
      return _buildScreen(
        isDark: isDark,
        playerSection: AspectRatio(
          aspectRatio: 16 / 9,
          child: _buildPlayerError(),
        ),
      );
    }

    return YoutubePlayerScaffold(
      controller: controller,
      aspectRatio: 16 / 9,
      builder: (context, player) {
        return _buildScreen(
          isDark: isDark,
          playerSection: _buildPlayerSurface(player),
        );
      },
    );
  }
}
