import 'package:flutter/material.dart';

import '../config/theme.dart';

class UserMessageBubble extends StatelessWidget {
  const UserMessageBubble({
    super.key,
    required this.isDark,
    required this.horizontalInset,
    required this.padding,
    required this.child,
  });

  final bool isDark;
  final double horizontalInset;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: 5,
        bottom: 5,
        left: horizontalInset,
        right: 2,
      ),
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.iosBlueDark : AppTheme.iosBlueLight,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: child,
    );
  }
}

class BotMessageBubble extends StatelessWidget {
  const BotMessageBubble({
    super.key,
    required this.isDark,
    required this.horizontalInset,
    required this.padding,
    required this.child,
  });

  final bool isDark;
  final double horizontalInset;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: 5,
        bottom: 5,
        left: 2,
        right: horizontalInset,
      ),
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.iosBubbleDark : AppTheme.iosBubbleLight,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.06 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}
