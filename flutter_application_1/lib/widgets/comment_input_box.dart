import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import 'sticker_picker.dart';
import 'user_avatar.dart';

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
  bool _isExpanded = false;
  late AnimationController _expandController;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    _expandController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus && !_isExpanded) {
      _expand();
    }
  }

  void _onTextChanged() {
    if (widget.controller.text.isNotEmpty && !_isExpanded) {
      _expand();
    }
    // Re-render when text changes to enable/disable button
    if (mounted) setState(() {});
  }

  void _expand() {
    if (widget.isReadOnly) return;
    setState(() => _isExpanded = true);
    _expandController.forward();
  }

  void _collapse() {
    widget.focusNode.unfocus();
    setState(() => _isExpanded = false);
    _expandController.reverse();
  }

  void _handleSubmit() {
    widget.onSubmit();
    if (widget.replyToName == null) {
      _collapse();
    }
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
    final bgColor = isDark ? const Color(0xFF000000) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final mutedColor = isDark ? Colors.white60 : Colors.black54;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE2E8F0),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: _expand,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Reply banner
                  if (widget.replyToName != null) ...[
                    _buildReplyBanner(isDark),
                    const SizedBox(height: 8),
                  ],
                  // Main input area
                  Row(
                    crossAxisAlignment: _isExpanded
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      // User avatar
                      UserAvatar(
                        radius: 16,
                        photoUrl: widget.userPhotoUrl,
                        displayName: widget.userDisplayName ?? 'User',
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _isExpanded
                            ? _buildExpandedInput(isDark, textColor, mutedColor)
                            : _buildCompactBar(mutedColor, isDark),
                      ),
                      if (!_isExpanded) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.open_in_full_rounded,
                          size: 16,
                          color: mutedColor,
                        ),
                      ],
                    ],
                  ),
                  // Expanded controls
                  if (_isExpanded) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(left: 42),
                      child: _buildExpandedControls(isDark, mutedColor),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyBanner(bool isDark) {
    final handle = widget.replyToName?.contains('@') == true
        ? '@${widget.replyToName!.split('@').first}'
        : '@${widget.replyToName}';
    return Row(
      children: [
        Text(
          'Replying to ',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        Text(
          handle,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppTheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () {
            widget.onCancelReply();
            if (widget.controller.text.isEmpty) {
              _collapse();
            }
          },
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: isDark ? Colors.white54 : Colors.black38,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactBar(Color mutedColor, bool isDark) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16181C) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
          width: 0.5,
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        widget.isReadOnly
            ? 'Read-only mode'
            : (widget.replyToName != null ? 'Post your reply' : widget.hintText),
        style: GoogleFonts.inter(
          fontSize: 14,
          color: mutedColor,
        ),
      ),
    );
  }

  Widget _buildExpandedInput(bool isDark, Color textColor, Color mutedColor) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: !widget.isReadOnly && !widget.isSubmitting,
      style: GoogleFonts.inter(
        color: textColor,
        fontSize: 15,
        height: 1.4,
      ),
      maxLines: null,
      minLines: 2,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: widget.isReadOnly
            ? 'Read-only mode'
            : (widget.replyToName != null ? 'Post your reply' : widget.hintText),
        hintStyle: GoogleFonts.inter(
          color: mutedColor,
          fontSize: 15,
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
      ),
      onSubmitted: (_) {
        if (widget.controller.text.trim().isNotEmpty) {
          _handleSubmit();
        }
      },
    );
  }

  Widget _buildExpandedControls(bool isDark, Color mutedColor) {
    final textNotEmpty = widget.controller.text.trim().isNotEmpty;
    return Row(
      children: [
        // Sticker / image button
        if (widget.onStickerSelected != null)
          IconButton(
            onPressed: (widget.isReadOnly || widget.isSubmitting)
                ? null
                : _openStickerPicker,
            icon: Icon(
              Icons.image_outlined,
              color: widget.isReadOnly ? Colors.grey : AppTheme.primary,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        const Spacer(),
        // Submit button
        if (widget.isSubmitting)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppTheme.primary),
            ),
          )
        else
          ElevatedButton(
            onPressed: widget.isReadOnly || !textNotEmpty
                ? null
                : _handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.4),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              minimumSize: const Size(0, 32),
            ),
            child: Text(
              'Reply',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}
