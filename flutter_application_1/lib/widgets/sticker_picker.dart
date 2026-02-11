import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../services/sticker_service.dart';
import '../screens/stickers/sticker_editor_screen.dart';
import 'success_overlay.dart';

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
  final TextEditingController _searchController = TextEditingController();

  List<File> _stickers = [];
  Set<String> _installedPacks = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _packActionInProgress;
  String _stickerQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<File> get _filteredStickers {
    if (_stickerQuery.trim().isEmpty) return _stickers;
    final query = _stickerQuery.toLowerCase();
    return _stickers
        .where(
          (file) =>
              file.path.toLowerCase().contains(query) ||
              file.uri.pathSegments.last.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _stickerService.purgeLegacyPacks();
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
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) return;

    final sourceFile = File(result.files.single.path!);
    if (!mounted) return;

    final savedFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => StickerEditorScreen(sourceFile: sourceFile),
      ),
    );

    if (savedFile == null) return;

    await _loadAll();
    if (!mounted) return;
    _showSuccessOverlay(
      title: 'Sticker Created',
      message: 'Your sticker is ready to use.',
      variant: SuccessOverlayVariant.stickerImport,
    );
  }

  Future<void> _importPackFromFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      );

      if (result == null || result.files.isEmpty) return;
      final filePaths = result.files
          .map((file) => file.path)
          .whereType<String>()
          .where((path) => path.trim().isNotEmpty)
          .toList();
      if (filePaths.isEmpty) return;

      final importResult = await _stickerService.importPackFromPaths(
        paths: filePaths,
        packName: 'Imported Pack',
      );
      if (importResult.importedCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No valid stickers found in selected files.'),
            ),
          );
        }
        return;
      }

      await _loadAll();
      if (!mounted) return;
      _showSuccessOverlay(
        title: 'Sticker Pack Installed',
        message:
            '${importResult.importedCount} stickers installed to your library.',
        variant: SuccessOverlayVariant.stickerImport,
        badgeLabel: importResult.skippedCount > 0
            ? '${importResult.skippedCount} skipped'
            : null,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to import sticker pack. Please try again.'),
        ),
      );
    }
  }

  void _showSuccessOverlay({
    required String title,
    required String message,
    required SuccessOverlayVariant variant,
    String? badgeLabel,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SuccessOverlay(
        title: title,
        message: message,
        badgeLabel: badgeLabel,
        variant: variant,
        onDismiss: () => Navigator.pop(context),
      ),
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sticker deleted')));
  }

  Future<void> _togglePack(StickerPack pack) async {
    if (_packActionInProgress != null) return;

    setState(() => _packActionInProgress = pack.id);

    try {
      if (_installedPacks.contains(pack.id)) {
        await _stickerService.uninstallPack(pack.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${pack.name} removed')));
        }
      } else {
        final installedCount = await _stickerService.installPack(pack);
        if (mounted) {
          if (installedCount > 0) {
            _showSuccessOverlay(
              title: '${pack.name} Installed',
              message: '$installedCount stickers are now available.',
              variant: SuccessOverlayVariant.stickerImport,
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
    final mutedColor = textColor.withValues(alpha: 0.65);
    final sheetHeight = MediaQuery.of(context).size.height * 0.72;

    if (_isLoading) {
      return Container(
        height: sheetHeight,
        color: surfaceColor,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Container(
        height: sheetHeight,
        color: surfaceColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
              const SizedBox(height: 10),
              Text(_errorMessage!, style: TextStyle(color: textColor)),
              const SizedBox(height: 10),
              ElevatedButton(onPressed: _loadAll, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 22,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                const SizedBox(width: 36),
                Expanded(
                  child: Text(
                    'Stickers',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: textColor,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Text(
              'Create stickers with text or remove background for a clean look.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: mutedColor),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                _buildActionButton(
                  icon: Icons.add_photo_alternate_rounded,
                  onTap: _createFromGallery,
                  tooltip: 'Create from gallery',
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.folder_zip_rounded,
                  onTap: _importPackFromFiles,
                  tooltip: 'Import sticker pack',
                  isDark: isDark,
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildSearchField(isDark)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
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
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildStickersGrid(isDark), _buildPackList(isDark)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    required bool isDark,
  }) {
    final iconColor = isDark ? Colors.white70 : Colors.black87;
    final bgColor = isDark
        ? Colors.white10
        : Colors.black.withValues(alpha: 0.06);
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }

  Widget _buildSearchField(bool isDark) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _stickerQuery = value),
      decoration: InputDecoration(
        hintText: 'Search stickers...',
        isDense: true,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
        suffixIcon: _stickerQuery.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _stickerQuery = '');
                },
              ),
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF4F6FB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Widget _buildStickersGrid(bool isDark) {
    final stickers = _filteredStickers;
    if (stickers.isEmpty) {
      return _buildStickerEmptyState();
    }

    final items = <File?>[null, ...stickers];

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildCreateTile(isDark);
        }
        final sticker = items[index]!;
        return GestureDetector(
          onTap: () => widget.onStickerSelected(sticker),
          onLongPress: () => _deleteSticker(sticker),
          child: Semantics(
            label: 'Sticker ${index + 1}. Long press to delete.',
            button: true,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.getBorderColor(context)),
                color: isDark ? Colors.white10 : Colors.white,
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

  Widget _buildStickerEmptyState() {
    final message = _stickerQuery.trim().isEmpty
        ? 'No stickers yet'
        : 'No matching sticker found';
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
            message,
            style: GoogleFonts.inter(
              color: AppTheme.getTextColor(context).withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Create stickers from photos or import packs.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.getTextColor(context).withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _createFromGallery,
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
            label: const Text('Create Sticker'),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateTile(bool isDark) {
    final borderColor = isDark ? Colors.white24 : Colors.black12;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    return InkWell(
      onTap: _createFromGallery,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
          color: isDark ? Colors.white10 : Colors.white,
        ),
        child: Center(
          child: Icon(Icons.add_rounded, size: 28, color: iconColor),
        ),
      ),
    );
  }

  Widget _buildPackList(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      itemCount: StickerService.availablePacks.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : const Color(0xFFBFDBFE),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: isDark ? Colors.white70 : const Color(0xFF1D4ED8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'For WhatsApp/Telegram sticker exports, share files to this app or use Import Pack.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : const Color(0xFF1E3A8A),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final pack = StickerService.availablePacks[index - 1];
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
