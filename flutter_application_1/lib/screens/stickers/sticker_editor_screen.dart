import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as path;

import '../../config/theme.dart';
import '../../services/sticker_service.dart';

/// Builds a sticker editor with text and background removal controls.
class StickerEditorScreen extends StatefulWidget {
  final File sourceFile;

  /// Creates a sticker editor for the provided source image.
  const StickerEditorScreen({super.key, required this.sourceFile});

  @override
  State<StickerEditorScreen> createState() => _StickerEditorScreenState();
}

class _StickerEditorScreenState extends State<StickerEditorScreen> {
  final StickerService _stickerService = StickerService();
  final GlobalKey _previewKey = GlobalKey();
  final TextEditingController _textController = TextEditingController();

  late File _workingFile;
  bool _isRemovingBg = false;
  bool _isSaving = false;
  double _textScale = 1.0;
  Alignment _textAlignment = Alignment.bottomCenter;
  Color _textColor = Colors.white;

  static const List<Color> _textColors = [
    Colors.white,
    Colors.black,
    Color(0xFF2563EB),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    _workingFile = widget.sourceFile;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _removeBackground() async {
    if (_isRemovingBg) return;
    setState(() => _isRemovingBg = true);

    try {
      final cleaned = await _stickerService.removeBackground(_workingFile);
      if (cleaned != null && mounted) {
        setState(() => _workingFile = cleaned);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Background removal failed: $e')));
    } finally {
      if (mounted) setState(() => _isRemovingBg = false);
    }
  }

  Future<void> _saveSticker() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final boundary =
          _previewKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Preview not ready');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to render sticker');
      }

      final savedFile = await _writeSticker(bytes);
      if (!mounted) return;
      Navigator.pop(context, savedFile);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<File> _writeSticker(Uint8List bytes) async {
    final dir = await _stickerService.getStickerDirectory();
    final filename = 'custom_${DateTime.now().millisecondsSinceEpoch}.png';
    final outputPath = path.join(dir.path, filename);
    final file = File(outputPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final textColor = AppTheme.getTextColor(context);
    final canRemoveBg = _stickerService.canRemoveBackground;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          'Create Sticker',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSticker,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            _buildPreview(),
            const SizedBox(height: 16),
            _buildRemoveBgRow(isDark, canRemoveBg, textColor),
            const SizedBox(height: 16),
            _buildTextField(textColor),
            const SizedBox(height: 12),
            _buildColorRow(),
            const SizedBox(height: 12),
            _buildSizeRow(textColor),
            const SizedBox(height: 12),
            _buildAlignmentRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final overlayText = _textController.text.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            const _Checkerboard(),
            Positioned.fill(
              child: RepaintBoundary(
                key: _previewKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(_workingFile, fit: BoxFit.contain),
                    if (overlayText.isNotEmpty)
                      Align(
                        alignment: _textAlignment,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            overlayText,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 28 * _textScale,
                              fontWeight: FontWeight.w700,
                              color: _textColor,
                              shadows: const [
                                Shadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoveBgRow(bool isDark, bool canRemoveBg, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: (!canRemoveBg || _isRemovingBg) ? null : _removeBackground,
          icon: _isRemovingBg
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_fix_high_rounded, size: 18),
          label: Text(
            canRemoveBg ? 'Remove Background (HQ)' : 'Remove BG (Add API Key)',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? Colors.white : Colors.black,
          ),
        ),
        if (!canRemoveBg)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Set REMOVE_BG_API_KEY to enable background removal.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: textColor.withValues(alpha: 0.6),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTextField(Color textColor) {
    return TextField(
      controller: _textController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'Sticker text',
        hintText: 'Add a caption or word',
        labelStyle: GoogleFonts.inter(color: textColor.withValues(alpha: 0.7)),
        filled: true,
        fillColor: textColor.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      style: GoogleFonts.inter(color: textColor),
    );
  }

  Widget _buildColorRow() {
    return Wrap(
      spacing: 10,
      children: _textColors.map((color) {
        final selected = color == _textColor;
        return GestureDetector(
          onTap: () => setState(() => _textColor = color),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppTheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSizeRow(Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Text size',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        Slider(
          value: _textScale,
          min: 0.6,
          max: 1.8,
          divisions: 6,
          label: _textScale.toStringAsFixed(1),
          onChanged: (value) => setState(() => _textScale = value),
        ),
      ],
    );
  }

  Widget _buildAlignmentRow() {
    return SegmentedButton<Alignment>(
      segments: const [
        ButtonSegment(value: Alignment.topCenter, label: Text('Top')),
        ButtonSegment(value: Alignment.center, label: Text('Center')),
        ButtonSegment(value: Alignment.bottomCenter, label: Text('Bottom')),
      ],
      selected: {_textAlignment},
      onSelectionChanged: (selection) {
        setState(() => _textAlignment = selection.first);
      },
    );
  }
}

class _Checkerboard extends StatelessWidget {
  const _Checkerboard();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const squareSize = 20.0;
    final lightPaint = Paint()..color = const Color(0xFFF1F5F9);
    final darkPaint = Paint()..color = const Color(0xFFE2E8F0);

    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        final isDarkSquare = ((x / squareSize) + (y / squareSize)) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, squareSize, squareSize),
          isDarkSquare ? darkPaint : lightPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
