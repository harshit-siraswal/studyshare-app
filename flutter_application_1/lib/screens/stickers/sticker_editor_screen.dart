import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as path;

import '../../config/theme.dart';
import '../../services/sticker_service.dart';

class StickerEditorScreen extends StatefulWidget {
  final File sourceFile;
  final bool startWithMemeLayout;
  final String? sourceLabel;

  const StickerEditorScreen({
    super.key,
    required this.sourceFile,
    this.startWithMemeLayout = false,
    this.sourceLabel,
  });

  @override
  State<StickerEditorScreen> createState() => _StickerEditorScreenState();
}

class _StickerEditorScreenState extends State<StickerEditorScreen> {
  final StickerService _stickerService = StickerService();
  final GlobalKey _previewKey = GlobalKey();
  final TextEditingController _textController = TextEditingController();

  late File _workingFile;
  DateTime _workingFileModified = DateTime.now();
  late List<_StickerTextLayer> _layers;
  String? _selectedLayerId;
  bool _isRemovingBg = false;
  bool _isSaving = false;
  bool _canRemoveBg = false;
  bool _isWarmingUp = false;

  static const List<Color> _textColors = [
    Colors.white,
    Colors.black,
    Color(0xFFB0BEC5), // Light blue-grey (distinct from white)
    Color(0xFFF97316),
    Color(0xFF2563EB),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
    Color(0xFFFACC15),
  ];

  @override
  void initState() {
    super.initState();
    _workingFile = widget.sourceFile;
    _updateWorkingFileModified();
    _layers = widget.startWithMemeLayout
        ? [
            _StickerTextLayer.create(
              text: 'TOP TEXT',
              alignment: const Alignment(0, -0.82),
              scale: 1.2,
              color: Colors.white,
              family: _StickerFontFamily.bangers,
              style: _StickerTextStyle.outline,
              uppercase: true,
            ),
            _StickerTextLayer.create(
              text: 'BOTTOM TEXT',
              alignment: const Alignment(0, 0.82),
              scale: 1.2,
              color: Colors.white,
              family: _StickerFontFamily.bangers,
              style: _StickerTextStyle.outline,
              uppercase: true,
            ),
          ]
        : [
            _StickerTextLayer.create(
              text: '',
              alignment: const Alignment(0, 0.64),
              scale: 1,
              color: Colors.white,
              family: _StickerFontFamily.inter,
              style: _StickerTextStyle.clean,
              uppercase: false,
            ),
          ];
    _selectedLayerId = _layers.first.id;
    _syncTextFieldFromActiveLayer();
    unawaited(_warmCapabilities());
  }

  void _updateWorkingFileModified() {
    try {
      _workingFileModified = _workingFile.lastModifiedSync();
    } catch (_) {
      _workingFileModified = DateTime.now();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  _StickerTextLayer? get _activeLayer {
    final selectedId = _selectedLayerId;
    if (selectedId == null) return null;
    for (final layer in _layers) {
      if (layer.id == selectedId) return layer;
    }
    return null;
  }

  void _syncTextFieldFromActiveLayer() {
    final nextText = _activeLayer?.text ?? '';
    if (_textController.text == nextText) return;
    _textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  void _selectLayer(String layerId) {
    if (_selectedLayerId == layerId) return;
    setState(() => _selectedLayerId = layerId);
    _syncTextFieldFromActiveLayer();
  }

  void _updateActiveLayer(
    _StickerTextLayer Function(_StickerTextLayer layer) fn,
  ) {
    final selectedId = _selectedLayerId;
    if (selectedId == null) return;
    setState(() {
      _layers = _layers
          .map((layer) {
            if (layer.id != selectedId) return layer;
            return fn(layer);
          })
          .toList(growable: false);
    });
  }

  void _addTextLayer() {
    if (_layers.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can add up to 5 text layers.')),
      );
      return;
    }
    final layer = _StickerTextLayer.create(
      text: 'New text',
      alignment: Alignment(0, (_layers.length.isEven ? 0.0 : 0.22)),
      scale: 1,
      color: Colors.white,
      family: widget.startWithMemeLayout
          ? _StickerFontFamily.bangers
          : _StickerFontFamily.inter,
      style: widget.startWithMemeLayout
          ? _StickerTextStyle.outline
          : _StickerTextStyle.clean,
      uppercase: widget.startWithMemeLayout,
    );
    setState(() {
      _layers = [..._layers, layer];
      _selectedLayerId = layer.id;
    });
    _syncTextFieldFromActiveLayer();
  }

  void _duplicateActiveLayer() {
    final activeLayer = _activeLayer;
    if (activeLayer == null) return;
    if (_layers.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can add up to 5 text layers.')),
      );
      return;
    }
    final duplicated = activeLayer.copyWith(
      id: _StickerTextLayer.nextId(),
      alignment: Alignment(
        (activeLayer.alignment.x + 0.12).clamp(-1.0, 1.0),
        (activeLayer.alignment.y + 0.08).clamp(-1.0, 1.0),
      ),
    );
    setState(() {
      _layers = [..._layers, duplicated];
      _selectedLayerId = duplicated.id;
    });
    _syncTextFieldFromActiveLayer();
  }

  void _deleteActiveLayer() {
    if (_layers.length <= 1) {
      _updateActiveLayer((layer) => layer.copyWith(text: ''));
      _syncTextFieldFromActiveLayer();
      return;
    }
    final selectedId = _selectedLayerId;
    if (selectedId == null) return;
    final updated = _layers.where((layer) => layer.id != selectedId).toList();
    setState(() {
      _layers = updated;
      _selectedLayerId = updated.first.id;
    });
    _syncTextFieldFromActiveLayer();
  }

  Future<void> _removeBackground() async {
    if (_isRemovingBg) return;
    setState(() => _isRemovingBg = true);

    try {
      final cleaned = await _stickerService.removeBackground(_workingFile);
      if (cleaned != null && mounted) {
        setState(() {
          _workingFile = cleaned;
          _updateWorkingFileModified();
        });
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

  Future<void> _warmCapabilities() async {
    if (mounted) {
      setState(() => _isWarmingUp = true);
    }
    try {
      await _stickerService.warmUpCapabilities();
      final canRemoveBg = await _stickerService.canRemoveBackground();
      if (!mounted) return;
      setState(() {
        _canRemoveBg = canRemoveBg;
        _isWarmingUp = false;
      });
    } catch (e, st) {
      debugPrint('Sticker capability warmup failed: $e');
      debugPrint('$st');
    } finally {
      if (mounted && _isWarmingUp) {
        setState(() => _isWarmingUp = false);
      }
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
      Uint8List? bytes;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = data?.buffer.asUint8List();
        if (bytes == null || bytes.isEmpty) {
          throw Exception('Failed to render sticker');
        }
      } finally {
        image.dispose();
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

  TextStyle _fontStyleFor(_StickerTextLayer layer) {
    final fontSize = 28 * layer.scale;
    switch (layer.family) {
      case _StickerFontFamily.inter:
        return GoogleFonts.inter(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1,
          letterSpacing: 0.2,
        );
      case _StickerFontFamily.bebasNeue:
        return GoogleFonts.bebasNeue(
          fontSize: fontSize * 1.08,
          height: 0.92,
          letterSpacing: 1.2,
        );
      case _StickerFontFamily.bangers:
        return GoogleFonts.bangers(
          fontSize: fontSize * 1.06,
          height: 0.95,
          letterSpacing: 1,
        );
      case _StickerFontFamily.permanentMarker:
        return GoogleFonts.permanentMarker(
          fontSize: fontSize * 0.96,
          height: 1.05,
        );
    }
  }

  Widget _buildLayerVisual(
    _StickerTextLayer layer, {
    required Size canvasSize,
  }) {
    final rawText = layer.text.trim();
    if (rawText.isEmpty) {
      return const SizedBox.shrink();
    }
    final displayText = layer.uppercase ? rawText.toUpperCase() : rawText;
    final baseStyle = _fontStyleFor(layer);
    final maxWidth = canvasSize.width * 0.78;

    Widget text = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        displayText,
        textAlign: TextAlign.center,
        style: baseStyle.copyWith(
          color: layer.color,
          shadows: layer.style == _StickerTextStyle.clean
              ? const [
                  Shadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
      ),
    );

    if (layer.style == _StickerTextStyle.outline) {
      final strokeWidth = (4 * layer.scale).clamp(2.4, 6.0);
      text = Stack(
        alignment: Alignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Text(
              displayText,
              textAlign: TextAlign.center,
              style: baseStyle.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = strokeWidth
                  ..color = Colors.black.withValues(alpha: 0.9),
              ),
            ),
          ),
          text,
        ],
      );
    }

    if (layer.style == _StickerTextStyle.pill) {
      final insetScale = layer.scale.clamp(0.8, 1.6);
      text = DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14 * insetScale,
            vertical: 8 * insetScale,
          ),
          child: text,
        ),
      );
    }

    return text;
  }

  void _moveLayer(
    _StickerTextLayer layer,
    DragUpdateDetails details,
    Size canvasSize,
  ) {
    final dx = (details.delta.dx / (canvasSize.width / 2)).clamp(-1.0, 1.0);
    final dy = (details.delta.dy / (canvasSize.height / 2)).clamp(-1.0, 1.0);
    setState(() {
      _layers = _layers
          .map((entry) {
            if (entry.id != layer.id) return entry;
            return entry.copyWith(
              alignment: Alignment(
                (entry.alignment.x + dx).clamp(-1.0, 1.0),
                (entry.alignment.y + dy).clamp(-1.0, 1.0),
              ),
            );
          })
          .toList(growable: false);
      _selectedLayerId = layer.id;
    });
  }

  void _snapActiveLayerTo(Alignment alignment) {
    _updateActiveLayer((layer) => layer.copyWith(alignment: alignment));
  }

  Widget _buildPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = Size(constraints.maxWidth, constraints.maxWidth);
          return AspectRatio(
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
                        Image(
                          image: FileImage(_workingFile),
                          fit: BoxFit.contain,
                          key: ValueKey(
                            _workingFile.path +
                                _workingFileModified.toString(),
                          ),
                        ),
                        for (final layer in _layers)
                          Align(
                            alignment: layer.alignment,
                            child: _buildLayerVisual(
                              layer,
                              canvasSize: canvasSize,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Stack(
                    children: [
                      for (final layer in _layers)
                        if (layer.text.trim().isNotEmpty)
                          Align(
                            alignment: layer.alignment,
                            child: GestureDetector(
                              onTap: () => _selectLayer(layer.id),
                              onPanUpdate: (details) =>
                                  _moveLayer(layer, details, canvasSize),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: layer.id == _selectedLayerId
                                        ? AppTheme.primary
                                        : Colors.white.withValues(alpha: 0.18),
                                    width: layer.id == _selectedLayerId ? 2 : 1,
                                  ),
                                  color: layer.id == _selectedLayerId
                                      ? Colors.black.withValues(alpha: 0.08)
                                      : Colors.transparent,
                                ),
                                child: Opacity(
                                  opacity: 0,
                                  child: _buildLayerVisual(
                                    layer,
                                    canvasSize: canvasSize,
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.open_with_rounded,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Drag selected text anywhere on the sticker.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.96),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPanel({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.getTextColor(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.getBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: textColor.withValues(alpha: 0.62),
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildLayerToolbar() {
    final activeLayer = _activeLayer;
    final textColor = AppTheme.getTextColor(context);
    return _buildPanel(
      title: 'Text Layers',
      subtitle: 'Add multiple captions, move them freely, and style each one.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final layer in _layers)
                ChoiceChip(
                  selected: layer.id == _selectedLayerId,
                  label: Text(
                    layer.text.trim().isEmpty
                        ? 'Layer ${_layers.indexOf(layer) + 1}'
                        : layer.displayName,
                  ),
                  onSelected: (_) => _selectLayer(layer.id),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Text'),
                onPressed: _addTextLayer,
              ),
              if (activeLayer != null)
                ActionChip(
                  avatar: const Icon(Icons.copy_all_rounded, size: 16),
                  label: const Text('Duplicate'),
                  onPressed: _duplicateActiveLayer,
                ),
              if (activeLayer != null)
                ActionChip(
                  avatar: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Delete'),
                  onPressed: _deleteActiveLayer,
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _textController,
            onChanged: (value) {
              _updateActiveLayer((layer) => layer.copyWith(text: value));
            },
            decoration: InputDecoration(
              labelText: 'Selected text',
              hintText: widget.startWithMemeLayout
                  ? 'Type your meme caption'
                  : 'Add a caption or word',
              filled: true,
              fillColor: textColor.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            style: GoogleFonts.inter(color: textColor),
          ),
          if (activeLayer != null) ...[
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              value: activeLayer.uppercase,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Use uppercase style',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              subtitle: Text(
                'Great for punchy meme captions and labels.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: textColor.withValues(alpha: 0.62),
                ),
              ),
              onChanged: (value) {
                _updateActiveLayer((layer) => layer.copyWith(uppercase: value));
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStylePanel() {
    final activeLayer = _activeLayer;
    final textColor = AppTheme.getTextColor(context);
    if (activeLayer == null) {
      return const SizedBox.shrink();
    }
    return _buildPanel(
      title: 'Style',
      subtitle:
          'Pick a text look, font family, and color for the selected layer.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Text look',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _StickerTextStyle.values
                .map((style) {
                  return ChoiceChip(
                    selected: activeLayer.style == style,
                    label: Text(style.label),
                    onSelected: (_) {
                      _updateActiveLayer(
                        (layer) => layer.copyWith(style: style),
                      );
                    },
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 16),
          Text(
            'Font',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _StickerFontFamily.values
                .map((family) {
                  return ChoiceChip(
                    selected: activeLayer.family == family,
                    label: Text(family.label),
                    onSelected: (_) {
                      _updateActiveLayer(
                        (layer) => layer.copyWith(family: family),
                      );
                    },
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 16),
          Text(
            'Color',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _textColors
                .map((color) {
                  final selected = color == activeLayer.color;
                  return GestureDetector(
                    onTap: () {
                      _updateActiveLayer(
                        (layer) => layer.copyWith(color: color),
                      );
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? AppTheme.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildPlacementPanel() {
    final activeLayer = _activeLayer;
    final textColor = AppTheme.getTextColor(context);
    if (activeLayer == null) {
      return const SizedBox.shrink();
    }
    return _buildPanel(
      title: 'Placement',
      subtitle:
          'Drag on the canvas or use quick snaps for cleaner positioning.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Text size',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          Slider(
            value: activeLayer.scale,
            min: 0.7,
            max: 1.8,
            divisions: 11,
            label: activeLayer.scale.toStringAsFixed(1),
            onChanged: (value) {
              _updateActiveLayer((layer) => layer.copyWith(scale: value));
            },
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSnapChip('Top', const Alignment(0, -0.82)),
              _buildSnapChip('Center', const Alignment(0, 0)),
              _buildSnapChip('Bottom', const Alignment(0, 0.82)),
              _buildSnapChip('Left', const Alignment(-0.72, 0)),
              _buildSnapChip('Right', const Alignment(0.72, 0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSnapChip(String label, Alignment alignment) {
    return ActionChip(
      label: Text(label),
      onPressed: () => _snapActiveLayerTo(alignment),
    );
  }

  Widget _buildRemoveBgPanel(bool isDark) {
    final textColor = AppTheme.getTextColor(context);
    return _buildPanel(
      title: 'Sticker Tools',
      subtitle: widget.sourceLabel == null
          ? 'Clean up the source image before saving the final sticker.'
          : 'Working from: ${widget.sourceLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: (!_canRemoveBg || _isRemovingBg || _isWarmingUp)
                ? null
                : _removeBackground,
            icon: _isRemovingBg
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: Text(
              _isWarmingUp
                  ? 'Checking capabilities...'
                  : (_canRemoveBg
                        ? 'Remove Background'
                        : 'Remove BG (Unavailable)'),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Colors.white : Colors.black,
            ),
          ),
          if (!_canRemoveBg)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Background removal is currently unavailable.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: textColor.withValues(alpha: 0.62),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          widget.startWithMemeLayout ? 'Create Meme Sticker' : 'Create Sticker',
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
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
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
            _buildLayerToolbar(),
            const SizedBox(height: 14),
            _buildStylePanel(),
            const SizedBox(height: 14),
            _buildPlacementPanel(),
            const SizedBox(height: 14),
            _buildRemoveBgPanel(isDark),
          ],
        ),
      ),
    );
  }
}

enum _StickerTextStyle {
  clean('Clean'),
  outline('Outline'),
  pill('Label');

  const _StickerTextStyle(this.label);
  final String label;
}

enum _StickerFontFamily {
  inter('Inter'),
  bebasNeue('Bebas'),
  bangers('Bangers'),
  permanentMarker('Marker');

  const _StickerFontFamily(this.label);
  final String label;
}

class _StickerTextLayer {
  final String id;
  final String text;
  final Alignment alignment;
  final double scale;
  final Color color;
  final _StickerFontFamily family;
  final _StickerTextStyle style;
  final bool uppercase;

  const _StickerTextLayer({
    required this.id,
    required this.text,
    required this.alignment,
    required this.scale,
    required this.color,
    required this.family,
    required this.style,
    required this.uppercase,
  });

  factory _StickerTextLayer.create({
    required String text,
    required Alignment alignment,
    required double scale,
    required Color color,
    required _StickerFontFamily family,
    required _StickerTextStyle style,
    required bool uppercase,
  }) {
    return _StickerTextLayer(
      id: nextId(),
      text: text,
      alignment: alignment,
      scale: scale,
      color: color,
      family: family,
      style: style,
      uppercase: uppercase,
    );
  }

  static int _layerCounter = 0;

  static String nextId() =>
      'layer_${DateTime.now().microsecondsSinceEpoch}_${_layerCounter++}';

  String get displayName {
    final value = text.trim();
    if (value.isEmpty) return 'Untitled';
    return value.length > 16 ? '${value.substring(0, 16)}...' : value;
  }

  _StickerTextLayer copyWith({
    String? id,
    String? text,
    Alignment? alignment,
    double? scale,
    Color? color,
    _StickerFontFamily? family,
    _StickerTextStyle? style,
    bool? uppercase,
  }) {
    return _StickerTextLayer(
      id: id ?? this.id,
      text: text ?? this.text,
      alignment: alignment ?? this.alignment,
      scale: scale ?? this.scale,
      color: color ?? this.color,
      family: family ?? this.family,
      style: style ?? this.style,
      uppercase: uppercase ?? this.uppercase,
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
