import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders the StudyShare AI logo mark without background.
class AiLogoMark extends StatelessWidget {
  final double size;
  final bool useSvg;

  const AiLogoMark({
    super.key,
    this.size = 36,
    this.useSvg = false,
  });

  @override
  Widget build(BuildContext context) {
    if (useSvg) {
      return SvgPicture.asset(
        'assets/images/ai_logo_mark.svg',
        width: size,
        height: size,
      );
    }

    return Image.asset(
      'assets/images/ai_logo_mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// Subtle animated logo for AI moments (loading, welcome, etc.).
class AiLogoSpinner extends StatefulWidget {
  final double size;
  final Duration duration;

  const AiLogoSpinner({
    super.key,
    this.size = 40,
    this.duration = const Duration(seconds: 6),
  });

  @override
  State<AiLogoSpinner> createState() => _AiLogoSpinnerState();
}

class _AiLogoSpinnerState extends State<AiLogoSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: AiLogoMark(size: widget.size, useSvg: true),
    );
  }
}
