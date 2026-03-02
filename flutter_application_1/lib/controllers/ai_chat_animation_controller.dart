import 'package:flutter/material.dart';

/// Owns animation setup/teardown for AI chat screen UI transitions.
class AiChatAnimationControllerBundle {
  AiChatAnimationControllerBundle({
    required TickerProvider vsync,
    required int suggestionCount,
    required VoidCallback onEntrySplashComplete,
  }) {
    splashController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 1180),
    );

    iconScaleAnimation = CurvedAnimation(
      parent: splashController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
    );

    iconSlideCurveAnimation = CurvedAnimation(
      parent: splashController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
    );
    iconSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          iconSlideCurveAnimation,
        );

    splashTitleAnimation = CurvedAnimation(
      parent: splashController,
      curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
    );

    titleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(splashTitleAnimation);

    splashSubtitleAnimation = CurvedAnimation(
      parent: splashController,
      curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic),
    );

    subtitleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(splashSubtitleAnimation);

    suggestionsController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 860),
    );

    suggestionAnimations = List.generate(suggestionCount, (index) {
      return CurvedAnimation(
        parent: suggestionsController,
        curve: Interval(
          (index / suggestionCount) * 0.5,
          1.0,
          curve: Curves.easeOutBack,
        ),
      );
    });

    suggestionFadeAnimations = List.generate(suggestionCount, (index) {
      return CurvedAnimation(
        parent: suggestionsController,
        curve: Interval(
          (index / suggestionCount) * 0.5,
          1.0,
          curve: Curves.easeOut,
        ),
      );
    });

    entrySplashController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 1540),
    );

    entrySplashScaleCurved = CurvedAnimation(
      parent: entrySplashController,
      curve: const Interval(0.0, 0.58, curve: Curves.easeOutBack),
    );
    entrySplashScale = Tween<double>(begin: 0.84, end: 1.0).animate(
      entrySplashScaleCurved,
    );

    entrySplashFade = CurvedAnimation(
      parent: entrySplashController,
      curve: const Interval(0.0, 0.9, curve: Curves.easeOutCubic),
    );

    entrySplashController.forward().whenComplete(onEntrySplashComplete);
  }

  late final AnimationController splashController;
  late final CurvedAnimation iconScaleAnimation;
  late final CurvedAnimation iconSlideCurveAnimation;
  late final Animation<Offset> iconSlideAnimation;
  late final CurvedAnimation splashTitleAnimation;
  late final Animation<Offset> titleSlideAnimation;
  late final CurvedAnimation splashSubtitleAnimation;
  late final Animation<Offset> subtitleSlideAnimation;
  late final AnimationController suggestionsController;
  late final List<CurvedAnimation> suggestionAnimations;
  late final List<CurvedAnimation> suggestionFadeAnimations;
  late final AnimationController entrySplashController;
  late final CurvedAnimation entrySplashScaleCurved;
  late final Animation<double> entrySplashScale;
  late final CurvedAnimation entrySplashFade;

  void dispose() {
    iconScaleAnimation.dispose();
    iconSlideCurveAnimation.dispose();
    splashTitleAnimation.dispose();
    splashSubtitleAnimation.dispose();
    for (final animation in suggestionAnimations) {
      animation.dispose();
    }
    for (final animation in suggestionFadeAnimations) {
      animation.dispose();
    }
    entrySplashScaleCurved.dispose();
    entrySplashFade.dispose();
    splashController.dispose();
    suggestionsController.dispose();
    entrySplashController.dispose();
  }
}
