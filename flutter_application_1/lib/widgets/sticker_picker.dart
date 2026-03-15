import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../config/theme.dart';
import '../services/sticker_service.dart';

class ImgflipTemplate {
  final String id;
  final String name;
  final String url;
  final int width;
  final int height;
  final int boxCount;

  const ImgflipTemplate({
    required this.id,
    required this.name,
    required this.url,
    required this.width,
    required this.height,
    required this.boxCount,
  });

  factory ImgflipTemplate.fromJson(Map<String, dynamic> json) {
    return ImgflipTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      width: json['width'] is int ? json['width'] as int : 0,
      height: json['height'] is int ? json['height'] as int : 0,
      boxCount: json['box_count'] is int ? json['box_count'] as int : 2,
    );
  }
}

class TenorGifItem {
  final String url;
  final int width;
  final int height;

  const TenorGifItem({
    required this.url,
    required this.width,
    required this.height,
  });

  factory TenorGifItem.fromJson(Map<String, dynamic> json) {
    final media = json['media_formats'] as Map<String, dynamic>? ?? {};
    final gif = media['gif'] as Map<String, dynamic>? ?? {};
    final dims = (gif['dims'] as List?) ?? const [0, 0];
    return TenorGifItem(
      url: gif['url']?.toString() ?? '',
      width: dims.isNotEmpty ? dims.first as int : 0,
      height: dims.length > 1 ? dims[1] as int : 0,
    );
  }
}

class GiphyGifItem {
  final String id;
  final String title;
  final String fixedWidthUrl;
  final String originalUrl;
  final double aspectRatio;

  const GiphyGifItem({
    required this.id,
    required this.title,
    required this.fixedWidthUrl,
    required this.originalUrl,
    required this.aspectRatio,
  });
}

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

  final TextEditingController _stickerSearchController =
      TextEditingController();
  final TextEditingController _gifSearchController = TextEditingController();

  List<File> _stickers = [];
  bool _isLoading = true;
  String? _errorMessage;

  String _activePackId = 'all';
  String _stickerQuery = '';

  List<GiphyStickerItem> _giphyStickerResults = [];
  bool _giphyLoading = false;

  List<GiphyGifItem> _giphyGifResults = [];
  bool _gifLoading = false;
  String _gifQuery = '';
  String? _gifError;

  List<ImgflipTemplate> _imgflipTemplates = [];
  List<TenorGifItem> _tenorGifs = [];
  bool _memesLoading = false;
  String? _memeError;
  ImgflipTemplate? _activeTemplate;
  List<TextEditingController> _memeTextControllers = [];
  bool _memeSubmitting = false;

  Timer? _stickerSearchDebounce;
  Timer? _gifSearchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
    _loadMemes();
    _loadGiphy();
    _loadGiphyGifs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _stickerSearchController.dispose();
    _gifSearchController.dispose();
    for (final controller in _memeTextControllers) {
      controller.dispose();
    }
    _stickerSearchDebounce?.cancel();
    _gifSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _stickerService.warmUpCapabilities();
      await _stickerService.purgeLegacyPacks();
      await _stickerService.ensureDefaultAnimatedPacksInstalled(packCount: 3);
      final stickers = await _stickerService.getLocalStickers();
      if (!mounted) return;
      setState(() {
        _stickers = stickers;
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

  Future<void> _loadGiphy({String? query}) async {
    if (!mounted) return;
    setState(() => _giphyLoading = true);
    final trimmed = query?.trim();
    final results = await _stickerService.fetchGiphyStickers(
      query: trimmed?.isEmpty == true ? null : trimmed,
      limit: 24,
    );
    if (!mounted) return;
    setState(() {
      _giphyStickerResults = results;
      _giphyLoading = false;
    });
  }

  Future<void> _loadGiphyGifs({String? query}) async {
    final key = AppConfig.giphyApiKey.trim();
    if (key.isEmpty) {
      setState(() {
        _gifError = 'GIPHY key not configured.';
        _giphyGifResults = [];
      });
      return;
    }

    setState(() {
      _gifLoading = true;
      _gifError = null;
    });

    final endpoint = (query == null || query.trim().isEmpty)
        ? 'https://api.giphy.com/v1/gifs/trending'
        : 'https://api.giphy.com/v1/gifs/search';
    final params = {
      'api_key': key,
      'limit': '25',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    };

    try {
      final uri = Uri.parse(endpoint).replace(queryParameters: params);
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw Exception('GIPHY error ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (decoded['data'] as List?) ?? [];
      final items = data.map((item) {
        final images = item['images'] as Map<String, dynamic>? ?? {};
        final fixed = images['fixed_width'] as Map<String, dynamic>? ?? {};
        final original = images['original'] as Map<String, dynamic>? ?? {};
        final fixedUrl = fixed['url']?.toString() ?? '';
        final origUrl = original['url']?.toString() ?? '';
        final width = double.tryParse(fixed['width']?.toString() ?? '') ?? 1;
        final height = double.tryParse(fixed['height']?.toString() ?? '') ?? 1;
        return GiphyGifItem(
          id: item['id']?.toString() ?? '',
          title: item['title']?.toString() ?? '',
          fixedWidthUrl: fixedUrl,
          originalUrl: origUrl.isEmpty ? fixedUrl : origUrl,
          aspectRatio: width / (height == 0 ? 1 : height),
        );
      }).where((item) => item.fixedWidthUrl.isNotEmpty).toList();

      if (!mounted) return;
      setState(() {
        _giphyGifResults = items;
        _gifLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _gifError = 'Failed to load GIFs';
        _gifLoading = false;
      });
    }
  }

  Future<void> _loadMemes() async {
    setState(() {
      _memesLoading = true;
      _memeError = null;
    });

    try {
      final imgflipRes = await http
          .get(Uri.parse('https://api.imgflip.com/get_memes'))
          .timeout(const Duration(seconds: 15));
      final imgflipDecoded = jsonDecode(imgflipRes.body) as Map<String, dynamic>;
      final templates =
          (imgflipDecoded['data']?['memes'] as List? ?? [])
              .map((e) => ImgflipTemplate.fromJson(e as Map<String, dynamic>))
              .toList();

      final tenorUri = Uri.parse(
        'https://tenor.googleapis.com/v2/search?q=meme&key=${AppConfig.tenorApiKey}&limit=20&media_filter=gif',
      );
      final tenorRes =
          await http.get(tenorUri).timeout(const Duration(seconds: 15));
      final tenorDecoded = jsonDecode(tenorRes.body) as Map<String, dynamic>;
      final tenorResults = (tenorDecoded['results'] as List? ?? [])
          .map((e) => TenorGifItem.fromJson(e as Map<String, dynamic>))
          .where((e) => e.url.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _imgflipTemplates = templates.take(20).toList();
        _tenorGifs = tenorResults;
        _memesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _memesLoading = false;
        _memeError = 'Failed to load memes';
      });
    }
  }

  List<File> get _filteredLocalStickers {
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

  Future<File?> _downloadToTempFile(String url, String prefix) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      final tempDir = await getTemporaryDirectory();
      final ext = path.extension(Uri.parse(url).path);
      final safeExt = ext.isEmpty ? '.gif' : ext;
      final filePath = path.join(
        tempDir.path,
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}$safeExt',
      );
      final file = File(filePath);
      await file.writeAsBytes(res.bodyBytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendRemoteMedia(String url, {String prefix = 'remote'}) async {
    final file = await _downloadToTempFile(url, prefix);
    if (file == null) return;
    widget.onStickerSelected(file);
  }

  Future<void> _openMemeEditor(ImgflipTemplate template) async {
    for (final controller in _memeTextControllers) {
      controller.dispose();
    }
    _memeTextControllers = List.generate(
      template.boxCount > 2 ? 2 : template.boxCount,
      (_) => TextEditingController(),
    );
    setState(() {
      _activeTemplate = template;
      _memeSubmitting = false;
    });
  }

  Future<void> _submitMeme() async {
    final template = _activeTemplate;
    if (template == null || _memeSubmitting) return;

    final navigator = Navigator.of(context);
    setState(() => _memeSubmitting = true);

    try {
      final text0 = _memeTextControllers.isNotEmpty
          ? _memeTextControllers[0].text.trim()
          : '';
      final text1 = _memeTextControllers.length > 1
          ? _memeTextControllers[1].text.trim()
          : '';

      final payload = {
        'template_id': template.id,
        'username': AppConfig.imgflipUsername,
        'password': AppConfig.imgflipPassword,
        'text0': text0,
        'text1': text1,
      };

      final res = await http.post(
        Uri.parse('https://api.imgflip.com/caption_image'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: payload,
      );

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      if (decoded['success'] == true) {
        final url = decoded['data']?['url']?.toString() ?? '';
        if (url.isNotEmpty) {
          await _sendRemoteMedia(url, prefix: 'imgflip');
          if (!mounted) return;
          navigator.pop();
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meme creation failed, try again')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meme creation failed, try again')),
        );
      }
    } finally {
      if (mounted) setState(() => _memeSubmitting = false);
    }
  }

  Widget _buildSegmentedTabs(bool isDark) {
    final labels = ['Stickers', 'GIFs', 'Memes'];
    return Row(
      children: labels.asMap().entries.map((entry) {
        final selected = _tabController.index == entry.key;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _tabController.animateTo(entry.key)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                entry.value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : (isDark ? Colors.white54 : Colors.black45),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSearchBar({
    required TextEditingController controller,
    required bool isDark,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.search,
              size: 18, color: isDark ? Colors.white54 : Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerPackStrip(bool isDark) {
    final previews = _buildPackPreviewMap();
    final items = StickerService.availablePacks
        .where((pack) => previews.containsKey(pack.id))
        .toList();

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final pack = items[index];
          final isActive = _activePackId == pack.id;
          final preview = previews[pack.id];
          return GestureDetector(
            onTap: () => setState(() => _activePackId = pack.id),
            child: Container(
              width: 64,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.primary.withValues(alpha: 0.18)
                    : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive ? AppTheme.primary : Colors.transparent,
                ),
              ),
              child: preview == null
                  ? const Icon(Icons.sticky_note_2_outlined)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        preview,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStickerGrid(bool isDark) {
    final items = _stickerQuery.trim().isNotEmpty
        ? _giphyStickerResults
        : _filteredLocalStickers;

    if (_stickerQuery.trim().isNotEmpty && _giphyLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return Center(
        child: Text(
          'No stickers found',
          style: GoogleFonts.inter(
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }

    if (_stickerQuery.trim().isNotEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.only(top: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: _giphyStickerResults.length,
        itemBuilder: (context, index) {
          final item = _giphyStickerResults[index];
          return GestureDetector(
            onTap: () async {
              final navigator = Navigator.of(context);
              final file = await _stickerService.saveGiphySticker(item);
              if (!mounted || file == null) return;
              widget.onStickerSelected(file);
              navigator.pop();
            },
            child: CachedNetworkImage(
              imageUrl: item.previewUrl,
              fit: BoxFit.cover,
            ),
          );
        },
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(top: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _filteredLocalStickers.length,
      itemBuilder: (context, index) {
        final file = _filteredLocalStickers[index];
        return GestureDetector(
          onTap: () {
            widget.onStickerSelected(file);
            Navigator.pop(context);
          },
          child: Image.file(file, fit: BoxFit.cover),
        );
      },
    );
  }

  Widget _buildGifGrid(bool isDark) {
    if (_gifLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_gifError != null) {
      return Center(
        child: Text(
          _gifError!,
          style: GoogleFonts.inter(
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }
    if (_giphyGifResults.isEmpty) {
      return Center(
        child: Text(
          'No GIFs found',
          style: GoogleFonts.inter(
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }
    return MasonryGridView.count(
      padding: const EdgeInsets.only(top: 8),
      crossAxisCount: 2,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      itemCount: _giphyGifResults.length,
      itemBuilder: (context, index) {
        final item = _giphyGifResults[index];
        return GestureDetector(
          onTap: () async {
            final navigator = Navigator.of(context);
            await _sendRemoteMedia(item.originalUrl, prefix: 'giphy_gif');
            if (!mounted) return;
            navigator.pop();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: item.fixedWidthUrl,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMemeEditor(bool isDark) {
    final template = _activeTemplate;
    if (template == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() => _activeTemplate = null),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Text(
                    'Create Meme',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: template.url,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _memeTextControllers.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return TextField(
                      controller: _memeTextControllers[index],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: index == 0 ? 'Top text' : 'Bottom text',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w700,
                        ),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _memeSubmitting ? null : _submitMeme,
                    child:
                        Text(_memeSubmitting ? 'Creating...' : 'Create Meme'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemesTab(bool isDark) {
    if (_memesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_memeError != null) {
      return Center(
        child: Text(
          _memeError!,
          style: GoogleFonts.inter(
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: constraints.maxHeight,
          child: Stack(
            children: [
              ListView(
                children: [
                  const SizedBox(height: 10),
                  if (_imgflipTemplates.isNotEmpty)
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _imgflipTemplates.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final template = _imgflipTemplates[index];
                          return GestureDetector(
                            onTap: () => _openMemeEditor(template),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: template.url,
                                width: 140,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  MasonryGridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _tenorGifs.length,
                    itemBuilder: (context, index) {
                      final item = _tenorGifs[index];
                      return GestureDetector(
                        onTap: () async {
                          final navigator = Navigator.of(context);
                          await _sendRemoteMedia(item.url, prefix: 'tenor');
                          if (!mounted) return;
                          navigator.pop();
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: item.url,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
              _buildMemeEditor(isDark),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetHeight = MediaQuery.of(context).size.height * 0.6;

    if (_isLoading) {
      return Container(
        height: sheetHeight,
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Container(
        height: sheetHeight,
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
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
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  'Stickers',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: isDark ? Colors.white : Colors.black87,
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _buildSegmentedTabs(isDark),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      _buildSearchBar(
                        controller: _stickerSearchController,
                        isDark: isDark,
                        hint: 'Search stickers',
                        onChanged: (value) {
                          _stickerQuery = value;
                          _stickerSearchDebounce?.cancel();
                          _stickerSearchDebounce = Timer(
                            const Duration(milliseconds: 400),
                            () => _loadGiphy(query: _stickerQuery),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      if (_stickerQuery.trim().isEmpty) ...[
                        _buildStickerPackStrip(isDark),
                        const SizedBox(height: 10),
                      ],
                      Expanded(child: _buildStickerGrid(isDark)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      _buildSearchBar(
                        controller: _gifSearchController,
                        isDark: isDark,
                        hint: 'Search GIFs',
                        onChanged: (value) {
                          _gifQuery = value;
                          _gifSearchDebounce?.cancel();
                          _gifSearchDebounce = Timer(
                            const Duration(milliseconds: 400),
                            () => _loadGiphyGifs(query: _gifQuery),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Expanded(child: _buildGifGrid(isDark)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _buildMemesTab(isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
