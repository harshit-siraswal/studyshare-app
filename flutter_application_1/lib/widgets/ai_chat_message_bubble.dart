import 'package:flutter/material.dart';

import '../config/theme.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.isUser,
    required this.isDark,
    required this.horizontalInset,
    required this.padding,
    required this.child,
  });

  final bool isUser;
  final bool isDark;
  final double horizontalInset;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = isUser
        ? (isDark ? AppTheme.iosBlueDark : AppTheme.iosBlueLight)
        : (isDark ? AppTheme.iosBubbleDark : AppTheme.iosBubbleLight);
    final borderRadius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.chatBubbleRadiusLarge),
            topRight: Radius.circular(AppTheme.chatBubbleRadiusLarge),
            bottomLeft: Radius.circular(AppTheme.chatBubbleRadiusLarge),
            bottomRight: Radius.circular(AppTheme.chatBubbleRadiusSmall),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.chatBubbleRadiusLarge),
            topRight: Radius.circular(AppTheme.chatBubbleRadiusLarge),
            bottomLeft: Radius.circular(AppTheme.chatBubbleRadiusSmall),
            bottomRight: Radius.circular(AppTheme.chatBubbleRadiusLarge),
          );
    final margin = isUser
        ? EdgeInsets.only(
            top: AppTheme.chatBubbleVerticalPadding,
            bottom: AppTheme.chatBubbleVerticalPadding,
            left: horizontalInset,
            right: AppTheme.chatBubbleHorizontalPadding,
          )
        : EdgeInsets.only(
            top: AppTheme.chatBubbleVerticalPadding,
            bottom: AppTheme.chatBubbleVerticalPadding,
            left: AppTheme.chatBubbleHorizontalPadding,
            right: horizontalInset,
          );

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        boxShadow: isUser
            ? null
            : [
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
    return ChatMessageBubble(
      isUser: true,
      isDark: isDark,
      horizontalInset: horizontalInset,
      padding: padding,
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
    final margin = EdgeInsets.only(
      top: AppTheme.chatBubbleVerticalPadding,
      bottom: AppTheme.chatBubbleVerticalPadding,
      left: AppTheme.chatBubbleHorizontalPadding,
      right: horizontalInset,
    );

    return Container(margin: margin, padding: padding, child: child);
  }
}
