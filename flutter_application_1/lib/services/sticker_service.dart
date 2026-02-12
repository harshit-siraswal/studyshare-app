import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

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

  /// Returns true when background removal is available.
  bool get canRemoveBackground => AppConfig.removeBgApiKey.isNotEmpty;

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
    final apiKey = AppConfig.removeBgApiKey;
    if (apiKey.isEmpty) {
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
              headers: {'X-Api-Key': apiKey},
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
