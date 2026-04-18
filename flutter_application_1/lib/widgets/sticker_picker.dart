import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../config/theme.dart';
import '../screens/stickers/sticker_editor_screen.dart';
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
  Set<String> _installedPackIds = {};
  bool _isLoading = true;
  String? _errorMessage;

  String _stickerQuery = '';
  String _selectedPackId = 'all';

  List<GiphyStickerItem> _giphyStickerResults = [];
  bool _giphyLoading = false;

  List<GiphyGifItem> _giphyGifResults = [];
  bool _gifLoading = false;
  String _gifQuery = '';
  String? _gifError;
  int _gifOffset = 0;
  bool _gifLoadingMore = false;
  bool _gifHasMore = true;
  final ScrollController _gifScrollController = ScrollController();

  List<ImgflipTemplate> _imgflipTemplates = [];
  List<TenorGifItem> _tenorGifs = [];
  bool _memesLoading = false;
  String? _memeError;
  String? _tenorNextPos;
  bool _tenorLoadingMore = false;
  final ScrollController _tenorScrollController = ScrollController();

  Timer? _stickerSearchDebounce;
  Timer? _gifSearchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _gifScrollController.addListener(_handleGifScroll);
    _tenorScrollController.addListener(_handleTenorScroll);
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
    _gifScrollController.dispose();
    _tenorScrollController.dispose();
    _stickerSearchDebounce?.cancel();
    _gifSearchDebounce?.cancel();
    super.dispose();
  }

  void _handleGifScroll() {
    if (!_gifHasMore || _gifLoading || _gifLoadingMore) return;
    if (!_gifScrollController.hasClients) return;
    final threshold = _gifScrollController.position.maxScrollExtent - 300;
    if (_gifScrollController.position.pixels >= threshold) {
      _loadGiphyGifs(query: _gifQuery, append: true);
    }
  }

  void _handleTenorScroll() {
    if (_tenorLoadingMore || _tenorNextPos == null) return;
    if (!_tenorScrollController.hasClients) return;
    final threshold = _tenorScrollController.position.maxScrollExtent - 300;
    if (_tenorScrollController.position.pixels >= threshold) {
      _loadMoreTenorGifs();
    }
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
      final installed = await _stickerService.getInstalledPackIds();
      if (!mounted) return;
      setState(() {
        _stickers = stickers;
        _installedPackIds = installed;
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

  Future<void> _refreshLocalStickers() async {
    final stickers = await _stickerService.getLocalStickers();
    final installed = await _stickerService.getInstalledPackIds();
    if (!mounted) return;
    setState(() {
      _stickers = stickers;
      _installedPackIds = installed;
      if (_selectedPackId != 'all' &&
          !_installedPackIds.contains(_selectedPackId)) {
        _selectedPackId = 'all';
      }
    });
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

  Future<void> _loadGiphyGifs({String? query, bool append = false}) async {
    if (append && _gifLoadingMore) return;
    if (!append) {
      setState(() {
        _gifLoading = true;
        _gifError = null;
        _gifOffset = 0;
        _gifHasMore = true;
      });
    } else {
      setState(() => _gifLoadingMore = true);
    }

    try {
      final trimmedQuery = query?.trim();
      final key = AppConfig.giphyApiKey.trim();
      final items = key.isNotEmpty
          ? await _fetchGiphyGifsDirect(
              key: key,
              query: trimmedQuery,
              offset: _gifOffset,
            )
          : await _fetchGiphyGifsViaProxy(
              query: trimmedQuery,
              offset: _gifOffset,
            );
      if (!mounted) return;
      setState(() {
        if (append) {
          _giphyGifResults.addAll(items);
          _gifLoadingMore = false;
        } else {
          _giphyGifResults = items;
          _gifLoading = false;
        }
        _gifOffset += items.length;
        if (items.length < 25) {
          _gifHasMore = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _gifError = 'Failed to load GIFs';
        _gifLoading = false;
        _gifLoadingMore = false;
      });
    }
  }

  Future<List<GiphyGifItem>> _fetchGiphyGifsDirect({
    required String key,
    String? query,
    int offset = 0,
  }) async {
    final endpoint = (query == null || query.trim().isEmpty)
        ? 'https://api.giphy.com/v1/gifs/trending'
        : 'https://api.giphy.com/v1/gifs/search';
    final params = {
      'api_key': key,
      'limit': '25',
      'offset': '$offset',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    };
    final uri = Uri.parse(endpoint).replace(queryParameters: params);
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('GIPHY error ${res.statusCode}');
    }
    return _parseGiphyGifItems(res.body);
  }

  Future<List<GiphyGifItem>> _fetchGiphyGifsViaProxy({
    String? query,
    int offset = 0,
  }) async {
    final token = await _getIdToken();
    final headers = {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final endpoint = (query == null || query.trim().isEmpty)
        ? '/api/stickers/giphy/trending'
        : '/api/stickers/giphy/search';
    final uris = _backendUris(endpoint, {
      'limit': '25',
      'offset': '$offset',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    });

    for (final uri in uris) {
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) continue;
      return _parseGiphyGifItems(res.body);
    }
    return [];
  }

  List<GiphyGifItem> _parseGiphyGifItems(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final data = (decoded['data'] as List?) ?? [];
    return data
        .map((item) {
          final images = item['images'] as Map<String, dynamic>? ?? {};
          final fixed = images['fixed_width'] as Map<String, dynamic>? ?? {};
          final original = images['original'] as Map<String, dynamic>? ?? {};
          final fixedUrl = fixed['url']?.toString() ?? '';
          final origUrl = original['url']?.toString() ?? '';
          final width = double.tryParse(fixed['width']?.toString() ?? '') ?? 1;
          final height =
              double.tryParse(fixed['height']?.toString() ?? '') ?? 1;
          return GiphyGifItem(
            id: item['id']?.toString() ?? '',
            title: item['title']?.toString() ?? '',
            fixedWidthUrl: fixedUrl,
            originalUrl: origUrl.isEmpty ? fixedUrl : origUrl,
            aspectRatio: width / (height == 0 ? 1 : height),
          );
        })
        .where((item) => item.fixedWidthUrl.isNotEmpty)
        .toList();
  }

  Iterable<Uri> _backendUris(
    String endpoint,
    Map<String, String> params,
  ) sync* {
    final normalized = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    for (final base in AppConfig.apiBaseUrls) {
      final uri = Uri.parse('$base$normalized');
      yield uri.replace(queryParameters: params);
    }
  }

  Future<String?> _getIdToken() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    return user?.getIdToken();
  }

  Future<(List<TenorGifItem>, String?)> _fetchTenorMemesPage({
    int limit = 20,
    String? pos,
  }) async {
    try {
      final queryParams = [
        'q=meme',
        'key=${AppConfig.tenorApiKey}',
        'limit=$limit',
        'media_filter=gif',
        if (pos != null && pos.isNotEmpty) 'pos=$pos',
      ].join('&');
      final v2Uri = Uri.parse(
        'https://tenor.googleapis.com/v2/search?$queryParams',
      );
      final res = await http.get(v2Uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final results = (decoded['results'] as List? ?? [])
            .map((e) => TenorGifItem.fromJson(e as Map<String, dynamic>))
            .where((e) => e.url.isNotEmpty)
            .toList();
        final next = decoded['next']?.toString();
        return (results, next);
      }
    } catch (_) {
      // Fall back below.
    }
    try {
      final legacyUri = Uri.parse(
        'https://g.tenor.com/v1/search?q=meme&key=LIVDSRZULELA&limit=$limit',
      );
      final res = await http
          .get(legacyUri)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return (<TenorGifItem>[], null);
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (decoded['results'] as List?) ?? [];
      final items = <TenorGifItem>[];
      for (final raw in results) {
        if (raw is! Map) continue;
        final mediaList = (raw['media'] as List?) ?? const [];
        if (mediaList.isEmpty) continue;
        final media = mediaList.first as Map? ?? const {};
        final gif =
            (media['gif'] ?? media['mediumgif'] ?? media['tinygif']) as Map? ??
            const {};
        final url = gif['url']?.toString() ?? '';
        final dims = (gif['dims'] as List?) ?? const [0, 0];
        if (url.isEmpty) continue;
        final width = dims.isNotEmpty ? int.tryParse('${dims.first}') ?? 1 : 1;
        final height = dims.length > 1 ? int.tryParse('${dims[1]}') ?? 1 : 1;
        items.add(TenorGifItem(url: url, width: width, height: height));
      }
      return (items, null);
    } catch (_) {
      return (<TenorGifItem>[], null);
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
      final imgflipDecoded =
          jsonDecode(imgflipRes.body) as Map<String, dynamic>;
      final templates = (imgflipDecoded['data']?['memes'] as List? ?? [])
          .map((e) => ImgflipTemplate.fromJson(e as Map<String, dynamic>))
          .toList();

      final tenorPage = await _fetchTenorMemesPage(limit: 20);

      if (!mounted) return;
      setState(() {
        _imgflipTemplates = templates;
        _tenorGifs = tenorPage.$1;
        _tenorNextPos = tenorPage.$2;
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

  Future<void> _loadMoreTenorGifs() async {
    if (_tenorLoadingMore || _tenorNextPos == null) return;
    setState(() => _tenorLoadingMore = true);
    try {
      final page = await _fetchTenorMemesPage(limit: 20, pos: _tenorNextPos);
      if (!mounted) return;
      setState(() {
        _tenorGifs.addAll(page.$1);
        _tenorNextPos = page.$2;
        _tenorLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _tenorLoadingMore = false);
    }
  }

  List<File> get _filteredLocalStickers {
    final query = _stickerQuery.trim().toLowerCase();
    final selectedPackId = _selectedPackId.trim();
    final filteredByPack = selectedPackId.isEmpty || selectedPackId == 'all'
        ? _stickers
        : _stickers
              .where((file) => _packIdForFile(file) == selectedPackId)
              .toList();

    return query.isEmpty
        ? filteredByPack
        : filteredByPack
              .where(
                (file) =>
                    file.path.toLowerCase().contains(query) ||
                    file.uri.pathSegments.last.toLowerCase().contains(query),
              )
              .toList();
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

  Future<void> _openStickerEditorFromFile(
    File sourceFile, {
    bool startWithMemeLayout = false,
    String? sourceLabel,
  }) async {
    final navigator = Navigator.of(context);
    final savedFile = await navigator.push<File>(
      MaterialPageRoute(
        builder: (_) => StickerEditorScreen(
          sourceFile: sourceFile,
          startWithMemeLayout: startWithMemeLayout,
          sourceLabel: sourceLabel,
        ),
      ),
    );
    if (!mounted) return;
    if (savedFile != null) {
      // Deliver the sticker — do NOT call navigator.pop() here.
      // The sticker sheet is already dismissed by the caller after
      // onStickerSelected fires; an extra pop would eject the chatroom.
      widget.onStickerSelected(savedFile);
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  List<StickerPack> get _featuredStickerPacks => StickerService.availablePacks
      .where((pack) => pack.stickerUrls.isNotEmpty)
      .toList(growable: false);

  List<StickerPack> get _installedStickerPacks => _featuredStickerPacks
      .where((pack) => _installedPackIds.contains(pack.id))
      .toList(growable: false);

  String _assetPathFromStickerUrl(String url) =>
      url.replaceFirst('asset://', '');

  String? _packIdForFile(File file) {
    final segments = file.uri.pathSegments;
    for (final segment in segments) {
      if (!segment.startsWith('pack_')) continue;
      final packId = segment.substring(5).trim();
      if (packId.isNotEmpty) return packId;
    }
    return null;
  }

  String _packDescription(StickerPack pack) {
    switch (pack.id) {
      case 'animated_reaction_loop':
        return 'Clean emoji-style reactions for everyday replies.';
      case 'animated_study_loop':
        return 'Books, targets, and focus stickers for study mode.';
      case 'animated_celebration_loop':
        return 'Confetti, trophies, and full-on victory energy.';
      case 'animated_moods_loop':
        return 'Expressive moods for late-night student life moments.';
      default:
        return '${pack.stickerUrls.length} animated stickers';
    }
  }

  Widget _buildPackPreviewRow(StickerPack pack) {
    final previewUrls = pack.stickerUrls.take(4).toList(growable: false);
    return SizedBox(
      height: 52,
      child: Row(
        children: previewUrls.asMap().entries.map((entry) {
          final isLast = entry.key == previewUrls.length - 1;
          return Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                _assetPathFromStickerUrl(entry.value),
                width: 52,
                height: 52,
                fit: BoxFit.cover,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _showStickerPackSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final packs = _featuredStickerPacks;
    final installing = <String>{};
    final sheetInstalledPackIds = Set<String>.from(_installedPackIds);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
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
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
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
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: packs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final pack = packs[index];
                        final packId = pack.id;
                        final isInstalled = sheetInstalledPackIds.contains(
                          packId,
                        );
                        final isInstalling = installing.contains(packId);

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.black12,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPackPreviewRow(pack),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pack.name,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _packDescription(pack),
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            height: 1.35,
                                            color: isDark
                                                ? Colors.white60
                                                : Colors.black54,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${pack.stickerUrls.length} animated stickers',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (isInstalled)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(
                                          alpha: 0.14,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_circle_rounded,
                                            size: 16,
                                            color: Colors.green.shade400,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Added',
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w700,
                                              color: Colors.green.shade400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (isInstalling)
                                    SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.primary,
                                      ),
                                    )
                                  else
                                    ElevatedButton(
                                      onPressed: () async {
                                        setSheetState(
                                          () => installing.add(packId),
                                        );
                                        final installedCount =
                                            await _stickerService.installPack(
                                              pack,
                                            );
                                        await _refreshLocalStickers();
                                        if (!mounted) return;
                                        setSheetState(() {
                                          installing.remove(packId);
                                          if (installedCount > 0) {
                                            sheetInstalledPackIds.add(packId);
                                          }
                                        });
                                        if (installedCount > 0) {
                                          setState(
                                            () => _selectedPackId = packId,
                                          );
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '${pack.name} added with $installedCount stickers.',
                                              ),
                                            ),
                                          );
                                        } else if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Could not add ${pack.name}. Please try again.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                      ),
                                      child: const Text('Add Pack'),
                                    ),
                                ],
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
          },
        );
      },
    );
  }

  Future<void> _createStickerFromImage() async {
    final file = await _stickerService.importSticker(enableEditing: true);
    if (!mounted || file == null) return;
    await _openStickerEditorFromFile(file, sourceLabel: 'Custom sticker');
  }

  Future<void> _openMemeEditor(ImgflipTemplate template) async {
    final file = await _downloadToTempFile(template.url, 'imgflip_template');
    if (file == null) return;
    await _openStickerEditorFromFile(
      file,
      startWithMemeLayout: true,
      sourceLabel: template.name,
    );
  }

  Widget _buildSegmentedTabs(bool isDark) {
    final labels = ['Stickers', 'GIFs', 'Memes'];
    final animation = _tabController.animation;
    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentCount = labels.length;
        final segmentWidth = (constraints.maxWidth - 6) / segmentCount;

        Widget childForValue(double value) {
          final clampedValue = value.clamp(0.0, (segmentCount - 1).toDouble());
          return Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.black12,
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.all(3),
            child: Stack(
              children: [
                Positioned(
                  left: segmentWidth * clampedValue,
                  top: 0,
                  bottom: 0,
                  width: segmentWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                Row(
                  children: labels.asMap().entries.map((entry) {
                    final selected = _tabController.index == entry.key;
                    return Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _tabController.animateTo(entry.key),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 160),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : (isDark
                                          ? Colors.white54
                                          : Colors.black45),
                              ),
                              child: Text(
                                entry.value,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }

        if (animation == null) {
          return childForValue(_tabController.index.toDouble());
        }
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => childForValue(animation.value),
        );
      },
    );
  }

  Widget _buildSearchBar({
    required TextEditingController controller,
    required bool isDark,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
        prefixIcon: Icon(
          Icons.search,
          size: 18,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        isDense: true,
      ),
      onChanged: onChanged,
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

  Widget _buildInstalledPackChips(bool isDark) {
    final packs = _installedStickerPacks;
    if (packs.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedColor = AppTheme.primary;
    final idleColor = isDark
        ? Colors.white10
        : Colors.black.withValues(alpha: 0.05);

    Widget chip({
      required String id,
      required String label,
      required bool selected,
    }) {
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _selectedPackId = id);
        },
        selectedColor: selectedColor.withValues(alpha: isDark ? 0.22 : 0.12),
        backgroundColor: idleColor,
        side: BorderSide(
          color: selected
              ? selectedColor.withValues(alpha: 0.38)
              : (isDark ? Colors.white12 : Colors.black12),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: selected
              ? selectedColor
              : (isDark ? Colors.white70 : Colors.black87),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        visualDensity: VisualDensity.compact,
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip(
              id: 'all',
              label: 'All Packs',
              selected: _selectedPackId == 'all',
            ),
            ...packs.map(
              (pack) => chip(
                id: pack.id,
                label: pack.name,
                selected: _selectedPackId == pack.id,
              ),
            ),
          ],
        ),
      ),
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
      controller: _gifScrollController,
      padding: const EdgeInsets.only(top: 8),
      crossAxisCount: 2,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      itemCount: _giphyGifResults.length + (_gifLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _giphyGifResults.length) {
          return Center(
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? Colors.white70 : Colors.black45,
              ),
            ),
          );
        }
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

    return ListView(
      controller: _tenorScrollController,
      children: [
        const SizedBox(height: 10),
        if (_imgflipTemplates.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Templates',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _imgflipTemplates.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
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
        ],
        const SizedBox(height: 12),
        if (_tenorGifs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Trending Memes',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
        if (_tenorGifs.isNotEmpty) const SizedBox(height: 8),
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
                final file = await _downloadToTempFile(item.url, 'tenor_meme');
                if (!mounted || file == null) return;
                await _openStickerEditorFromFile(
                  file,
                  startWithMemeLayout: true,
                  sourceLabel: 'Trending meme',
                );
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
        if (_tenorLoadingMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Colors.white70 : Colors.black45,
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
      ],
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
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _createStickerFromImage,
                                icon: const Icon(
                                  Icons.add_photo_alternate_rounded,
                                ),
                                label: const Text('Create Sticker'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  side: BorderSide(
                                    color: AppTheme.primary.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _showStickerPackSheet,
                                icon: const Icon(
                                  Icons.collections_bookmark_rounded,
                                ),
                                label: const Text('Get More Stickers'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildInstalledPackChips(isDark),
                        if (_installedStickerPacks.isNotEmpty)
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
