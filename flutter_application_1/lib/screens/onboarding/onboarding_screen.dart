import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../config/theme.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _motionController;
  int _currentPage = 0;

  final List<_ShowcasePage> _pages = const [
    _ShowcasePage(
      eyebrow: 'RESOURCES',
      title: 'Find the right notes, videos, and PYQs without hunting around.',
      description:
          'Search, filter, and skim the real resource feed built around your branch and semester.',
      assetPath: 'assets/images/mobile-showcase/feed.png',
      accent: Color(0xFF2563EB),
      badges: ['Search fast', 'Relevant feed', 'Save for later'],
      statLabel: 'Resource flow',
      statValue: 'For You + filters',
      motionOffset: 0.04,
    ),
    _ShowcasePage(
      eyebrow: 'PROFILE + AI',
      title:
          'Track contributions, premium access, and AI credits in one place.',
      description:
          'Your profile keeps uploads, badges, and monthly AI usage visible without jumping between screens.',
      assetPath: 'assets/images/mobile-showcase/profile.png',
      accent: Color(0xFFF59E0B),
      badges: ['Contribution badge', 'Credit balance', 'Premium status'],
      statLabel: 'Personal control',
      statValue: 'Profile + credits',
      motionOffset: 0.32,
    ),
    _ShowcasePage(
      eyebrow: 'SYLLABUS',
      title:
          'Move from the syllabus to the exact study material with less noise.',
      description:
          'Browse department structure first, then step into the right subject context before you start revising.',
      assetPath: 'assets/images/mobile-showcase/syllabus.png',
      accent: Color(0xFF14B8A6),
      badges: ['Department view', 'Semester context', 'Faster navigation'],
      statLabel: 'Structured start',
      statValue: 'Department-first browsing',
      motionOffset: 0.61,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _motionController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage == _pages.length - 1) {
      widget.onComplete();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 360),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF020617), Color(0xFF000000)]
                : const [Color(0xFFF8FBFF), Color(0xFFEFF4FB)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    _brandPill(isDark),
                    const Spacer(),
                    TextButton(
                      onPressed: widget.onComplete,
                      child: Text(
                        'Skip',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (value) =>
                      setState(() => _currentPage = value),
                  itemBuilder: (context, index) {
                    return AnimatedBuilder(
                      animation: Listenable.merge([
                        _pageController,
                        _motionController,
                      ]),
                      builder: (context, _) {
                        final pageValue = _pageController.hasClients
                            ? (_pageController.page ?? _currentPage.toDouble())
                            : _currentPage.toDouble();
                        return _buildPage(
                          _pages[index],
                          pageValue - index,
                          isDark,
                        );
                      },
                    );
                  },
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
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '/ ${_pages.length}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white54
                                : const Color(0xFF64748B),
                          ),
                        ),
                        const Spacer(),
                        SmoothPageIndicator(
                          controller: _pageController,
                          count: _pages.length,
                          effect: WormEffect(
                            activeDotColor: AppTheme.primary,
                            dotColor: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : AppTheme.primary.withValues(alpha: 0.16),
                            dotHeight: 7,
                            dotWidth: 7,
                            spacing: 8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        onPressed: _nextPage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _currentPage == _pages.length - 1
                                  ? 'Enter StudyShare'
                                  : 'Continue',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Swipe to inspect real app screens.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(_ShowcasePage page, double delta, bool isDark) {
    final opacity = (1 - delta.abs() * 0.35).clamp(0.0, 1.0);
    final xOffset = delta * 24;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(xOffset, 0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Column(
            children: [
              Expanded(child: _buildShowcasePhone(page, isDark)),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: _eyebrowChip(page.eyebrow, page.accent, isDark),
              ),
              const SizedBox(height: 14),
              Text(
                page.title,
                style: GoogleFonts.inter(
                  fontSize: 31,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                page.description,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: page.badges
                    .map(
                      (badge) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShowcasePhone(_ShowcasePage page, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 360.0);
        final phoneWidth = math.max(250.0, width * 0.82);
        final phoneHeight = phoneWidth * 2.0;
        final oscillation =
            (math.sin(
                  (_motionController.value + page.motionOffset) * math.pi * 2,
                ) +
                1) /
            2;
        final eased = Curves.easeInOut.transform(oscillation);
        final imageOffset = -52.0 * eased;

        return Center(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 26,
                child: Container(
                  width: phoneWidth * 0.9,
                  height: phoneHeight * 0.92,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(42),
                    boxShadow: [
                      BoxShadow(
                        color: page.accent.withValues(
                          alpha: isDark ? 0.28 : 0.18,
                        ),
                        blurRadius: 42,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: phoneWidth,
                height: phoneHeight,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF06080D),
                  borderRadius: BorderRadius.circular(38),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Transform.translate(
                          offset: Offset(0, imageOffset),
                          child: Image.asset(
                            page.assetPath,
                            width: phoneWidth * 1.06,
                            fit: BoxFit.fitWidth,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.swipe_up_alt_rounded,
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.82),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Live scroll',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withValues(
                                        alpha: 0.92,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 52,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                bottom: 28,
                child: _floatingInfoCard(
                  label: page.statLabel,
                  value: page.statValue,
                  accent: page.accent,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _floatingInfoCard({
    required String label,
    required String value,
    required Color accent,
    required bool isDark,
  }) {
    return Container(
      width: 170,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF111827).withValues(alpha: 0.94)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandPill(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 12,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'StudyShare',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eyebrowChip(String text, Color accent, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
  }
}

class _ShowcasePage {
  final String eyebrow;
  final String title;
  final String description;
  final String assetPath;
  final Color accent;
  final List<String> badges;
  final String statLabel;
  final String statValue;
  final double motionOffset;

  const _ShowcasePage({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.assetPath,
    required this.accent,
    required this.badges,
    required this.statLabel,
    required this.statValue,
    required this.motionOffset,
  });
}
