import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Global key to wrap the entire app's scaffold/body to take a screenshot.
final GlobalKey appBoundaryKey = GlobalKey();

/// Utility to trigger a Telegram-style circular reveal theme transition.
Future<void> animateThemeTransition(
  BuildContext context,
  Offset tapOffset,
  VoidCallback toggleTheme,
) async {
  // Capture current screen
  final boundary = appBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    toggleTheme();
    return;
  }

  var pixelRatio = 1.0;
  try {
    pixelRatio = MediaQuery.of(context).devicePixelRatio;
  } catch (_) {
    try {
      pixelRatio = View.of(context).devicePixelRatio;
    } catch (_) {
      pixelRatio = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    }
  }

  ui.Image? image;
  try {
    image = await boundary.toImage(pixelRatio: pixelRatio);
  } catch (e) {
    // If it fails, fallback to standard toggle
    toggleTheme();
    return;
  }

  final overlayState = Overlay.of(context);
  if (overlayState == null) {
    toggleTheme();
    return;
  }

  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) {
      return _CircularRevealAnimation(
        image: image!,
        tapOffset: tapOffset,
        onEnd: () {
          overlayEntry.remove();
        },
      );
    },
  );

  overlayState.insert(overlayEntry);
  
  // Actually update the theme underneath
  toggleTheme();
}

class _CircularRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Offset center;
  
  _CircularRevealClipper({required this.fraction, required this.center});

  @override
  Path getClip(Size size) {
    final path = Path();
    // Calculate max radius needed to cover the screen from the center point
    final radius = size.longestSide * 1.5 * fraction;
    path.addOval(Rect.fromCircle(center: center, radius: radius));
    return path;
  }

  @override
  bool shouldReclip(_CircularRevealClipper oldClipper) {
    return fraction != oldClipper.fraction || center != oldClipper.center;
  }
}

class _CircularRevealAnimation extends StatefulWidget {
  final ui.Image image;
  final Offset tapOffset;
  final VoidCallback onEnd;

  const _CircularRevealAnimation({
    super.key,
    required this.image,
    required this.tapOffset,
    required this.onEnd,
  });

  @override
  State<_CircularRevealAnimation> createState() => _CircularRevealAnimationState();
}

class _CircularRevealAnimationState extends State<_CircularRevealAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
    _controller.forward().then((_) {
      if (mounted) widget.onEnd();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    widget.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return ClipPath(
          clipper: _CircularRevealClipper(
            fraction: 1.0 - _animation.value,
            center: widget.tapOffset,
          ),
          child: SizedBox.expand(
            child: RawImage(
              image: widget.image,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}
