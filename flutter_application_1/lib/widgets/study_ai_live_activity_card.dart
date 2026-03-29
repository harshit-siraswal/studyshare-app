import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/study_ai_live_activity.dart';

class StudyAiLiveActivityCard extends StatelessWidget {
  const StudyAiLiveActivityCard({
    super.key,
    required this.title,
    required this.steps,
    this.answerOrigin,
    this.isRunning = false,
    this.showExport = false,
    this.onOpenPdf,
    this.onOpenUrl,
    this.onOpenVideo,
    this.onExport,
  });

  final String title;
  final AiAnswerOrigin? answerOrigin;
  final List<AiLiveActivityStep> steps;
  final bool isRunning;
  final bool showExport;
  final void Function(String fileId, int? page)? onOpenPdf;
  final void Function(String url)? onOpenUrl;
  final void Function(String url, String? timestamp)? onOpenVideo;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF171717) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);
    final textPrimary = isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final completed = steps
        .where((step) => step.status == AiLiveActivityStatus.completed)
        .length;
    final total = steps.isEmpty ? 1 : steps.length;
    final progress = (completed / total).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Live',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.18,
                  color: textSecondary.withValues(alpha: 0.82),
                ),
              ),
              const SizedBox(width: 8),
              _LiveDot(isRunning: isRunning),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              height: 1.22,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _summaryLabel(answerOrigin, isRunning, completed, steps.length),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 1.5,
              value: progress,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 13),
            Column(
              children: [
                for (var i = 0; i < steps.length; i++)
                  _LiveStepRow(
                    key: ValueKey<String>(steps[i].id),
                    step: steps[i],
                    isDark: isDark,
                    isLast: i == steps.length - 1,
                    onOpenPdf: onOpenPdf,
                    onOpenUrl: onOpenUrl,
                    onOpenVideo: onOpenVideo,
                  ),
              ],
            ),
          ],
          if (showExport && onExport != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onExport,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(38),
                side: BorderSide(color: border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: Icon(
                Icons.download_rounded,
                size: 15,
                color: textSecondary,
              ),
              label: Text(
                'Export generated file',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.isRunning});

  final bool isRunning;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (!widget.isRunning) {
      _controller.stop();
      _controller.value = 1;
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.isRunning
          ? Tween<double>(begin: 0.35, end: 1).animate(_controller)
          : const AlwaysStoppedAnimation<double>(1),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isRunning ? AppTheme.primary : AppTheme.darkTextMuted,
        ),
      ),
    );
  }
}

class _LiveStepRow extends StatefulWidget {
  const _LiveStepRow({
    super.key,
    required this.step,
    required this.isDark,
    required this.isLast,
    this.onOpenPdf,
    this.onOpenUrl,
    this.onOpenVideo,
  });

  final AiLiveActivityStep step;
  final bool isDark;
  final bool isLast;
  final void Function(String fileId, int? page)? onOpenPdf;
  final void Function(String url)? onOpenUrl;
  final void Function(String url, String? timestamp)? onOpenVideo;

  @override
  State<_LiveStepRow> createState() => _LiveStepRowState();
}

class _LiveStepRowState extends State<_LiveStepRow> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.step.status == AiLiveActivityStatus.active;
  }

  @override
  void didUpdateWidget(covariant _LiveStepRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.status == AiLiveActivityStatus.active &&
        oldWidget.step.status != AiLiveActivityStatus.active) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = widget.isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = widget.isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final muted = widget.isDark
        ? AppTheme.darkTextMuted
        : AppTheme.lightTextMuted;
    final hasDetails = widget.step.hasDetails;
    final tone = _toneForStatus(widget.step.status);

    return Padding(
      padding: EdgeInsets.only(bottom: widget.isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
              ),
              if (!widget.isLast)
                Container(
                  width: 1,
                  height: _expanded && hasDetails ? 68 : 28,
                  margin: const EdgeInsets.only(top: 6),
                  color: widget.isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08),
                ),
            ],
          ),
          const SizedBox(width: 9),
          Expanded(
            child: GestureDetector(
              onTap: hasDetails
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.step.title,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _labelForStatus(widget.step.status),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: widget.step.status == AiLiveActivityStatus.active
                              ? AppTheme.primary
                              : muted,
                        ),
                      ),
                    ],
                  ),
                  if (widget.step.description?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        widget.step.description!.trim(),
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w400,
                          color: textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (_expanded && widget.step.events.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final event in widget.step.events)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _EventRow(
                          event: event,
                          isDark: widget.isDark,
                          onOpenPdf: widget.onOpenPdf,
                          onOpenUrl: widget.onOpenUrl,
                          onOpenVideo: widget.onOpenVideo,
                        ),
                      ),
                  ],
                  if (_expanded && widget.step.sources.isNotEmpty)
                    _SourceWrap(
                      sources: widget.step.sources,
                      isDark: widget.isDark,
                      onOpenPdf: widget.onOpenPdf,
                      onOpenUrl: widget.onOpenUrl,
                      onOpenVideo: widget.onOpenVideo,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.isDark,
    this.onOpenPdf,
    this.onOpenUrl,
    this.onOpenVideo,
  });

  final AiLiveActivityEvent event;
  final bool isDark;
  final void Function(String fileId, int? page)? onOpenPdf;
  final void Function(String url)? onOpenUrl;
  final void Function(String url, String? timestamp)? onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.08);
    final textPrimary = isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.title,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          if (event.detail?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                event.detail!.trim(),
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w400,
                  color: textSecondary,
                  height: 1.35,
                ),
              ),
            ),
          if (event.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SourceWrap(
              sources: event.sources,
              isDark: isDark,
              onOpenPdf: onOpenPdf,
              onOpenUrl: onOpenUrl,
              onOpenVideo: onOpenVideo,
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceWrap extends StatelessWidget {
  const _SourceWrap({
    required this.sources,
    required this.isDark,
    this.onOpenPdf,
    this.onOpenUrl,
    this.onOpenVideo,
  });

  final List<AiLiveActivitySource> sources;
  final bool isDark;
  final void Function(String fileId, int? page)? onOpenPdf;
  final void Function(String url)? onOpenUrl;
  final void Function(String url, String? timestamp)? onOpenVideo;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sources
          .map(
            (source) => _SourceChip(
              source: source,
              isDark: isDark,
              onTap: () {
                if (!source.isClickable) return;
                switch (source.kind) {
                  case AiLiveSourceKind.notes:
                    final fileId = source.fileId?.trim() ?? '';
                    if (fileId.isNotEmpty) {
                      onOpenPdf?.call(fileId, source.page);
                    }
                    break;
                  case AiLiveSourceKind.web:
                    final url = source.url?.trim() ?? '';
                    if (url.isNotEmpty) onOpenUrl?.call(url);
                    break;
                  case AiLiveSourceKind.video:
                    final url = source.url?.trim() ?? '';
                    if (url.isNotEmpty) {
                      onOpenVideo?.call(url, source.timestamp);
                    }
                    break;
                }
              },
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.source,
    required this.isDark,
    required this.onTap,
  });

  final AiLiveActivitySource source;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);
    final textColor = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final pageLabel = source.page != null ? ' p.${source.page}' : '';
    final stampLabel =
        source.timestamp?.trim().isNotEmpty == true ? ' ${source.timestamp}' : '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: source.isClickable ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                switch (source.kind) {
                  AiLiveSourceKind.notes => Icons.picture_as_pdf_rounded,
                  AiLiveSourceKind.web => Icons.public_rounded,
                  AiLiveSourceKind.video => Icons.play_circle_outline_rounded,
                },
                size: 13,
                color: textColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${source.title}$pageLabel$stampLabel',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _summaryLabel(
  AiAnswerOrigin? origin,
  bool isRunning,
  int completed,
  int total,
) {
  final progress = '$completed of $total steps complete';
  if (isRunning) {
    return switch (origin) {
      AiAnswerOrigin.notesPlusWeb =>
        'Working through notes and web context - $progress',
      AiAnswerOrigin.webOnly => 'Working through web context - $progress',
      AiAnswerOrigin.insufficientNotes =>
        'Checking limited note context - $progress',
      AiAnswerOrigin.notesOnly || null => 'Processing notes - $progress',
    };
  }
  return progress;
}

Color _toneForStatus(AiLiveActivityStatus status) => switch (status) {
  AiLiveActivityStatus.pending => AppTheme.darkTextMuted,
  AiLiveActivityStatus.active => AppTheme.primary,
  AiLiveActivityStatus.completed => AppTheme.success,
  AiLiveActivityStatus.warning => AppTheme.warning,
  AiLiveActivityStatus.failed => AppTheme.error,
};

String _labelForStatus(AiLiveActivityStatus status) => switch (status) {
  AiLiveActivityStatus.pending => 'Queued',
  AiLiveActivityStatus.active => 'Running',
  AiLiveActivityStatus.completed => 'Done',
  AiLiveActivityStatus.warning => 'Needs check',
  AiLiveActivityStatus.failed => 'Failed',
};
