import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

// ─── Giphy Models ────────────────────────────────────────────────────────────

class GiphyStickerItem {
  final String id;
  final String title;
  final String previewUrl; // fixed_width_small gif / downsampled
  final String originalUrl; // original mp4 or gif url to save

  const GiphyStickerItem({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.originalUrl,
  });

  factory GiphyStickerItem.fromJson(Map<String, dynamic> j) {
    final images = j['images'] as Map<String, dynamic>? ?? {};
    // Prefer a static webp/gif at fixed_width_small; fallback to downsized
    final small = images['fixed_width_small'] as Map<String, dynamic>? ?? {};
    final downsized = images['downsized'] as Map<String, dynamic>? ?? {};
    final original = images['original'] as Map<String, dynamic>? ?? {};
    return GiphyStickerItem(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? 'Sticker',
      previewUrl: (small['url'] ?? downsized['url'] ?? original['url'] ?? '')
          .toString(),
      originalUrl: (original['url'] ?? downsized['url'] ?? small['url'] ?? '')
          .toString(),
    );
  }
}

class GiphyStickerCategory {
  final String name;
  final String encodedSearchTerm;
  final String previewGifUrl;

  const GiphyStickerCategory({
    required this.name,
    required this.encodedSearchTerm,
    required this.previewGifUrl,
  });

  factory GiphyStickerCategory.fromJson(Map<String, dynamic> j) {
    return GiphyStickerCategory(
      name: j['name']?.toString() ?? 'Unknown',
      encodedSearchTerm:
          j['name_encoded']?.toString() ?? j['name']?.toString() ?? '',
      previewGifUrl:
          ((j['gif'] as Map<String, dynamic>?)?['images']
                  as Map<String, dynamic>?)?['fixed_width_small']?['url']
              ?.toString() ??
          '',
    );
  }
}

class StickerPack {
  final String id;
  final String name;
  final String author;
  final String source;
  final List<String> stickerUrls;

  const StickerPack({
    required this.id,
    required this.name,
    required this.author,
    required this.source,
    required this.stickerUrls,
  });

  String? get previewUrl => stickerUrls.isNotEmpty ? stickerUrls.first : null;
}

class StickerPackImportResult {
  final String packId;
  final String packName;
  final int importedCount;
  final int skippedCount;

  const StickerPackImportResult({
    required this.packId,
    required this.packName,
    required this.importedCount,
    required this.skippedCount,
  });
}

class StickerService {
  static const String _stickerDirName = 'stickers';
  static const String _installedPacksKey = 'installed_sticker_packs_v1';
  static const Set<String> _supportedStickerExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
  };
  static const List<Map<String, String>> _removeBgQualityProfiles = [
    {'size': '4k', 'format': 'png'},
    {'size': 'auto', 'format': 'png'},
  ];
  static Future<void>? _capabilityFetchFuture;
  static bool _remoteCapabilitiesLoaded = false;
  static bool _remoteGiphyEnabled = false;
  static bool _remoteRemoveBgEnabled = false;

  static const List<StickerPack> availablePacks = [
    StickerPack(
      id: 'study_essentials',
      name: 'Study Essentials',
      author: 'Noto Emoji',
      source: 'github.com/googlefonts/noto-emoji',
      stickerUrls: [
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f4da.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f4d6.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f4dd.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u270f.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f4a1.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f3af.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f4c5.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f393.png',
      ],
    ),
    StickerPack(
      id: 'reaction_burst',
      name: 'Reaction Burst',
      author: 'Noto Emoji',
      source: 'github.com/googlefonts/noto-emoji',
      stickerUrls: [
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f44d.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f44f.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f525.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f389.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f60e.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f92f.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f4af.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f64c.png',
      ],
    ),
    StickerPack(
      id: 'cute_vibes',
      name: 'Cute Vibes',
      author: 'Noto Emoji',
      source: 'github.com/googlefonts/noto-emoji',
      stickerUrls: [
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f970.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f60d.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f63b.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f917.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f496.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f308.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f31f.png',
        'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u1f31a.png',
      ],
    ),
  ];

  // ─── Giphy Sticker API ────────────────────────────────────────────────────

  static const String _giphyBase = 'https://api.giphy.com/v1';

  String get _giphyKey => AppConfig.giphyApiKey;
  String get _removeBgKey => AppConfig.removeBgApiKey;

  bool get hasGiphy => _giphyKey.isNotEmpty || _remoteGiphyEnabled;

  /// Returns true when background removal is available.
  bool get canRemoveBackground =>
      _removeBgKey.isNotEmpty || _remoteRemoveBgEnabled;

  Future<void> warmUpCapabilities() async {
    await _ensureCapabilities();
  }

  Future<String?> _getIdToken() async {
    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (e) {
      debugPrint('Failed to get Firebase token for sticker APIs: $e');
      return null;
    }
  }

  Uri _backendUri(String path, [Map<String, String>? queryParameters]) {
    final normalizedBase = AppConfig.apiUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse(
      '$normalizedBase$path',
    ).replace(queryParameters: queryParameters);
  }

  Future<void> _ensureCapabilities() async {
    if (_giphyKey.isNotEmpty && _removeBgKey.isNotEmpty) {
      _remoteCapabilitiesLoaded = true;
      _remoteGiphyEnabled = true;
      _remoteRemoveBgEnabled = true;
      return;
    }

    if (_remoteCapabilitiesLoaded) return;
    if (_capabilityFetchFuture != null) {
      await _capabilityFetchFuture;
      return;
    }

    _capabilityFetchFuture = _fetchCapabilitiesFromBackend();
    try {
      await _capabilityFetchFuture;
    } finally {
      _capabilityFetchFuture = null;
    }
  }

  Future<void> _fetchCapabilitiesFromBackend() async {
    try {
      final token = await _getIdToken();
      final response = await http
          .get(
            _backendUri('/api/stickers/config'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final parsed = jsonDecode(response.body) as Map<String, dynamic>;
        _remoteGiphyEnabled = parsed['giphyEnabled'] == true;
        _remoteRemoveBgEnabled = parsed['removeBgEnabled'] == true;
      } else {
        _remoteGiphyEnabled = false;
        _remoteRemoveBgEnabled = false;
      }
    } catch (e) {
      debugPrint('Sticker capability check failed: $e');
      _remoteGiphyEnabled = false;
      _remoteRemoveBgEnabled = false;
    } finally {
      _remoteCapabilitiesLoaded = true;
    }
  }

  /// Fetch trending stickers or search results from Giphy.
  Future<List<GiphyStickerItem>> fetchGiphyStickers({
    String? query,
    int limit = 24,
    int offset = 0,
    String rating = 'g',
  }) async {
    final trimmedQuery = query?.trim();
    final hasDirectKey = _giphyKey.isNotEmpty;

    Uri uri;
    Map<String, String>? headers;

    if (hasDirectKey) {
      final endpoint = trimmedQuery != null && trimmedQuery.isNotEmpty
          ? '$_giphyBase/stickers/search'
          : '$_giphyBase/stickers/trending';
      uri = Uri.parse(endpoint).replace(
        queryParameters: {
          'api_key': _giphyKey,
          'limit': limit.toString(),
          'offset': offset.toString(),
          'rating': rating,
          if (trimmedQuery != null && trimmedQuery.isNotEmpty)
            'q': trimmedQuery,
        },
      );
      headers = null;
    } else {
      await _ensureCapabilities();
      if (!_remoteGiphyEnabled) return [];
      final token = await _getIdToken();
      uri = _backendUri(
        trimmedQuery != null && trimmedQuery.isNotEmpty
            ? '/api/stickers/giphy/search'
            : '/api/stickers/giphy/trending',
        {
          'limit': limit.toString(),
          'offset': offset.toString(),
          'rating': rating,
          if (trimmedQuery != null && trimmedQuery.isNotEmpty)
            'q': trimmedQuery,
        },
      );
      headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
    }

    try {
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final decoded = jsonDecode(res.body) as Map<String, dynamic>?;
      final data = (decoded?['data'] as List?) ?? [];
      return data
          .map((e) => GiphyStickerItem.fromJson(e as Map<String, dynamic>))
          .where((s) => s.previewUrl.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[Giphy] fetchGiphyStickers error: $e');
      return [];
    }
  }

  /// Fetch sticker categories from Giphy.
  Future<List<GiphyStickerCategory>> fetchGiphyCategories() async {
    if (_giphyKey.isEmpty) {
      await _ensureCapabilities();
      if (!_remoteGiphyEnabled) return [];
      // Categories endpoint is optional in proxy mode for now.
      return [];
    }
    final uri = Uri.parse(
      '$_giphyBase/stickers/categories',
    ).replace(queryParameters: {'api_key': _giphyKey});
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final decoded = jsonDecode(res.body) as Map<String, dynamic>?;
      final data = (decoded?['data'] as List?) ?? [];
      return data
          .map((e) => GiphyStickerCategory.fromJson(e as Map<String, dynamic>))
          .where((c) => c.name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[Giphy] fetchGiphyCategories error: $e');
      return [];
    }
  }

  /// Download a Giphy sticker and save it to the local sticker directory.
  Future<File?> saveGiphySticker(GiphyStickerItem sticker) async {
    try {
      final res = await http
          .get(Uri.parse(sticker.originalUrl))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final dir = await getStickerDirectory();
      final ext = sticker.originalUrl.contains('.webp')
          ? '.webp'
          : sticker.originalUrl.contains('.gif')
          ? '.gif'
          : '.gif';
      final filename = 'giphy_${sticker.id}$ext';
      final file = File(path.join(dir.path, filename));
      if (await file.exists()) return file; // already saved
      await file.writeAsBytes(res.bodyBytes, flush: true);
      return file;
    } catch (e) {
      debugPrint('[Giphy] saveGiphySticker error: $e');
      return null;
    }
  }

  Future<Directory> getStickerDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final stickerDir = Directory(path.join(appDocDir.path, _stickerDirName));
    if (!await stickerDir.exists()) {
      await stickerDir.create(recursive: true);
    }
    return stickerDir;
  }

  /// Deletes legacy sticker packs from disk and preferences.
  Future<void> purgeLegacyPacks() async {
    const legacyIds = {'study_pack', 'express_pack'};
    try {
      final dir = await getStickerDirectory();
      for (final legacyId in legacyIds) {
        final packDir = Directory(path.join(dir.path, 'pack_$legacyId'));
        if (await packDir.exists()) {
          await packDir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('Failed to purge legacy packs: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final current =
        prefs.getStringList(_installedPacksKey)?.toSet() ?? <String>{};
    current.removeAll(legacyIds);
    await prefs.setStringList(_installedPacksKey, current.toList());
  }

  Future<List<File>> getLocalStickers() async {
    try {
      final dir = await getStickerDirectory();
      final entities = await dir.list(recursive: true).toList();

      final futures = <Future<({File file, DateTime modified})?>>[];

      for (final entity in entities) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (_supportedStickerExtensions.contains(ext)) {
            futures.add(() async {
              try {
                final stat = await entity.stat();
                return (file: entity, modified: stat.modified);
              } catch (_) {
                return (
                  file: entity,
                  modified: DateTime.fromMillisecondsSinceEpoch(0),
                );
              }
            }());
          }
        }
      }

      final results = await Future.wait(futures);

      final stickerFiles = <File>[];
      final fileData = <File, DateTime>{};

      for (final result in results) {
        if (result != null) {
          stickerFiles.add(result.file);
          fileData[result.file] = result.modified;
        }
      }

      stickerFiles.sort(
        (a, b) =>
            (fileData[b] ?? DateTime(0)).compareTo(fileData[a] ?? DateTime(0)),
      );
      return stickerFiles;
    } catch (e) {
      debugPrint('Error loading local stickers: $e');
      return [];
    }
  }

  Future<File?> importSticker({bool enableEditing = true}) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.single.path == null) return null;

      var sourcePath = result.files.single.path!;
      if (enableEditing && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final cropped = await ImageCropper().cropImage(
          sourcePath: sourcePath,
          compressFormat: ImageCompressFormat.png,
          compressQuality: 100,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Create Sticker',
              lockAspectRatio: false,
              hideBottomControls: false,
            ),
            IOSUiSettings(
              title: 'Create Sticker',
              aspectRatioLockEnabled: false,
            ),
          ],
        );
        if (cropped != null) {
          sourcePath = cropped.path;
        }
      }

      final sourceFile = File(sourcePath);
      final ext = path.extension(sourceFile.path).toLowerCase().isEmpty
          ? '.png'
          : path.extension(sourceFile.path).toLowerCase();
      final dir = await getStickerDirectory();
      final filename = 'custom_${DateTime.now().millisecondsSinceEpoch}$ext';
      final destinationPath = path.join(dir.path, filename);
      return await sourceFile.copy(destinationPath);
    } catch (e) {
      debugPrint('Error importing sticker: $e');
      return null;
    }
  }

  /// Removes the background from an image using remove.bg.
  Future<File?> removeBackground(File sourceFile) async {
    if (_removeBgKey.isEmpty) {
      await _ensureCapabilities();
      if (_remoteRemoveBgEnabled) {
        return _removeBackgroundViaBackend(sourceFile);
      }
      throw Exception('REMOVE_BG_API_KEY not set');
    }

    Object? lastError;

    try {
      final sourceBytes = await sourceFile.readAsBytes();
      final fileName = path.basename(sourceFile.path);
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 40),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      for (final profile in _removeBgQualityProfiles) {
        try {
          final formData = FormData.fromMap({
            'image_file': MultipartFile.fromBytes(
              sourceBytes,
              filename: fileName,
            ),
            ...profile,
          });

          final response = await dio.post<List<int>>(
            'https://api.remove.bg/v1.0/removebg',
            data: formData,
            options: Options(
              responseType: ResponseType.bytes,
              headers: {'X-Api-Key': _removeBgKey},
            ),
          );

          final bytes = response.data;
          if (bytes == null || bytes.isEmpty) {
            continue;
          }

          final tempDir = await getTemporaryDirectory();
          final outputPath = path.join(
            tempDir.path,
            'mss_removebg_${DateTime.now().millisecondsSinceEpoch}.png',
          );
          final outputFile = File(outputPath);
          await outputFile.writeAsBytes(bytes, flush: true);
          return outputFile;
        } catch (e) {
          lastError = e;
          if (!_shouldRetryRemoveBg(e)) {
            rethrow;
          }
        }
      }
    } catch (e) {
      debugPrint('Background removal failed: $e');
      rethrow;
    }

    if (lastError != null) {
      throw Exception(_readableRemoveBgError(lastError));
    }
    return null;
  }

  Future<File?> _removeBackgroundViaBackend(File sourceFile) async {
    final token = await _getIdToken();
    final request = http.MultipartRequest(
      'POST',
      _backendUri('/api/stickers/remove-bg'),
    );

    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields['size'] = 'auto';
    request.fields['format'] = 'png';
    request.files.add(
      await http.MultipartFile.fromPath('image', sourceFile.path),
    );

    final response = await request.send().timeout(const Duration(seconds: 50));
    final bytes = await response.stream.toBytes();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = utf8.decode(bytes, allowMalformed: true).trim();
      throw Exception(
        errorBody.isNotEmpty
            ? 'Background removal failed: $errorBody'
            : 'Background removal failed (${response.statusCode})',
      );
    }

    if (bytes.isEmpty) {
      throw Exception('Background removal failed: empty output');
    }

    final tempDir = await getTemporaryDirectory();
    final outputPath = path.join(
      tempDir.path,
      'mss_removebg_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(bytes, flush: true);
    return outputFile;
  }

  bool _shouldRetryRemoveBg(Object error) {
    if (error is! DioException) return false;
    final statusCode = error.response?.statusCode ?? 0;
    // Don't retry on auth errors or rate limits
    if (statusCode == 401 || statusCode == 403 || statusCode == 429) {
      return false;
    }
    // Retry with lower quality profile on client errors (e.g., plan limitations)
    // or transient server errors
    return (statusCode >= 400 && statusCode < 500) || statusCode >= 500;
  }

  String _readableRemoveBgError(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final responseData = error.response?.data;
      if (responseData is List<int>) {
        try {
          final decoded = utf8.decode(responseData);
          if (decoded.trim().isNotEmpty) {
            return 'remove.bg request failed (${statusCode ?? 'n/a'}): $decoded';
          }
        } catch (_) {
          // Keep generic error text if decoding fails.
        }
      }
      if (responseData is String && responseData.trim().isNotEmpty) {
        return 'remove.bg request failed (${statusCode ?? 'n/a'}): $responseData';
      }
      return 'remove.bg request failed (${statusCode ?? 'n/a'})';
    }
    return error.toString();
  }

  Future<Set<String>> getInstalledPackIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_installedPacksKey) ?? const [];
    return list.toSet();
  }

  Future<int> installPack(StickerPack pack) async {
    final dir = await getStickerDirectory();
    final packDir = Directory(path.join(dir.path, 'pack_${pack.id}'));
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );

    // Create parallel download futures
    final downloadFutures = pack.stickerUrls.asMap().entries.map((entry) async {
      final index = entry.key;
      final url = entry.value;
      try {
        final response = await dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = response.data;
        if (bytes == null || bytes.isEmpty) return false;

        final ext = _safeExtensionFromUrl(url);
        final file = File(path.join(packDir.path, '${pack.id}_$index$ext'));
        await file.writeAsBytes(bytes, flush: true);
        return true;
      } catch (e) {
        debugPrint('Sticker download failed for $url: $e');
        return false;
      }
    }).toList();

    // Await all downloads and count successes
    final results = await Future.wait(downloadFutures);
    final installedCount = results.where((success) => success).length;

    if (installedCount > 0) {
      final prefs = await SharedPreferences.getInstance();
      final current =
          prefs.getStringList(_installedPacksKey)?.toSet() ?? <String>{};
      current.add(pack.id);
      await prefs.setStringList(_installedPacksKey, current.toList());
    }

    return installedCount;
  }

  Future<void> uninstallPack(String packId) async {
    try {
      final dir = await getStickerDirectory();
      final packDir = Directory(path.join(dir.path, 'pack_$packId'));
      if (await packDir.exists()) {
        await packDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error deleting pack directory: $e');
    }

    // Always update preferences to allow re-download
    final prefs = await SharedPreferences.getInstance();
    final current =
        prefs.getStringList(_installedPacksKey)?.toSet() ?? <String>{};
    current.remove(packId);
    await prefs.setStringList(_installedPacksKey, current.toList());
  }

  bool isStickerPath(String pathValue) {
    final extension = path.extension(pathValue).toLowerCase();
    return _supportedStickerExtensions.contains(extension);
  }

  Future<StickerPackImportResult> importPackFromPaths({
    required List<String> paths,
    String? packName,
  }) async {
    final validPaths = <String>[];
    for (final pathValue in paths) {
      if (pathValue.trim().isEmpty) continue;
      if (isStickerPath(pathValue)) {
        validPaths.add(pathValue);
      }
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final generatedId = 'shared_$timestamp';
    final label = (packName == null || packName.trim().isEmpty)
        ? 'Imported Pack'
        : packName.trim();
    final dir = await getStickerDirectory();
    final packDir = Directory(path.join(dir.path, 'pack_$generatedId'));
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }

    var importedCount = 0;
    var skippedCount = 0;

    for (int i = 0; i < validPaths.length; i++) {
      try {
        final source = File(validPaths[i]);
        if (!await source.exists()) {
          skippedCount++;
          continue;
        }

        final ext = path.extension(source.path).toLowerCase();
        if (!_supportedStickerExtensions.contains(ext)) {
          skippedCount++;
          continue;
        }

        final filename = '${generatedId}_$i$ext';
        final destination = path.join(packDir.path, filename);
        await source.copy(destination);
        importedCount++;
      } catch (_) {
        skippedCount++;
      }
    }

    if (importedCount == 0) {
      if (await packDir.exists()) {
        await packDir.delete(recursive: true);
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final current =
          prefs.getStringList(_installedPacksKey)?.toSet() ?? <String>{};
      current.add(generatedId);
      await prefs.setStringList(_installedPacksKey, current.toList());
    }

    return StickerPackImportResult(
      packId: generatedId,
      packName: label,
      importedCount: importedCount,
      skippedCount: skippedCount,
    );
  }

  Future<bool> deleteSticker(File sticker) async {
    try {
      final dir = await getStickerDirectory();
      final canonicalStickerPath = path.canonicalize(sticker.path);
      final canonicalDirPath = path.canonicalize(dir.path);
      if (!path.isWithin(canonicalDirPath, canonicalStickerPath)) {
        debugPrint('Attempted to delete file outside stickers directory');
        return false;
      }
      if (await sticker.exists()) {
        await sticker.delete();
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting sticker: $e');
      return false;
    }
  }

  String _safeExtensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final ext = path.extension(uri?.path ?? '').toLowerCase();
    if (_supportedStickerExtensions.contains(ext)) {
      return ext;
    }
    return '.png';
  }
}
