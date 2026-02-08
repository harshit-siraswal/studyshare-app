import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class StickerService {
  static const String _stickerDirName = 'stickers';

  /// Get the directory where stickers are stored
  Future<Directory> getStickerDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final stickerDir = Directory(path.join(appDocDir.path, _stickerDirName));
    if (!await stickerDir.exists()) {
      await stickerDir.create(recursive: true);
    }
    return stickerDir;
  }

  /// Get list of local sticker files
  Future<List<File>> getLocalStickers() async {
    try {
      final dir = await getStickerDirectory();
      
      // Async list
      final entities = await dir.list().toList();
      
      final stickerFiles = <File>[];
      final fileData = <File, DateTime>{};
      
      final futures = <Future<void>>[];

      for (var entity in entities) {
        if (entity is File) {
           final ext = path.extension(entity.path).toLowerCase();
           if (['.png', '.jpg', '.jpeg', '.webp', '.gif'].contains(ext)) {
             futures.add(() async {
               try {
                 final stat = await entity.stat();
                 stickerFiles.add(entity);
                 fileData[entity] = stat.modified;
               } catch (e) {
                 stickerFiles.add(entity);
                 fileData[entity] = DateTime.fromMillisecondsSinceEpoch(0);
               }
             }());
           }
        }
      }
      
      await Future.wait(futures);

      // Sort by modified date (newest first)
      stickerFiles.sort((a, b) {
        final dateA = fileData[a] ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = fileData[b] ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });
      
      return stickerFiles;
    } catch (e) {
      debugPrint('Error loading local stickers: $e');
      return [];
    }
  }

  /// Import a sticker from picking a file
  Future<File?> importSticker() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result != null && result.files.single.path != null) {
        final sourceFile = File(result.files.single.path!);
        final dir = await getStickerDirectory();
        
        // Create unique name
        final filename = 'sticker_${DateTime.now().millisecondsSinceEpoch}${path.extension(sourceFile.path)}';
        final destPath = path.join(dir.path, filename);
        
        // Copy file
        final savedFile = await sourceFile.copy(destPath);
        return savedFile;
      }
      return null;
    } catch (e) {
      debugPrint('Error importing sticker: $e');
      return null;
    }
  }

  /// Delete a sticker
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
}
