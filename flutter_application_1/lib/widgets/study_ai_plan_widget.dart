import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/study_ai_plan.dart';

class StudyAIPlanWidget extends StatelessWidget {
  const StudyAIPlanWidget({
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
  final AnswerOrigin? answerOrigin;
  final List<PlanStep> steps;
  final bool isRunning;
  final bool showExport;
  final void Function(String fileId, int? page)? onOpenPdf;
  final void Function(String url)? onOpenUrl;
  final void Function(String url, String? timestamp)? onOpenVideo;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    final completed = steps
        .where((step) => step.status == StepStatus.completed)
        .length;
    final total = steps.isEmpty ? 1 : steps.length;
    final progress = completed / total;
    final banner = _BannerStyle.fromOrigin(answerOrigin, isDark);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1016) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                if (isRunning) ...[
                  _WorkingPill(
                    isDark: isDark,
                    disableAnimations: disableAnimations,
                  ),
                ],
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(1),
            ),
            child: LinearProgressIndicator(
              minHeight: 2,
              value: progress.clamp(0, 1),
              backgroundColor: isDark
                  ? Colors.white10
                  : const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF10B981),
              ),
            ),
          ),
          if (banner != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: BoxDecoration(
                color: banner.background,
                border: Border(bottom: BorderSide(color: banner.border)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: banner.foreground,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      banner.label,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: banner.foreground,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              children: [
                for (var index = 0; index < steps.length; index++)
                  _PlanStepTile(
                    key: ValueKey<String>(steps[index].id),
                    step: steps[index],
                    isDark: isDark,
                    disableAnimations: disableAnimations,
                    onOpenPdf: onOpenPdf,
                    onOpenUrl: onOpenUrl,
                    onOpenVideo: onOpenVideo,
                  ),
              ],
            ),
          ),
          if (showExport && onExport != null)
            AnimatedOpacity(
              opacity: 1,
              duration: Duration(milliseconds: disableAnimations ? 0 : 300),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: FilledButton.icon(
                  onPressed: onExport,
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white
                        : const Color(0xFF111827),
                    foregroundColor: isDark
                        ? const Color(0xFF111827)
                        : Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    'Download question paper PDF',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanStepTile extends StatefulWidget {
  const _PlanStepTile({
    super.key,
    required this.step,
    required this.isDark,
    required this.disableAnimations,
    this.onOpenPdf,
    this.onOpenUrl,
    this.onOpenVideo,
  });

  final PlanStep step;
  final bool isDark;
  final bool disableAnimations;
  final void Function(String fileId, int? page)? onOpenPdf;
  final void Function(String url)? onOpenUrl;
  final void Function(String url, String? timestamp)? onOpenVideo;

  @override
  State<_PlanStepTile> createState() => _PlanStepTileState();
}

class _PlanStepTileState extends State<_PlanStepTile>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.step.status == StepStatus.inProgress;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _PlanStepTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.status == StepStatus.inProgress &&
        oldWidget.step.status != StepStatus.inProgress &&
        widget.step.hasDetails) {
      _isExpanded = true;
    }
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.disableAnimations) {
      _pulseController.stop();
      return;
    }
    if (widget.step.status == StepStatus.inProgress) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryColor = widget.isDark
        ? AppTheme.darkTextSecondary
        : const Color(0xFF475569);
    final hasExpandableBody =
        widget.step.substeps.isNotEmpty || widget.step.sources.isNotEmpty;

    return AnimatedSize(
      duration: Duration(milliseconds: widget.disableAnimations ? 0 : 250),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: widget.isDark
              ? Colors.white.withValues(alpha: 0.02)
              : Colors.black.withValues(alpha: 0.015),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: hasExpandableBody
                  ? () => setState(() => _isExpanded = !_isExpanded)
                  : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Row(
                  children: [
                    AnimatedSwitcher(
                      duration: Duration(
                        milliseconds: widget.disableAnimations ? 0 : 200,
                      ),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        );
                      },
                      child: _buildStatusIcon(widget.step.status),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.step.title,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                              height: 1.2,
                              decoration:
                                  widget.step.status == StepStatus.completed
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              decorationColor: secondaryColor.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          if (widget.step.description?.trim().isNotEmpty ==
                                  true &&
                              (!_isExpanded || widget.step.substeps.isEmpty))
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                widget.step.description!.trim(),
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: secondaryColor,
                                  height: 1.35,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.step.status == StepStatus.inProgress)
                      FadeTransition(
                        opacity: _pulseController,
                        child: Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF38BDF8),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    if (hasExpandableBody)
                      AnimatedRotation(
                        turns: _isExpanded ? 0.25 : 0,
                        duration: Duration(
                          milliseconds: widget.disableAnimations ? 0 : 180,
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: secondaryColor,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.step.substeps.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(left: 5, bottom: 6),
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: widget.isDark
                                  ? Colors.white12
                                  : const Color(0xFFD8E0EB),
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            for (final substep in widget.step.substeps)
                              _PlanSubstepTile(
                                substep: substep,
                                isDark: widget.isDark,
                                disableAnimations: widget.disableAnimations,
                                onOpenPdf: widget.onOpenPdf,
                                onOpenUrl: widget.onOpenUrl,
                                onOpenVideo: widget.onOpenVideo,
                              ),
                          ],
                        ),
                      ),
                    if (widget.step.sources.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.step.sources
                              .map(
                                (source) => _SourceChip(
                                  source: source,
                                  onOpenPdf: widget.onOpenPdf,
                                  onOpenUrl: widget.onOpenUrl,
                                  onOpenVideo: widget.onOpenVideo,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(StepStatus status) {
    switch (status) {
      case StepStatus.completed:
        return const Icon(
          Icons.check_circle_rounded,
          key: ValueKey<String>('completed'),
          size: 18,
          color: Color(0xFF10B981),
        );
      case StepStatus.inProgress:
        return const Icon(
          Icons.timelapse_rounded,
          key: ValueKey<String>('in_progress'),
          size: 18,
          color: Color(0xFF38BDF8),
        );
      case StepStatus.needHelp:
        return const Icon(
          Icons.error_outline_rounded,
          key: ValueKey<String>('need_help'),
          size: 18,
          color: Color(0xFFF59E0B),
        );
      case StepStatus.failed:
        return const Icon(
          Icons.cancel_rounded,
          key: ValueKey<String>('failed'),
          size: 18,
          color: Color(0xFFEF4444),
        );
      case StepStatus.pending:
        return Icon(
          Icons.radio_button_unchecked_rounded,
          key: const ValueKey<String>('pending'),
          size: 18,
          color: widget.isDark ? Colors.white38 : const Color(0xFF94A3B8),
        );
    }
  }
}

class _PlanSubstepTile extends StatefulWidget {
  const _PlanSubstepTile({
    required this.substep,
    required this.isDark,
    required this.disableAnimations,
    this.onOpenPdf,
    this.onOpenUrl,
    this.onOpenVideo,
  });

  final PlanSubstep substep;
  final bool isDark;
  final bool disableAnimations;
  final void Function(String fileId, int? page)? onOpenPdf;
  final void Function(String url)? onOpenUrl;
  final void Function(String url, String? timestamp)? onOpenVideo;

  @override
  State<_PlanSubstepTile> createState() => _PlanSubstepTileState();
}

class _PlanSubstepTileState extends State<_PlanSubstepTile> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.substep.status == StepStatus.inProgress;
  }

  @override
  void didUpdateWidget(covariant _PlanSubstepTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.substep.status == StepStatus.inProgress &&
        oldWidget.substep.status != StepStatus.inProgress) {
      _isExpanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final muted = widget.isDark
        ? AppTheme.darkTextSecondary
        : const Color(0xFF64748B);
    final hasBody =
        (widget.substep.detail?.trim().isNotEmpty ?? false) ||
        widget.substep.sources.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: hasBody
              ? () => setState(() => _isExpanded = !_isExpanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: _buildSubstepIcon(widget.substep.status),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.substep.title,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      height: 1.3,
                    ),
                  ),
                ),
                if (hasBody)
                  AnimatedRotation(
                    turns: _isExpanded ? 0.25 : 0,
                    duration: Duration(
                      milliseconds: widget.disableAnimations ? 0 : 160,
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_isExpanded && hasBody)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.substep.detail?.trim().isNotEmpty == true)
                  Text(
                    widget.substep.detail!.trim(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                if (widget.substep.sources.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.substep.sources
                        .map(
                          (source) => _SourceChip(
                            source: source,
                            onOpenPdf: widget.onOpenPdf,
                            onOpenUrl: widget.onOpenUrl,
                            onOpenVideo: widget.onOpenVideo,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSubstepIcon(StepStatus status) {
    switch (status) {
      case StepStatus.completed:
        return const Icon(
          Icons.check_circle_rounded,
          size: 14,
          color: Color(0xFF10B981),
        );
      case StepStatus.inProgress:
        return const Icon(
          Icons.timelapse_rounded,
          size: 14,
          color: Color(0xFF38BDF8),
        );
      case StepStatus.needHelp:
        return const Icon(
          Icons.error_outline_rounded,
          size: 14,
          color: Color(0xFFF59E0B),
        );
      case StepStatus.failed:
        return const Icon(
          Icons.cancel_rounded,
          size: 14,
          color: Color(0xFFEF4444),
        );
      case StepStatus.pending:
        return Icon(
          Icons.radio_button_unchecked_rounded,
          size: 14,
          color: widget.isDark ? Colors.white38 : const Color(0xFF94A3B8),
        );
    }
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.source,
    this.onOpenPdf,
    this.onOpenUrl,
    this.onOpenVideo,
  });

  final PlanSource source;
  final void Function(String fileId, int? page)? onOpenPdf;
  final void Function(String url)? onOpenUrl;
  final void Function(String url, String? timestamp)? onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final style = _SourceStyle.fromBadge(source.badge);
    final label = switch (source.badge) {
      SourceBadge.notes =>
        source.page != null
            ? '${source.title}  p.${source.page}'
            : source.title,
      SourceBadge.video =>
        source.timestamp?.trim().isNotEmpty == true
            ? '${source.title}  ${source.timestamp}'
            : source.title,
      SourceBadge.web => source.title,
    };

    return Material(
      color: style.background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: !source.isClickable
            ? null
            : () {
                if (source.badge == SourceBadge.notes &&
                    source.fileId != null &&
                    onOpenPdf != null) {
                  onOpenPdf!(source.fileId!, source.page);
                } else if (source.badge == SourceBadge.web &&
                    source.url != null &&
                    onOpenUrl != null) {
                  onOpenUrl!(source.url!);
                } else if (source.badge == SourceBadge.video &&
                    source.url != null &&
                    onOpenVideo != null) {
                  onOpenVideo!(source.url!, source.timestamp);
                }
              },
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: style.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: 13, color: style.foreground),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 210),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: style.foreground,
                    height: 1.1,
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

class _WorkingPill extends StatelessWidget {
  const _WorkingPill({required this.isDark, required this.disableAnimations});

  final bool isDark;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.35, end: 1),
            duration: Duration(milliseconds: disableAnimations ? 0 : 900),
            curve: Curves.easeInOut,
            onEnd: () {},
            builder: (context, value, child) {
              return AnimatedOpacity(
                opacity: disableAnimations ? 1 : value,
                duration: Duration(milliseconds: disableAnimations ? 0 : 450),
                child: child,
              );
            },
            child: const Icon(Icons.circle, size: 7, color: Color(0xFF38BDF8)),
          ),
          const SizedBox(width: 6),
          Text(
            'Working',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceStyle {
  const _SourceStyle({
    required this.background,
    required this.foreground,
    required this.border,
    required this.icon,
  });

  final Color background;
  final Color foreground;
  final Color border;
  final IconData icon;

  factory _SourceStyle.fromBadge(SourceBadge badge) {
    return switch (badge) {
      SourceBadge.notes => const _SourceStyle(
        background: Color(0xFFD1FAE5),
        foreground: Color(0xFF065F46),
        border: Color(0xFFA7F3D0),
        icon: Icons.menu_book_rounded,
      ),
      SourceBadge.web => const _SourceStyle(
        background: Color(0xFFDBEAFE),
        foreground: Color(0xFF1E40AF),
        border: Color(0xFFBFDBFE),
        icon: Icons.public_rounded,
      ),
      SourceBadge.video => const _SourceStyle(
        background: Color(0xFFFEF3C7),
        foreground: Color(0xFF92400E),
        border: Color(0xFFFDE68A),
        icon: Icons.smart_display_rounded,
      ),
    };
  }
}

class _BannerStyle {
  const _BannerStyle({
    required this.label,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color border;

  static _BannerStyle? fromOrigin(AnswerOrigin? origin, bool isDark) {
    switch (origin) {
      case AnswerOrigin.notesOnly:
        return _BannerStyle(
          label: 'Answered from your uploaded notes',
          background: isDark
              ? const Color(0x1F10B981)
              : const Color(0xFFE8FFF5),
          foreground: isDark
              ? const Color(0xFF9AE6B4)
              : const Color(0xFF065F46),
          border: isDark ? const Color(0x5534D399) : const Color(0xFFD1FAE5),
        );
      case AnswerOrigin.notesPlusWeb:
        return _BannerStyle(
          label: 'Answered from your notes + web',
          background: isDark
              ? const Color(0x1F3B82F6)
              : const Color(0xFFEDF5FF),
          foreground: isDark
              ? const Color(0xFF93C5FD)
              : const Color(0xFF1E40AF),
          border: isDark ? const Color(0x554F9CF9) : const Color(0xFFDBEAFE),
        );
      case AnswerOrigin.webOnly:
        return _BannerStyle(
          label: 'Answered from the web',
          background: isDark
              ? const Color(0x1F3B82F6)
              : const Color(0xFFEDF5FF),
          foreground: isDark
              ? const Color(0xFF93C5FD)
              : const Color(0xFF1E40AF),
          border: isDark ? const Color(0x554F9CF9) : const Color(0xFFDBEAFE),
        );
      case AnswerOrigin.insufficientNotes:
        return _BannerStyle(
          label: 'Not enough detail found in your notes',
          background: isDark
              ? const Color(0x1FF59E0B)
              : const Color(0xFFFFF8E5),
          foreground: isDark
              ? const Color(0xFFFCD34D)
              : const Color(0xFF92400E),
          border: isDark ? const Color(0x55FBBF24) : const Color(0xFFFEF3C7),
        );
      case null:
        return null;
    }
  }
}
