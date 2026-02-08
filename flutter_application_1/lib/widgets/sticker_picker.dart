import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/sticker_service.dart';
import '../config/theme.dart';

class StickerPicker extends StatefulWidget {
  final ValueChanged<File> onStickerSelected;
  const StickerPicker({super.key, required this.onStickerSelected});

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  final StickerService _stickerService = StickerService();
  List<File> _stickers = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  Future<void> _loadStickers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final stickers = await _stickerService.getLocalStickers();
      if (mounted) {
        setState(() {
          _stickers = stickers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load stickers';
        });
      }
    }
  }

  Future<void> _importSticker() async {
    final file = await _stickerService.importSticker();
    if (file != null) {
      _loadStickers();
    }
  }

  Future<void> _deleteSticker(File sticker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sticker?'),
        content: const Text('This will remove the sticker from your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      await _stickerService.deleteSticker(sticker);
      if (mounted) {
        _loadStickers();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 300,
        color: AppTheme.getSurfaceColor(context),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_errorMessage != null) {
      return Container(
        height: 300,
        color: AppTheme.getSurfaceColor(context),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
               const SizedBox(height: 12),
               Text(_errorMessage!, style: TextStyle(color: AppTheme.getTextColor(context))),
               const SizedBox(height: 12),
               ElevatedButton(
                 onPressed: _loadStickers,
                 child: const Text('Retry'),
               )
            ],
          ),
        ),
      );
    }

    return Container(
      height: 300,
      color: AppTheme.getSurfaceColor(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Stickers',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.getTextColor(context),
                  ),
                ),
                TextButton.icon(
                  onPressed: _importSticker,
                  icon: const Icon(Icons.add_photo_alternate, size: 20),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _stickers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_outlined, size: 48, color: AppTheme.getTextColor(context).withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text(
                          'No stickers yet',
                          style: TextStyle(color: AppTheme.getTextColor(context).withValues(alpha: 0.7)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "Add" to import stickers',
                          style: TextStyle(fontSize: 12, color: AppTheme.getTextColor(context).withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _stickers.length,
              itemBuilder: (context, index) {
                final sticker = _stickers[index];
                return GestureDetector(
                  onTap: () => widget.onStickerSelected(sticker),
                  onLongPress: () => _deleteSticker(sticker),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.getBorderColor(context)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.file(
                          sticker,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: () => _deleteSticker(sticker),
                            customBorder: const CircleBorder(),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
