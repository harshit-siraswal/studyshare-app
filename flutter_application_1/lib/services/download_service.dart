import 'dart:io';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  late Box _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox('offline_resources');
    _initialized = true;
  }

  bool isDownloaded(String resourceId) {
    if (!_initialized) return false;
    final path = _box.get(resourceId);
    if (path == null) return false;
    return File(path).existsSync(); 
  }

  String? getLocalPath(String resourceId) {
    if (!_initialized) return null;
    return _box.get(resourceId);
  }

  Future<void> downloadResource(String url, String resourceId, String fileName, {Function(int, int)? onProgress}) async {
    if (!_initialized) await init();
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Ensure 'downloads' subdir exists
      final saveDir = Directory('${dir.path}/downloads');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final extension = url.split('.').last.split('?').first;
      final safeName = fileName.replaceAll(RegExp(r'[^\w\s\.-]'), ''); // simple sanitize
      final path = '${saveDir.path}/${safeName}_$resourceId.$extension';

      await Dio().download(
        url, 
        path,
        onReceiveProgress: onProgress,
      );

      await _box.put(resourceId, path);
    } catch (e) {
      throw Exception('Download failed: $e');
    }
  }

  Future<void> deleteResource(String resourceId) async {
    if (!_initialized) await init();
    final path = _box.get(resourceId);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      await _box.delete(resourceId);
    }
  }
}
