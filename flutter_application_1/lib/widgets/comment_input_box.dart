import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../config/theme.dart';
import '../services/subscription_service.dart';
import '../widgets/paywall_dialog.dart';

class CommentInputBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isReadOnly;
  final bool isSubmitting;
  final String? replyToName;
  final VoidCallback onCancelReply;
  final VoidCallback onSubmit;
  final Function(File)? onStickerSelected;
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

  Future<void> _pickSticker() async {
    if (widget.isReadOnly) return;
    
    // Check premium status
    final isPremium = await SubscriptionService().isPremium();
    if (!isPremium) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => PaywallDialog(onSuccess: () {
            // After successful subscription, try picking sticker again
            Navigator.of(context).pop();
            _pickSticker();
          }),
        );
      }
      return;
    }
    
    // Unfocus to hide keyboard
    widget.focusNode.unfocus();

    // Pick sticker from device (WhatsApp stickers are in Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Stickers)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      dialogTitle: 'Select a Sticker',
    );

    if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
      final file = File(result.files.first.path!);
      if (widget.onStickerSelected != null) {
        widget.onStickerSelected!(file);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final secondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final inputBgColor = isDark ? AppTheme.darkCard : const Color(0xFFF5F5F5);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reply Banner
            if (widget.replyToName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.reply_rounded, size: 14, color: AppTheme.primary),
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
                          child: Icon(Icons.close_rounded, size: 12, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Input Row - Clean pill design without wrapper box
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Sticker Button (Premium Feature)
                if (widget.onStickerSelected != null) ...[
                  IconButton(
                    onPressed: widget.isReadOnly ? null : _pickSticker,
                    icon: Icon(
                      Icons.sticky_note_2_outlined, 
                      color: widget.isReadOnly ? Colors.grey : secondaryColor,
                      size: 26,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    tooltip: 'Add Sticker (Premium)',
                  ),
                  const SizedBox(width: 4),
                ],

                // Input Field - Transparent background to blend in or just underline?
                // User asked to "remove that box". 
                // Let's keep it minimal.
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: inputBgColor,
                      borderRadius: BorderRadius.circular(24),
                      // No border, just background color for the input pill
                    ),
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      enabled: !widget.isReadOnly && !widget.isSubmitting,
                      style: GoogleFonts.inter(color: textColor, fontSize: 15),
                      maxLines: null,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: widget.isReadOnly ? 'Read-only mode' : widget.hintText,
                        hintStyle: GoogleFonts.inter(
                          color: secondaryColor.withValues(alpha: 0.7), 
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) {
                        if (_showSendButton) widget.onSubmit();
                      },
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),

                // Send Button - Always visible but disabled if empty? 
                // User said "there should also be a send button after it".
                // We will show it always or when has text.
                Container(
                  decoration: BoxDecoration(
                    color: (_showSendButton || widget.isSubmitting) ? AppTheme.primary : Colors.grey.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: (_showSendButton && !widget.isSubmitting && !widget.isReadOnly) ? widget.onSubmit : null,
                    icon: widget.isSubmitting 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
