import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../l10n/app_localizations.dart';

enum SuccessOverlayVariant {
  general,
  contribution,
  badgeUnlocked,
  premiumUpgrade,
  stickerImport,
}

class SuccessOverlay extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  final SuccessOverlayVariant variant;
  final String? title;
  final String? badgeLabel;
  final Duration autoDismissDelay;

  const SuccessOverlay({
    super.key,
    required this.message,
    required this.onDismiss,
    this.variant = SuccessOverlayVariant.general,
    this.title,
    this.badgeLabel,
    this.autoDismissDelay = const Duration(milliseconds: 2400),
  });

  @override
  State<SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<SuccessOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _particleController;
  late final AnimationController _pulseController;
  late final _OverlayVisuals _visuals;
  late final List<_Particle> _particles;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _visuals = _OverlayVisuals.forVariant(widget.variant);
    _particles = List.generate(24, (_) {
      return _Particle(
        angle: _random.nextDouble() * 2 * pi,
        speed: 80 + _random.nextDouble() * 160,
        size: 4 + _random.nextDouble() * 8,
        color: _visuals
            .particlePalette[_random.nextInt(_visuals.particlePalette.length)],
      );
    });

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    )..forward();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    Future.delayed(widget.autoDismissDelay, () {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _particleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final successLabel = AppLocalizations.of(context)!.success;
    final title = widget.title ?? _visuals.title ?? successLabel;

    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _entryController,
          _particleController,
          _pulseController,
        ]),
        builder: (context, child) {
          final entry = Curves.easeOutCubic.transform(_entryController.value);
          final burst = Curves.easeOut.transform(_particleController.value);
          final cardScale = Tween<double>(
            begin: 0.82,
            end: 1.0,
          ).transform(entry);
          final pulseScale = Tween<double>(
            begin: 0.9,
            end: 1.2,
          ).transform(_pulseController.value);

          return Container(
            color: Colors.black.withValues(alpha: 0.56 * entry),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ..._particles.map((particle) {
                  final x = cos(particle.angle) * particle.speed * burst;
                  final y =
                      sin(particle.angle) * particle.speed * burst -
                      (48 * burst * burst);

                  return Positioned(
                    left: (MediaQuery.of(context).size.width / 2) + x,
                    top: (MediaQuery.of(context).size.height / 2) + y - 32,
                    child: Opacity(
                      opacity: (1 - burst).clamp(0.0, 1.0),
                      child: Container(
                        width: particle.size,
                        height: particle.size,
                        decoration: BoxDecoration(
                          color: particle.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  );
                }),
                Transform.scale(
                  scale: cardScale,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 30),
                    padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _visuals.primary.withValues(alpha: 0.28),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      label: '$title ${widget.message}',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.scale(
                                scale: pulseScale,
                                child: Container(
                                  width: 88,
                                  height: 88,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _visuals.primary.withValues(
                                        alpha: 0.22,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 82,
                                height: 82,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      _visuals.primary,
                                      _visuals.secondary,
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _visuals.icon,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.message,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              height: 1.45,
                              color: isDark
                                  ? AppTheme.textMuted
                                  : const Color(0xFF64748B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (widget.badgeLabel != null &&
                              widget.badgeLabel!.trim().isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _visuals.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _visuals.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Text(
                                widget.badgeLabel!,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _visuals.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;

  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
  });
}

class _OverlayVisuals {
  final Color primary;
  final Color secondary;
  final IconData icon;
  final String? title;
  final List<Color> particlePalette;

  const _OverlayVisuals({
    required this.primary,
    required this.secondary,
    required this.icon,
    required this.title,
    required this.particlePalette,
  });

  factory _OverlayVisuals.forVariant(SuccessOverlayVariant variant) {
    switch (variant) {
      case SuccessOverlayVariant.contribution:
        return const _OverlayVisuals(
          primary: Color(0xFF059669),
          secondary: Color(0xFF10B981),
          icon: Icons.volunteer_activism_rounded,
          title: 'Contribution Added',
          particlePalette: [
            Color(0xFF059669),
            Color(0xFF10B981),
            Color(0xFF34D399),
            Color(0xFF6EE7B7),
          ],
        );
      case SuccessOverlayVariant.premiumUpgrade:
        return const _OverlayVisuals(
          primary: Color(0xFFF59E0B),
          secondary: Color(0xFFF97316),
          icon: Icons.workspace_premium_rounded,
          title: 'Pro Activated',
          particlePalette: [
            Color(0xFFF59E0B),
            Color(0xFFF97316),
            Color(0xFFFBBF24),
            Color(0xFFFDE68A),
          ],
        );
      case SuccessOverlayVariant.badgeUnlocked:
        return const _OverlayVisuals(
          primary: Color(0xFF7C3AED),
          secondary: Color(0xFFA855F7),
          icon: Icons.emoji_events_rounded,
          title: 'Badge Unlocked',
          particlePalette: [
            Color(0xFF7C3AED),
            Color(0xFFA855F7),
            Color(0xFFC084FC),
            Color(0xFFE9D5FF),
          ],
        );
      case SuccessOverlayVariant.stickerImport:
        return const _OverlayVisuals(
          primary: Color(0xFF2563EB),
          secondary: Color(0xFF3B82F6),
          icon: Icons.emoji_emotions_rounded,
          title: 'Stickers Installed',
          particlePalette: [
            Color(0xFF2563EB),
            Color(0xFF3B82F6),
            Color(0xFF60A5FA),
            Color(0xFF93C5FD),
          ],
        );
      case SuccessOverlayVariant.general:
        return const _OverlayVisuals(
          primary: AppTheme.success,
          secondary: Color(0xFF22C55E),
          icon: Icons.check_rounded,
          title: null,
          particlePalette: [
            AppTheme.success,
            Color(0xFF22C55E),
            Color(0xFF34D399),
            Color(0xFF6EE7B7),
          ],
        );
    }
  }
}
