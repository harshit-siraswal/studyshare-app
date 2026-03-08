import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
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

class _CommentInputBoxState extends State<CommentInputBox> {
  bool _showSendButton = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _showSendButton) {
      setState(() => _showSendButton = hasText);
    }
  }

  Future<void> _openStickerPicker() async {
    if (widget.isReadOnly || widget.isSubmitting) return;

    if (widget.onStickerAccessCheck != null) {
      final canOpen = await widget.onStickerAccessCheck!.call();
      if (!mounted || !canOpen) return;
    }

    // Unfocus to hide keyboard
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
            Navigator.pop(context);
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
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryColor = isDark ? Colors.grey : Colors.black54;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reply Banner
            if (widget.replyToName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.reply_rounded,
                        size: 14,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Replying to ${widget.replyToName}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: widget.onCancelReply,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 12,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Single Pill Container (Search Bar Style)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(30), // Rounded pill
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.transparent,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Sticker Button
                  if (widget.onStickerSelected != null)
                    IconButton(
                      onPressed: (widget.isReadOnly || widget.isSubmitting)
                          ? null
                          : _openStickerPicker,
                      icon: Icon(
                        Icons.sticky_note_2_outlined,
                        color: widget.isReadOnly ? Colors.grey : secondaryColor,
                        size: 24,
                      ),
                      tooltip: 'Add Sticker',
                    ),

                  // Input Field
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      enabled: !widget.isReadOnly && !widget.isSubmitting,
                      style: GoogleFonts.inter(color: textColor, fontSize: 16),
                      maxLines: null,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: widget.isReadOnly
                            ? 'Read-only mode'
                            : widget.hintText,
                        hintStyle: GoogleFonts.inter(
                          color: secondaryColor.withValues(alpha: 0.7),
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) {
                        if (_showSendButton) widget.onSubmit();
                      },
                    ),
                  ),

                  // Send Button
                  IconButton(
                    onPressed:
                        (_showSendButton &&
                            !widget.isSubmitting &&
                            !widget.isReadOnly)
                        ? widget.onSubmit
                        : null,
                    icon: widget.isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.send_rounded,
                            color: _showSendButton
                                ? AppTheme.primary
                                : secondaryColor.withValues(alpha: 0.5),
                            size: 24,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
