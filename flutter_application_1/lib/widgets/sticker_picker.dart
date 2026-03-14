import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../services/sticker_service.dart';
import '../screens/stickers/sticker_editor_screen.dart';
import 'success_overlay.dart';

enum _GiphyBrowseMode { stickers, memes }

class _PackStripItem {
  final String id;
  final String label;
  final String? previewUrl;
  final File? previewFile;
  final bool isAdd;
  final bool isAll;

  const _PackStripItem({
    required this.id,
    required this.label,
    this.previewUrl,
    this.previewFile,
    this.isAdd = false,
    this.isAll = false,
  });

  factory _PackStripItem.all() =>
      const _PackStripItem(id: 'all', label: 'All', isAll: true);

  factory _PackStripItem.add() =>
      const _PackStripItem(id: '_add', label: 'Add', isAdd: true);
}

class StickerPicker extends StatefulWidget {
  final ValueChanged<File> onStickerSelected;

  const StickerPicker({super.key, required this.onStickerSelected});

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker>
    with SingleTickerProviderStateMixin {
  static const Color _whatsappGreen = Color(0xFF25D366);
  final StickerService _stickerService = StickerService();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _giphySearchController = TextEditingController();

  List<File> _stickers = [];
  Set<String> _installedPacks = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _packActionInProgress;
  String _stickerQuery = '';
  String _activePackId = 'all';

  // Giphy state
  List<GiphyStickerItem> _giphyStickers = [];
  bool _giphyLoading = false;
  bool _hasGiphy = false;
  bool _supportsGiphyMemeTemplates = false;
  String? _giphySavingId; // ID of the sticker currently being saved
  _GiphyBrowseMode _giphyBrowseMode = _GiphyBrowseMode.stickers;

  static const List<String> _memeTemplateQueries = [
    'drake hotline bling',
    'woman yelling at cat',
    'this is fine',
    'surprised pikachu',
    'disaster girl',
    'success kid',
    'two buttons meme',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1) {
        if (_giphyBrowseMode != _GiphyBrowseMode.stickers) {
          _setGiphyBrowseMode(_GiphyBrowseMode.stickers);
        } else if (_giphyStickers.isEmpty) {
          _loadGiphy();
        }
        return;
      }
      if (_tabController.index == 2) {
        if (_giphyBrowseMode != _GiphyBrowseMode.memes) {
          _setGiphyBrowseMode(_GiphyBrowseMode.memes);
        } else if (_giphyStickers.isEmpty) {
          _loadGiphy();
        }
      }
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _giphySearchController.dispose();
    super.dispose();
  }

  List<File> get _filteredStickers {
    final query = _stickerQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _stickers
        : _stickers
            .where(
              (file) =>
                  file.path.toLowerCase().contains(query) ||
                  file.uri.pathSegments.last.toLowerCase().contains(query),
            )
            .toList();
    if (_activePackId == 'all') return filtered;
    return filtered
        .where((file) => _extractPackIdFromPath(file.path) == _activePackId)
        .toList();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _stickerService.warmUpCapabilities();
      final hasGiphy = await _stickerService.hasGiphy();
      await _stickerService.purgeLegacyPacks();
      final stickers = await _stickerService.getLocalStickers();
      final installedPacks = await _stickerService.getInstalledPackIds();
      if (!mounted) return;
      setState(() {
        _stickers = stickers;
        _installedPacks = installedPacks;
        _hasGiphy = hasGiphy;
        _supportsGiphyMemeTemplates =
            _stickerService.supportsGiphyMemeTemplates;
        _isLoading = false;
      });
      final previewMap = _buildPackPreviewMap();
      final validPackIds = <String>{
        ..._installedPacks,
        ...previewMap.keys,
      };
      if (_activePackId != 'all' && !validPackIds.contains(_activePackId)) {
        setState(() => _activePackId = 'all');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load stickers';
      });
    }
  }

  String _extractPackIdFromPath(String rawPath) {
    final normalized = rawPath.replaceAll('\\', '/');
    final segments = normalized.split('/');
    final packSegment = segments.firstWhere(
      (segment) => segment.startsWith('pack_'),
      orElse: () => '',
    );
    if (packSegment.isEmpty) return 'custom';
    return packSegment.replaceFirst('pack_', '');
  }

  Map<String, File> _buildPackPreviewMap() {
    final previews = <String, File>{};
    for (final sticker in _stickers) {
      final packId = _extractPackIdFromPath(sticker.path);
      previews.putIfAbsent(packId, () => sticker);
    }
    return previews;
  }

  List<_PackStripItem> _buildPackStripItems() {
    final items = <_PackStripItem>[_PackStripItem.all()];
    final previews = _buildPackPreviewMap();
    final availableById = {
      for (final pack in StickerService.availablePacks) pack.id: pack,
    };
    final installed = <String>{..._installedPacks};
    installed.addAll(previews.keys.where((id) => id != 'custom'));

    if (previews.containsKey('custom')) {
      items.add(
        _PackStripItem(
          id: 'custom',
          label: 'Custom',
          previewFile: previews['custom'],
        ),
      );
    }

    for (final pack in StickerService.availablePacks) {
      if (!installed.contains(pack.id)) continue;
      items.add(
        _PackStripItem(
          id: pack.id,
          label: pack.name,
          previewUrl: pack.previewUrl,
          previewFile: previews[pack.id],
        ),
      );
    }

    for (final packId in installed) {
      if (packId == 'custom' || availableById.containsKey(packId)) {
        continue;
      }
      items.add(
        _PackStripItem(
          id: packId,
          label: 'Imported',
          previewFile: previews[packId],
        ),
      );
    }

    items.add(_PackStripItem.add());
    return items;
  }

  void _setActivePack(String packId) {
    if (_activePackId == packId) return;
    setState(() => _activePackId = packId);
  }

  Future<void> _openPackManagerSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: AppTheme.getSurfaceColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'Sticker Packs',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppTheme.getTextColor(context),
                        ),
                      ),
                      const Spacer(),
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _importPackFromFiles,
                          icon: const Icon(Icons.folder_zip_rounded, size: 16),
                          label: const Text('Import Pack'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildPackList(isDark)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createFromGallery() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) return;

    final sourceFile = File(result.files.single.path!);
    final savedFile = await _openStickerEditor(sourceFile);

    if (savedFile == null) return;

    if (!mounted) return;
    await _loadAll();
    if (!mounted) return;
    _showSuccessOverlay(
      title: 'Sticker Created',
      message: 'Your sticker is ready to use.',
      variant: SuccessOverlayVariant.stickerImport,
    );
  }

  Future<File?> _openStickerEditor(
    File sourceFile, {
    bool startWithMemeLayout = false,
    String? sourceLabel,
  }) async {
    if (!mounted) return null;
    return Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => StickerEditorScreen(
          sourceFile: sourceFile,
          startWithMemeLayout: startWithMemeLayout,
          sourceLabel: sourceLabel,
        ),
      ),
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
    final sheetHeight = MediaQuery.of(context).size.height * 0.72;
    final isStickersTab = _tabController.index == 0;
    final isMemeTab = _tabController.index == 2;

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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  'Stickers',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: textColor,
                  ),
                ),
                const Spacer(),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: _buildSearchField(
                    isDark: isDark,
                    isGiphy: !isStickersTab,
                    isMemeTab: isMemeTab,
                  ),
                ),
                if (isStickersTab) ...[
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.add_photo_alternate_rounded,
                    onTap: _createFromGallery,
                    tooltip: 'Create from gallery',
                    isDark: isDark,
                  ),
                  const SizedBox(width: 6),
                  _buildActionButton(
                    icon: Icons.add_circle_outline_rounded,
                    onTap: _openPackManagerSheet,
                    tooltip: 'Sticker packs',
                    isDark: isDark,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                labelColor: _whatsappGreen,
                unselectedLabelColor:
                    isDark ? Colors.white70 : Colors.black54,
                dividerColor: Colors.transparent,
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sticky_note_2_outlined, size: 16),
                        SizedBox(width: 6),
                        Text('Stickers'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gif_box_outlined, size: 16),
                        SizedBox(width: 6),
                        Text('GIFs'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mood_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Memes'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStickerTab(isDark),
                _buildGiphyTab(isDark),
                _buildGiphyTab(isDark),
              ],
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

  Widget _buildSearchField({
    required bool isDark,
    required bool isGiphy,
    required bool isMemeTab,
  }) {
    final borderColor = isDark ? Colors.white12 : Colors.black12;
    final controller = isGiphy ? _giphySearchController : _searchController;
    final queryValue = isGiphy ? _giphySearchController.text : _stickerQuery;
    return TextField(
      controller: controller,
      textInputAction: isGiphy ? TextInputAction.search : TextInputAction.done,
      onSubmitted: isGiphy
          ? (value) => _loadGiphy(
                query: value.trim().isEmpty ? null : value.trim(),
              )
          : null,
      onChanged: (value) {
        if (isGiphy) {
          setState(() {});
          if (value.trim().isEmpty) {
            _loadGiphy();
          }
          return;
        }
        setState(() => _stickerQuery = value);
      },
      decoration: InputDecoration(
        hintText: isGiphy
            ? (isMemeTab ? 'Search memes...' : 'Search GIFs...')
            : 'Search stickers...',
        isDense: true,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
        suffixIcon: queryValue.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                onPressed: () {
                  controller.clear();
                  if (isGiphy) {
                    _loadGiphy();
                    setState(() {});
                    return;
                  }
                  setState(() => _stickerQuery = '');
                },
              ),
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF1F3F6),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: _whatsappGreen, width: 1.6),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: borderColor),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }

  Widget _buildPackStrip(bool isDark) {
    final items = _buildPackStripItems();
    final textColor = AppTheme.getTextColor(context);
    final borderColor = isDark ? Colors.white12 : Colors.black12;
    final chipBg = isDark ? Colors.white10 : const Color(0xFFF4F6FB);

    return SizedBox(
      height: 66,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected =
              _activePackId == item.id || (item.isAll && _activePackId == 'all');

          Widget avatar;
          if (item.isAdd) {
            avatar = Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: chipBg,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor),
              ),
              child: Icon(
                Icons.add_rounded,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            );
          } else if (item.previewUrl != null && item.previewUrl!.isNotEmpty) {
            avatar = ClipOval(
              child: CachedNetworkImage(
                imageUrl: item.previewUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 44,
                  height: 44,
                  color: chipBg,
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 44,
                  height: 44,
                  color: chipBg,
                  child: const Icon(Icons.broken_image, size: 18),
                ),
              ),
            );
          } else if (item.previewFile != null) {
            avatar = ClipOval(
              child: Image.file(
                item.previewFile!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 44,
                  height: 44,
                  color: chipBg,
                  child: const Icon(Icons.broken_image, size: 18),
                ),
              ),
            );
          } else {
            avatar = Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: chipBg,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor),
              ),
              child: Icon(
                item.isAll
                    ? Icons.history_toggle_off_rounded
                    : Icons.sticky_note_2_outlined,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            );
          }

          return GestureDetector(
            onTap: () {
              if (item.isAdd) {
                _openPackManagerSheet();
                return;
              }
              _setActivePack(item.id);
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? _whatsappGreen : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: avatar,
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 56,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? _whatsappGreen
                          : textColor.withValues(alpha: 0.7),
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

  Widget _buildStickerTab(bool isDark) {
    return Column(
      children: [
        _buildPackStrip(isDark),
        Expanded(child: _buildStickersGrid(isDark)),
      ],
    );
  }

  Widget _buildStickersGrid(bool isDark) {
    final filtered = _filteredStickers;

    return Stack(
      children: [
        GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          itemCount: filtered.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final sticker = filtered[index];
            return GestureDetector(
              onTap: () => widget.onStickerSelected(sticker),
              onLongPress: () => _deleteSticker(sticker),
              child: Semantics(
                label: 'Sticker $index',
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
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image),
                  ),
                ),
              ),
            );
          },
        ),
        if (filtered.isEmpty)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Container(
                color: Colors.transparent,
                child: _buildStickerEmptyState(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStickerEmptyState() {
    final hasQuery = _stickerQuery.trim().isNotEmpty;
    final message = hasQuery
        ? 'No matching sticker found'
        : (_activePackId == 'all'
              ? 'No stickers yet'
              : 'No stickers in this pack');
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
          if (!hasQuery)
            ElevatedButton.icon(
              onPressed: _createFromGallery,
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
              label: const Text('Create Sticker'),
            )
          else
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() => _stickerQuery = '');
              },
              child: const Text('Clear search'),
            ),
        ],
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

  // ─── GIPHY TAB ────────────────────────────────────────────────────────────

  String? _normalizedGiphyQuery({String? overrideQuery}) {
    final rawQuery = overrideQuery ?? _giphySearchController.text;
    final trimmedQuery = rawQuery.trim();
    if (trimmedQuery.isNotEmpty) return trimmedQuery;
    if (_giphyBrowseMode == _GiphyBrowseMode.memes) {
      return _memeTemplateQueries.first;
    }
    return null;
  }

  Future<void> _setGiphyBrowseMode(_GiphyBrowseMode mode) async {
    if (_giphyBrowseMode == mode) return;
    if (mode == _GiphyBrowseMode.memes && !_supportsGiphyMemeTemplates) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Using meme search fallback in this build.',
          ),
        ),
      );
    }
    setState(() {
      _giphyBrowseMode = mode;
      _giphyStickers = [];
      _giphySearchController.clear();
    });
    await _loadGiphy(query: _normalizedGiphyQuery());
  }

  Future<void> _loadGiphy({String? query}) async {
    if (!_hasGiphy) return;
    if (!mounted) return;
    setState(() => _giphyLoading = true);
    final effectiveQuery = _normalizedGiphyQuery(overrideQuery: query);
    final results = _giphyBrowseMode == _GiphyBrowseMode.memes
        ? (_supportsGiphyMemeTemplates
              ? await _stickerService.fetchGiphyMemeTemplates(
                  query: effectiveQuery,
                )
              : await _stickerService.fetchGiphyStickers(
                  query: effectiveQuery ?? _memeTemplateQueries.first,
                ))
        : await _stickerService.fetchGiphyStickers(query: effectiveQuery);
    if (!mounted) return;
    setState(() {
      _giphyStickers = results;
      _giphyLoading = false;
    });
  }

  Future<void> _saveAndSendGiphy(GiphyStickerItem item) async {
    if (_giphySavingId != null) return;
    if (!mounted) return;
    setState(() => _giphySavingId = item.id);
    try {
      final file = await _stickerService.saveGiphySticker(item);
      if (file != null && mounted) {
        widget.onStickerSelected(file);
        await _loadAll(); // refresh My Stickers tab
      }
    } catch (e) {
      debugPrint('Giphy save error: \$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save sticker. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _giphySavingId = null);
    }
  }

  Future<void> _openGiphyTemplateInEditor(GiphyStickerItem item) async {
    if (_giphySavingId != null) return;
    setState(() => _giphySavingId = item.id);
    try {
      final file = await _stickerService.downloadRemoteMediaToTemporaryFile(
        item.originalUrl,
        prefix: 'giphy_meme',
      );
      if (file == null) {
        throw Exception('Template download failed');
      }
      if (!mounted) return;
      final savedFile = await _openStickerEditor(
        file,
        startWithMemeLayout: true,
        sourceLabel: item.title,
      );
      if (savedFile != null && mounted) {
        await _loadAll();
        widget.onStickerSelected(savedFile);
      }
    } catch (e) {
      debugPrint('Giphy template edit error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to open meme template. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _giphySavingId = null);
    }
  }

  Widget _buildMemeTemplateChips() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        scrollDirection: Axis.horizontal,
        itemCount: _memeTemplateQueries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final query = _memeTemplateQueries[index];
          return ActionChip(
            label: Text(query),
            onPressed: () {
              _giphySearchController.text = query;
              _loadGiphy(query: query);
            },
          );
        },
      ),
    );
  }

  Widget _buildGiphyTab(bool isDark) {
    final mutedColor = AppTheme.getTextColor(context).withValues(alpha: 0.55);
    final isMemeMode = _giphyBrowseMode == _GiphyBrowseMode.memes;
    if (!_hasGiphy) {
      return Center(
        child: Text(
          'GIFs are currently unavailable.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: mutedColor),
        ),
      );
    }
    return Column(
      children: [
        if (isMemeMode) _buildMemeTemplateChips(),
        if (isMemeMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFBFDBFE),
                ),
              ),
              child: Text(
                _supportsGiphyMemeTemplates
                    ? 'Tap any template to open it in the editor with draggable meme text.'
                    : 'Tap any result to edit as a meme. Using GIPHY sticker search fallback.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF1E3A8A),
                ),
              ),
            ),
          ),
        Expanded(
          child: _giphyLoading
              ? const Center(child: CircularProgressIndicator())
              : _giphyStickers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isMemeMode
                            ? Icons.mood_rounded
                            : Icons.gif_box_outlined,
                        size: 48,
                        color: mutedColor,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isMemeMode
                            ? 'No meme templates found'
                            : 'No GIFs found',
                        style: GoogleFonts.inter(color: mutedColor),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: _loadGiphy,
                        child: Text(
                          isMemeMode ? 'Load Templates' : 'Load GIFs',
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.96,
                  ),
                  itemCount: _giphyStickers.length,
                  itemBuilder: (context, idx) {
                    final item = _giphyStickers[idx];
                    final isSaving = _giphySavingId == item.id;
                    return GestureDetector(
                      onTap: () => isMemeMode
                          ? _openGiphyTemplateInEditor(item)
                          : _saveAndSendGiphy(item),
                      child: Tooltip(
                        message: item.title,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.getBorderColor(context),
                            ),
                            color: isDark ? Colors.white10 : Colors.white,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (isSaving)
                                const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                CachedNetworkImage(
                                  imageUrl: item.previewUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: isDark
                                        ? Colors.white10
                                        : const Color(0xFFF0F0F0),
                                  ),
                                  errorWidget: (_, __, ___) =>
                                      const Icon(Icons.broken_image, size: 24),
                                ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  color: Colors.black.withValues(alpha: 0.48),
                                  child: Text(
                                    isMemeMode ? 'Use as meme' : 'Save sticker',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: Text(
            isMemeMode ? 'Powered by GIPHY templates' : 'Powered by GIPHY',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: mutedColor,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}
