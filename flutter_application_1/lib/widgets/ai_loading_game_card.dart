import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/theme.dart';

class AiLoadingGameCard extends StatefulWidget {
  const AiLoadingGameCard({
    super.key,
    required this.loadingMessage,
    this.compact = false,
    this.headline = 'Beat the high score while AI works',
    this.subheadline = 'Quick arcade games keep the wait useful.',
  });

  final String loadingMessage;
  final bool compact;
  final String headline;
  final String subheadline;

  @override
  State<AiLoadingGameCard> createState() => _AiLoadingGameCardState();
}

class _AiLoadingGameCardState extends State<AiLoadingGameCard> {
  static const _tapRushPrefsKey = 'ai_loading_game_tap_rush_high_score';
  static const _signalPrefsKey = 'ai_loading_game_signal_match_high_score';

  final math.Random _random = math.Random();
  Timer? _tapRushTimer;
  Timer? _signalTimer;

  int _selectedGameIndex = 0;

  int _tapRushTargetIndex = 4;
  int _tapRushScore = 0;
  int _tapRushHighScore = 0;
  int _tapRushStreak = 0;

  int _signalTargetIndex = 0;
  int _signalMatchScore = 0;
  int _signalMatchHighScore = 0;
  int _signalMatchStreak = 0;

  static const _signalColors = <Color>[
    Color(0xFF38BDF8),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFFA855F7),
  ];

  static const _signalLabels = <String>['Sky', 'Ember', 'Mint', 'Pulse'];

  @override
  void initState() {
    super.initState();
    _loadHighScores();
    _startTapRushTicker();
    _startSignalTicker();
  }

  @override
  void dispose() {
    _tapRushTimer?.cancel();
    _signalTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHighScores() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _tapRushHighScore = prefs.getInt(_tapRushPrefsKey) ?? 0;
      _signalMatchHighScore = prefs.getInt(_signalPrefsKey) ?? 0;
    });
  }

  Future<void> _storeHighScore(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  void _startTapRushTicker() {
    _tapRushTimer?.cancel();
    _tapRushTimer = Timer.periodic(const Duration(milliseconds: 820), (_) {
      if (!mounted) return;
      setState(() {
        final next = _random.nextInt(9);
        _tapRushTargetIndex = next == _tapRushTargetIndex
            ? (next + 1) % 9
            : next;
      });
    });
  }

  void _startSignalTicker() {
    _signalTimer?.cancel();
    _signalTimer = Timer.periodic(const Duration(milliseconds: 1700), (_) {
      if (!mounted) return;
      setState(() {
        final next = _random.nextInt(_signalColors.length);
        _signalTargetIndex = next == _signalTargetIndex
            ? (next + 1) % _signalColors.length
            : next;
      });
    });
  }

  void _updateTapRushHighScore() {
    if (_tapRushScore <= _tapRushHighScore) return;
    setState(() => _tapRushHighScore = _tapRushScore);
    unawaited(_storeHighScore(_tapRushPrefsKey, _tapRushScore));
  }

  void _updateSignalMatchHighScore() {
    if (_signalMatchScore <= _signalMatchHighScore) return;
    setState(() => _signalMatchHighScore = _signalMatchScore);
    unawaited(_storeHighScore(_signalPrefsKey, _signalMatchScore));
  }

  void _handleTapRushTileTap(int index) {
    if (!mounted) return;
    setState(() {
      if (index == _tapRushTargetIndex) {
        _tapRushScore += 1;
        _tapRushStreak += 1;
        _tapRushTargetIndex = _random.nextInt(9);
      } else {
        _tapRushScore = math.max(0, _tapRushScore - 1);
        _tapRushStreak = 0;
      }
    });
    _updateTapRushHighScore();
  }

  void _handleSignalMatchTap(int index) {
    if (!mounted) return;
    setState(() {
      if (index == _signalTargetIndex) {
        _signalMatchScore += 1;
        _signalMatchStreak += 1;
        _signalTargetIndex = _random.nextInt(_signalColors.length);
      } else {
        _signalMatchScore = math.max(0, _signalMatchScore - 1);
        _signalMatchStreak = 0;
      }
    });
    _updateSignalMatchHighScore();
  }

  Widget _buildScorePill({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameSwitch({
    required int index,
    required String label,
    required bool isDark,
  }) {
    final selected = _selectedGameIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedGameIndex = index),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected
                ? null
                : (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.78)),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05)),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.26),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.white
                    : (isDark ? Colors.white70 : const Color(0xFF334155)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTapRushGame(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildScorePill(
                label: 'Score',
                value: '$_tapRushScore',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildScorePill(
                label: 'High score',
                value: '$_tapRushHighScore',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildScorePill(
                label: 'Streak',
                value: '$_tapRushStreak',
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Tap the glowing orb before it jumps.',
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 9,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final isTarget = index == _tapRushTargetIndex;
            return InkWell(
              onTap: () => _handleTapRushTileTap(index),
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: isTarget
                        ? const [Color(0xFF38BDF8), Color(0xFF7C3AED)]
                        : (isDark
                              ? const [Color(0xFF111827), Color(0xFF1E293B)]
                              : const [Color(0xFFFFFFFF), Color(0xFFE2E8F0)]),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: isTarget
                        ? Colors.white.withValues(alpha: 0.42)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.05)),
                  ),
                  boxShadow: [
                    if (isTarget)
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                        blurRadius: 22,
                        spreadRadius: 1,
                        offset: const Offset(0, 12),
                      ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isTarget
                          ? Colors.white.withValues(alpha: 0.18)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06)),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: isTarget
                          ? Colors.white
                          : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSignalMatchGame(bool isDark) {
    final targetColor = _signalColors[_signalTargetIndex];
    final targetLabel = _signalLabels[_signalTargetIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildScorePill(
                label: 'Score',
                value: '$_signalMatchScore',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildScorePill(
                label: 'High score',
                value: '$_signalMatchHighScore',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildScorePill(
                label: 'Streak',
                value: '$_signalMatchStreak',
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                targetColor.withValues(alpha: 0.24),
                targetColor.withValues(alpha: 0.10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: targetColor.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: targetColor,
                  boxShadow: [
                    BoxShadow(
                      color: targetColor.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signal target',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap $targetLabel',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(_signalColors.length, (index) {
            final color = _signalColors[index];
            final label = _signalLabels[index];
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == _signalColors.length - 1 ? 0 : 10,
                ),
                child: InkWell(
                  onTap: () => _handleSignalMatchTap(index),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.95),
                          color.withValues(alpha: 0.72),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.28),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FBFF);
    final overlay = isDark ? const Color(0xFF111827) : Colors.white;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: widget.compact ? 520 : 680),
      padding: EdgeInsets.all(widget.compact ? 16 : 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.22),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(widget.compact ? 14 : 16),
        decoration: BoxDecoration(
          color: overlay.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF22D3EE), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.sports_esports_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.headline,
                        style: GoogleFonts.inter(
                          fontSize: widget.compact ? 15 : 16,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subheadline,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.loadingMessage,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildGameSwitch(index: 0, label: 'Orb Rush', isDark: isDark),
                const SizedBox(width: 10),
                _buildGameSwitch(
                  index: 1,
                  label: 'Signal Match',
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: Container(
                key: ValueKey<int>(_selectedGameIndex),
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: _selectedGameIndex == 0
                    ? _buildTapRushGame(isDark)
                    : _buildSignalMatchGame(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
