import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import 'sticker_picker.dart';

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
  });

  @override
  State<CommentInputBox> createState() => _CommentInputBoxState();
}

class _CommentInputBoxState extends State<CommentInputBox>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
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
    final bgColor = isDark ? const Color(0xFF0B1015) : Colors.white;
    final surfaceColor = isDark ? const Color(0xFF16181C) : const Color(0xFFF4F6F9);
    final textColor = isDark ? Colors.white : Colors.black;
    final mutedColor = isDark ? Colors.white60 : Colors.black54;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
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
                    const SizedBox(height: 10),
                  ],
                  // Main input area
                  Row(
                    crossAxisAlignment: _isExpanded
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      // User avatar
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppTheme.primary,
                        child: Text(
                          'U',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _isExpanded
                            ? _buildExpandedInput(isDark, textColor, mutedColor)
                            : _buildCompactBar(mutedColor),
                      ),
                      if (!_isExpanded) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.open_in_full_rounded,
                          size: 18,
                          color: mutedColor,
                        ),
                      ],
                    ],
                  ),
                  // Expanded controls
                  if (_isExpanded) ...[
                    const SizedBox(height: 12),
                    _buildExpandedControls(isDark, mutedColor),
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
    return Row(
      children: [
        Icon(
          Icons.reply_rounded,
          size: 14,
          color: AppTheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          'Replying to ${widget.replyToName}',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppTheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: () {
            widget.onCancelReply();
            if (widget.controller.text.isEmpty) {
              _collapse();
            }
          },
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactBar(Color mutedColor) {
    return Container(
      height: 40,
      alignment: Alignment.centerLeft,
      child: Text(
        widget.isReadOnly
            ? 'Read-only mode'
            : (widget.replyToName != null ? 'Post your reply' : widget.hintText),
        style: GoogleFonts.inter(
          fontSize: 15,
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
        fontSize: 16,
        height: 1.5,
      ),
      maxLines: null,
      minLines: 3,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: widget.isReadOnly
            ? 'Read-only mode'
            : (widget.replyToName != null ? 'Post your reply' : widget.hintText),
        hintStyle: GoogleFonts.inter(
          color: mutedColor,
          fontSize: 16,
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      onSubmitted: (_) {
        if (widget.controller.text.trim().isNotEmpty) {
          _handleSubmit();
        }
      },
    );
  }

  Widget _buildExpandedControls(bool isDark, Color mutedColor) {
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
              size: 22,
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
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          ElevatedButton(
            onPressed: widget.isReadOnly ||
                    widget.controller.text.trim().isEmpty
                ? null
                : _handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              minimumSize: const Size(0, 36),
            ),
            child: Text(
              'Reply',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }
}
