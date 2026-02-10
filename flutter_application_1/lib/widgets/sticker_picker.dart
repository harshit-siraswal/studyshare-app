import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../services/sticker_service.dart';

class StickerPicker extends StatefulWidget {
  final ValueChanged<File> onStickerSelected;

  const StickerPicker({super.key, required this.onStickerSelected});

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker>
    with SingleTickerProviderStateMixin {
  final StickerService _stickerService = StickerService();
  late TabController _tabController;

  List<File> _stickers = [];
  Set<String> _installedPacks = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _packActionInProgress;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final stickers = await _stickerService.getLocalStickers();
      final installedPacks = await _stickerService.getInstalledPackIds();
      if (!mounted) return;
      setState(() {
        _stickers = stickers;
        _installedPacks = installedPacks;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load stickers';
      });
    }
  }

  Future<void> _createFromGallery() async {
    final file = await _stickerService.importSticker(enableEditing: true);
    if (file == null) return;

    await _loadAll();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sticker added')),
    );
  }

  Future<void> _deleteSticker(File sticker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete sticker?'),
        content: const Text('This removes the sticker from this device.'),
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

    if (confirmed != true) return;

    await _stickerService.deleteSticker(sticker);
    if (!mounted) return;

    await _loadAll();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sticker deleted')),
    );
  }

  Future<void> _togglePack(StickerPack pack) async {
    if (_packActionInProgress != null) return;

    setState(() => _packActionInProgress = pack.id);

    try {
      if (_installedPacks.contains(pack.id)) {
        await _stickerService.uninstallPack(pack.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${pack.name} removed')),
          );
        }
      } else {
        final installedCount = await _stickerService.installPack(pack);
        if (mounted) {
          if (installedCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${pack.name} installed ($installedCount)'),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No stickers were downloaded. Try again.'),
              ),
            );
          }
        }
      }

      await _loadAll();
    } catch (e) {
      debugPrint('Pack action failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to complete action. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _packActionInProgress = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = AppTheme.getSurfaceColor(context);
    final textColor = AppTheme.getTextColor(context);

    if (_isLoading) {
      return Container(
        height: 420,
        color: surfaceColor,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Container(
        height: 420,
        color: surfaceColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
              const SizedBox(height: 10),
              Text(_errorMessage!, style: TextStyle(color: textColor)),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _loadAll,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 420,
      color: surfaceColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 0),
            child: Row(
              children: [
                Text(
                  'Stickers',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: textColor,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _createFromGallery,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: const Text('From Gallery'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: AppTheme.primary,
                unselectedLabelColor: isDark ? Colors.white70 : Colors.black54,
                dividerColor: Colors.transparent,
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                tabs: const [
                  Tab(text: 'My Stickers'),
                  Tab(text: 'Sticker Packs'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStickersGrid(),
                _buildPackList(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickersGrid() {
    if (_stickers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 44,
              color: AppTheme.getTextColor(context).withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'No stickers yet',
              style: GoogleFonts.inter(
                color: AppTheme.getTextColor(context).withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Use gallery import or install a pack',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.getTextColor(context).withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      itemCount: _stickers.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final sticker = _stickers[index];
        return GestureDetector(
          onTap: () => widget.onStickerSelected(sticker),
          onLongPress: () => _deleteSticker(sticker),
          child: Semantics(
            label: 'Sticker ${index + 1}. Long press to delete.',
            button: true,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.getBorderColor(context)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                sticker,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPackList(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      itemCount: StickerService.availablePacks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final pack = StickerService.availablePacks[index];
        final installed = _installedPacks.contains(pack.id);
        final busy = _packActionInProgress == pack.id;
        final previewUrl = pack.previewUrl;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: previewUrl == null
                        ? Container(
                            width: 54,
                            height: 54,
                            color: isDark
                                ? AppTheme.darkCard
                                : const Color(0xFFF0F0F0),
                            child: const Icon(Icons.broken_image, size: 24),
                          )
                        : CachedNetworkImage(
                            imageUrl: previewUrl,
                            width: 54,
                            height: 54,
                            fit: BoxFit.cover,
                            placeholder: (context, _) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (context, _, __) => Container(
                              color: isDark
                                  ? AppTheme.darkCard
                                  : const Color(0xFFF0F0F0),
                              child: const Icon(Icons.broken_image, size: 24),
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pack.name,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${pack.author} | ${pack.stickerUrls.length} stickers',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white60
                                : const Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          pack.source,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white38
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: busy ? null : () => _togglePack(pack),
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            installed
                                ? Icons.delete_outline
                                : Icons.download_rounded,
                            size: 16,
                          ),
                    label: Text(installed ? 'Remove' : 'Install'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: installed
                          ? AppTheme.error
                          : AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: pack.stickerUrls.length < 6
                      ? pack.stickerUrls.length
                      : 6,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, previewIndex) {
                    final url = pack.stickerUrls[previewIndex];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: url,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (context, _) => Container(
                          color: isDark
                              ? AppTheme.darkCard
                              : const Color(0xFFF0F0F0),
                        ),
                        errorWidget: (context, _, __) => Container(
                          color: isDark
                              ? AppTheme.darkCard
                              : const Color(0xFFF0F0F0),
                          child: const Icon(Icons.broken_image, size: 20),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
