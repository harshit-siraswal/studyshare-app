import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import 'sticker_picker.dart';
import 'user_avatar.dart';

/// Reply/comment composer styled after X (Twitter).
///
/// Always shows the user's avatar + an open text field inline.
/// The action toolbar (media button + post button) animates in
/// when the field is focused or has text.
class CommentInputBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isReadOnly;
  final bool isSubmitting;
  final String? replyToName;
  final VoidCallback onCancelReply;
  final VoidCallback onSubmit;
  final Function(File)? onStickerSelected;
  final Future<bool> Function()? onStickerAccessCheck;
  final String hintText;
  final String? userPhotoUrl;
  final String? userDisplayName;

  const CommentInputBox({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.isReadOnly = false,
    this.isSubmitting = false,
    this.replyToName,
    required this.onCancelReply,
    this.onStickerSelected,
    this.onStickerAccessCheck,
    this.hintText = 'Add a comment...',
    this.userPhotoUrl,
    this.userDisplayName,
  });

  @override
  State<CommentInputBox> createState() => _CommentInputBoxState();
}

class _CommentInputBoxState extends State<CommentInputBox>
    with SingleTickerProviderStateMixin {
  bool _showToolbar = false;
  late AnimationController _toolbarController;
  late Animation<double> _toolbarFade;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);

    _toolbarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _toolbarFade = CurvedAnimation(
      parent: _toolbarController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    _toolbarController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    _updateToolbarVisibility();
  }

  void _onTextChanged() {
    _updateToolbarVisibility();
    if (mounted) setState(() {});
  }

  void _updateToolbarVisibility() {
    final shouldShow =
        (widget.focusNode.hasFocus || widget.controller.text.isNotEmpty) &&
        !widget.isReadOnly;
    if (shouldShow == _showToolbar) return;
    setState(() => _showToolbar = shouldShow);
    if (shouldShow) {
      _toolbarController.forward();
    } else {
      _toolbarController.reverse();
    }
  }

  void _handleSubmit() {
    widget.onSubmit();
  }

  Future<void> _openStickerPicker() async {
    if (widget.isReadOnly || widget.isSubmitting) return;
    if (widget.onStickerAccessCheck != null) {
      final canOpen = await widget.onStickerAccessCheck!.call();
      if (!mounted || !canOpen) return;
    }
    widget.focusNode.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StickerPicker(
          onStickerSelected: (file) {
            if (widget.onStickerSelected != null) {
              widget.onStickerSelected!(file);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE2E8F0);
    final bgColor = isDark ? Colors.black : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final hintColor = isDark ? Colors.white38 : Colors.black38;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: dividerColor, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "Replying to @handle" banner — X/Twitter style
              if (widget.replyToName != null) ...[
                _ReplyBanner(
                  replyToName: widget.replyToName!,
                  isDark: isDark,
                  onCancel: () {
                    widget.onCancelReply();
                    if (widget.controller.text.isEmpty) {
                      widget.focusNode.unfocus();
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],

              // Avatar + text field row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: UserAvatar(
                      radius: 18,
                      photoUrl: widget.userPhotoUrl,
                      displayName: widget.userDisplayName ?? 'User',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      enabled: !widget.isReadOnly && !widget.isSubmitting,
                      style: GoogleFonts.inter(
                        color: textColor,
                        fontSize: 15,
                        height: 1.45,
                      ),
                      maxLines: null,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: widget.isReadOnly
                            ? 'Read-only mode'
                            : (widget.replyToName != null
                                ? 'Post your reply'
                                : widget.hintText),
                        hintStyle: GoogleFonts.inter(
                          color: hintColor,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.only(top: 6),
                      ),
                    ),
                  ),
                ],
              ),

              // Action toolbar — fades in when focused or has text
              FadeTransition(
                opacity: _toolbarFade,
                child: _showToolbar
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8, left: 48),
                        child: _Toolbar(
                          isDark: isDark,
                          hasText: widget.controller.text.trim().isNotEmpty,
                          isSubmitting: widget.isSubmitting,
                          showMediaButton: widget.onStickerSelected != null,
                          onMediaTap: _openStickerPicker,
                          onSubmit: _handleSubmit,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({
    required this.replyToName,
    required this.isDark,
    required this.onCancel,
  });

  final String replyToName;
  final bool isDark;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final handle = replyToName.contains('@')
        ? '@${replyToName.split('@').first}'
        : '@$replyToName';
    return Row(
      children: [
        const SizedBox(width: 48),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Replying to ',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                TextSpan(
                  text: handle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: onCancel,
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: isDark ? Colors.white38 : Colors.black26,
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.isDark,
    required this.hasText,
    required this.isSubmitting,
    required this.showMediaButton,
    required this.onMediaTap,
    required this.onSubmit,
  });

  final bool isDark;
  final bool hasText;
  final bool isSubmitting;
  final bool showMediaButton;
  final VoidCallback onMediaTap;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showMediaButton)
          GestureDetector(
            onTap: onMediaTap,
            child: Icon(
              Icons.image_outlined,
              size: 22,
              color: AppTheme.primary,
            ),
          ),
        const Spacer(),
        if (isSubmitting)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppTheme.primary),
            ),
          )
        else
          _PostButton(
            enabled: hasText,
            onTap: hasText ? onSubmit : null,
            isDark: isDark,
          ),
      ],
    );
  }
}

class _PostButton extends StatelessWidget {
  const _PostButton({
    required this.enabled,
    required this.onTap,
    required this.isDark,
  });

  final bool enabled;
  final VoidCallback? onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.primary
              : (isDark
                  ? AppTheme.primary.withValues(alpha: 0.35)
                  : AppTheme.primary.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Reply',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: enabled
                ? Colors.white
                : Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}
