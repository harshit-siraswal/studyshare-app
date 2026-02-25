import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';

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
    this.autoDismissDelay = const Duration(milliseconds: 3200),
  });

  @override
  State<SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<SuccessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  Timer? _dismissTimer;
  late final _OverlayVisuals _visuals;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _visuals = _OverlayVisuals.forVariant(widget.variant);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 300),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
        reverseCurve: Curves.easeIn,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const ElasticOutCurve(0.8),
        reverseCurve: Curves.easeIn,
      ),
    );

    _controller.forward();

    _dismissTimer = Timer(widget.autoDismissDelay, _closeOverlay);
  }

  void _closeOverlay() {
    if (mounted && !_isDismissing) {
      _isDismissing = true;
      _dismissTimer?.cancel();
      _controller.reverse().then((_) {
        if (mounted) widget.onDismiss();
      });
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayTitle = widget.title ?? _visuals.title ?? 'Success';

    final slideAnimation = Tween<double>(
      begin: -100,
      end: mediaQuery.viewPadding.top + 12,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const ElasticOutCurve(0.8),
        reverseCurve: Curves.easeIn,
      ),
    );

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeOverlay();
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeOverlay,
                child: Container(color: Colors.transparent),
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Positioned(
                  top: slideAnimation.value,
                  child: Opacity(
                    opacity: _fadeAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: GestureDetector(
                        onTap: _closeOverlay,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            borderRadius: BorderRadius.circular(100),
                            boxShadow: [
                              BoxShadow(
                                color: _visuals.primary.withValues(alpha: 0.15),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: isDark ? Colors.white12 : Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _visuals.primary.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _visuals.icon,
                                  color: _visuals.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayTitle,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    if (widget.message.isNotEmpty)
                                      Text(
                                        widget.message,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              if (widget.badgeLabel != null) ...[
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _visuals.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    widget.badgeLabel!,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayVisuals {
  final Color primary;
  final IconData icon;
  final String? title;

  const _OverlayVisuals({
    required this.primary,
    required this.icon,
    required this.title,
  });

  factory _OverlayVisuals.forVariant(SuccessOverlayVariant variant) {
    switch (variant) {
      case SuccessOverlayVariant.contribution:
        return const _OverlayVisuals(
          primary: Color(0xFF10B981),
          icon: Icons.volunteer_activism_rounded,
          title: 'Contribution Added',
        );
      case SuccessOverlayVariant.premiumUpgrade:
        return const _OverlayVisuals(
          primary: Color(0xFFF59E0B),
          icon: Icons.workspace_premium_rounded,
          title: 'Premium Activated',
        );
      case SuccessOverlayVariant.badgeUnlocked:
        return const _OverlayVisuals(
          primary: Color(0xFF8B5CF6),
          icon: Icons.emoji_events_rounded,
          title: 'Badge Unlocked',
        );
      case SuccessOverlayVariant.stickerImport:
        return const _OverlayVisuals(
          primary: Color(0xFF3B82F6),
          icon: Icons.emoji_emotions_rounded,
          title: 'Stickers Added',
        );
      case SuccessOverlayVariant.general:
        return const _OverlayVisuals(
          primary: AppTheme.success,
          icon: Icons.check_circle_rounded,
          title: null,
        );
    }
  }
}
