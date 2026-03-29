import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../config/theme.dart';
import '../../widgets/ai_logo.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _ambientController;
  int _currentPage = 0;

  final List<_ScenePage> _pages = const [
    _ScenePage(
      eyebrow: 'RESOURCE CLOUD',
      title: 'Everything your batch needs,\nactually organized.',
      description:
          'Notes, PYQs, videos, and revision material gathered into one shelf built around your branch and semester.',
      colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
      icon: Icons.auto_stories_rounded,
      tags: ['Notes', 'PYQs', 'Videos'],
      stat: '24/7 study shelf',
      badgeA: _SceneBadge('Notes', Icons.description_rounded, Offset(88, -84)),
      badgeB: _SceneBadge('Saved', Icons.bookmark_rounded, Offset(-84, 92)),
    ),
    _ScenePage(
      eyebrow: 'ROOMS',
      title: 'Ask once.\nPrepare together.',
      description:
          'Subject rooms keep doubts, quick reactions, and peer answers in one place so momentum stays inside the app.',
      colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
      icon: Icons.groups_rounded,
      tags: ['Rooms', 'Replies', 'Shared prep'],
      stat: 'Live peer momentum',
      badgeA: _SceneBadge('Doubt', Icons.chat_bubble_rounded, Offset(-88, -84)),
      badgeB: _SceneBadge('Fast', Icons.bolt_rounded, Offset(88, 92)),
    ),
    _ScenePage(
      eyebrow: 'CAMPUS SIGNAL',
      title: 'Notice, schedule,\nand attendance without noise.',
      description:
          'Important updates, live class context, and timetable cues stay visible right where students already spend time.',
      colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
      icon: Icons.campaign_rounded,
      tags: ['Notices', 'Schedule', 'Attendance'],
      stat: 'Real-time campus flow',
      badgeA: _SceneBadge(
        'Notice',
        Icons.notifications_active_rounded,
        Offset(88, -84),
      ),
      badgeB: _SceneBadge(
        'Today',
        Icons.calendar_today_rounded,
        Offset(-84, 92),
      ),
    ),
    _ScenePage(
      eyebrow: 'AI STUDIO',
      title: 'Turn dense notes into\nclarity you can revise.',
      description:
          'Grounded chat, OCR-backed answers, flashcards, quizzes, and summaries that stay tied to your actual material.',
      colors: [Color(0xFF2563EB), Color(0xFF111827)],
      icon: Icons.auto_awesome_rounded,
      tags: ['Summary', 'Quiz', 'Cards'],
      stat: 'OCR + notes grounding',
      useBrandMark: true,
      badgeA: _SceneBadge('Summary', Icons.subject_rounded, Offset(-88, -84)),
      badgeB: _SceneBadge('Quiz', Icons.quiz_rounded, Offset(88, 92)),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage == _pages.length - 1) {
      widget.onComplete();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      body: AnimatedBuilder(
        animation: Listenable.merge([_pageController, _ambientController]),
        builder: (context, _) {
          final pageValue = _pageController.hasClients
              ? (_pageController.page ?? _currentPage.toDouble())
              : _currentPage.toDouble();
          final active = _pages[pageValue.round().clamp(0, _pages.length - 1)];
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isDark
                          ? const [Color(0xFF030712), Color(0xFF000000)]
                          : const [Color(0xFFF4F8FF), Color(0xFFEAF1FB)],
                    ),
                  ),
                ),
              ),
              _orb(-100, -70, null, 260, active.colors.first, isDark, 0.0),
              _orb(180, null, -110, 320, active.colors.last, isDark, 0.35),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                      child: Row(
                        children: [
                          _brandPill(isDark),
                          const Spacer(),
                          _glassButton('Skip', isDark, widget.onComplete),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _pages.length,
                        onPageChanged: (value) =>
                            setState(() => _currentPage = value),
                        itemBuilder: (context, index) => _buildScene(
                          _pages[index],
                          pageValue - index,
                          isDark,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 26),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(
                                '${_currentPage + 1}'.padLeft(2, '0'),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? AppTheme.darkTextPrimary
                                      : AppTheme.lightTextPrimary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '/ ${_pages.length}',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppTheme.darkTextMuted
                                      : AppTheme.lightTextMuted,
                                ),
                              ),
                              const Spacer(),
                              SmoothPageIndicator(
                                controller: _pageController,
                                count: _pages.length,
                                effect: WormEffect(
                                  activeDotColor: AppTheme.primary,
                                  dotColor: isDark
                                      ? Colors.white.withValues(alpha: 0.14)
                                      : AppTheme.primary.withValues(
                                          alpha: 0.16,
                                        ),
                                  dotHeight: 7,
                                  dotWidth: 7,
                                  spacing: 8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: ElevatedButton(
                              onPressed: _nextPage,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _currentPage == _pages.length - 1
                                        ? 'Enter StudyShare'
                                        : 'Continue',
                                    style: GoogleFonts.inter(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _currentPage == _pages.length - 1
                                ? 'Built for the pace of college.'
                                : 'Swipe to move between scenes.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScene(_ScenePage page, double delta, bool isDark) {
    final drift = delta * 18;
    final fade = (1 - delta.abs() * 0.35).clamp(0.0, 1.0);
    final wave = math.sin(
      (_ambientController.value + (delta * 0.08)) * math.pi * 2,
    );
    return Opacity(
      opacity: fade,
      child: Transform.translate(
        offset: Offset(drift, delta.abs() * 18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
          child: Column(
            children: [
              SizedBox(
                height: 370,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 244,
                      height: 244,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.08 : 0.14,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 212,
                      height: 212,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(54),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: page.colors,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: page.colors.first.withValues(alpha: 0.28),
                            blurRadius: 42,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 212,
                      height: 212,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(54),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                    page.useBrandMark
                        ? const AiLogo(size: 104, animate: true)
                        : Icon(page.icon, size: 88, color: Colors.white),
                    _badge(page, page.badgeA, wave, delta, isDark),
                    _badge(page, page.badgeB, -wave, delta, isDark),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 6,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.28)
                                  : Colors.white.withValues(alpha: 0.84),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : page.colors.first.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: page.colors.first.withValues(
                                      alpha: 0.16,
                                    ),
                                  ),
                                  child: Icon(
                                    page.useBrandMark
                                        ? Icons.auto_awesome
                                        : page.icon,
                                    size: 18,
                                    color: isDark
                                        ? Colors.white
                                        : page.colors.first,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    page.stat,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? AppTheme.darkTextPrimary
                                          : AppTheme.lightTextPrimary,
                                    ),
                                  ),
                                ),
                                _tag('Swipe', isDark),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _tag(page.eyebrow, isDark, dot: true),
              const SizedBox(height: 18),
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  letterSpacing: -1.1,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                page.description,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.55,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: page.tags
                    .map((value) => _tag(value, isDark))
                    .toList(),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(
    _ScenePage page,
    _SceneBadge badge,
    double wave,
    double delta,
    bool isDark,
  ) {
    return Transform.translate(
      offset: Offset(
        badge.offset.dx - (delta * 10),
        badge.offset.dy + (wave * 8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : page.colors.first.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: page.colors.first.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    badge.icon,
                    size: 16,
                    color: isDark ? Colors.white : page.colors.first,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  badge.label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandPill(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AiLogo(size: 16, animate: true),
          const SizedBox(width: 8),
          Text(
            'studyshare',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppTheme.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassButton(String label, bool isDark, VoidCallback onPressed) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            backgroundColor: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.76),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : AppTheme.primaryDark,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, bool isDark, {bool dot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.primary.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                color: AppTheme.primaryLight,
                shape: BoxShape.circle,
              ),
            ),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: dot ? 11 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: dot ? 1.1 : 0,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _orb(
    double? top,
    double? left,
    double? right,
    double size,
    Color color,
    bool isDark,
    double phase,
  ) {
    final wave = math.sin((_ambientController.value * math.pi * 2) + phase);
    return Positioned(
      top: top == null ? null : top + (wave * 18),
      left: left == null ? null : left + (wave * 12),
      right: right == null ? null : right - (wave * 12),
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: isDark ? 0.12 : 0.08),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isDark ? 0.28 : 0.16),
                blurRadius: size * 0.42,
                spreadRadius: size * 0.06,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenePage {
  final String eyebrow;
  final String title;
  final String description;
  final List<Color> colors;
  final IconData icon;
  final List<String> tags;
  final String stat;
  final bool useBrandMark;
  final _SceneBadge badgeA;
  final _SceneBadge badgeB;

  const _ScenePage({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.colors,
    required this.icon,
    required this.tags,
    required this.stat,
    required this.badgeA,
    required this.badgeB,
    this.useBrandMark = false,
  });
}

class _SceneBadge {
  final String label;
  final IconData icon;
  final Offset offset;

  const _SceneBadge(this.label, this.icon, this.offset);
}
