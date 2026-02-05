import 'dart:io';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/resource.dart';
import 'package:flutter/foundation.dart';

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
    final data = _box.get(resourceId);
    if (data == null) return false;
    
    // Check if file exists
    final path = data is Map ? data['local_path'] : data;
    if (path == null) return false;
    
    return File(path).existsSync(); 
  }

  String? getLocalPath(String resourceId) {
    if (!_initialized) return null;
    final data = _box.get(resourceId);
    if (data == null) return null;
    return data is Map ? data['local_path'] : data; // Handle legitimate legacy string paths if any
  }

  List<Resource> getAllDownloadedResources() {
    if (!_initialized) return [];
    final resources = <Resource>[];
    
    for (var key in _box.keys) {
      final data = _box.get(key);
      if (data is Map) {
        // Verify file still exists
        final path = data['local_path'];
        if (path != null && File(path).existsSync()) {
          try {
            // Reconstruct Resource from stored JSON
            // We need to ensure the local path is used effectively
             final resourceJson = Map<String, dynamic>.from(data['resource_json']);
             // We can inject the local path into resource if needed, but for now just returning the object
             resources.add(Resource.fromJson(resourceJson));
          } catch (e) {
            debugPrint('Error parsing cached resource: $e');
          }
        }
      }
    }
    return resources;
  }

  Future<void> downloadResource(String url, Resource resource, {Function(int, int)? onProgress}) async {
    if (!_initialized) await init();
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Ensure 'downloads' subdir exists
      final saveDir = Directory('${dir.path}/downloads');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final extension = url.split('.').last.split('?').first;
      final safeName = resource.title.replaceAll(RegExp(r'[^\w\s\.-]'), ''); // simple sanitize
      final path = '${saveDir.path}/${safeName}_${resource.id}.$extension';

      await Dio().download(
        url, 
        path,
        onReceiveProgress: onProgress,
      );

      // Store metadata + path
      final data = {
        'local_path': path,
        'resource_json': resource.toJson(),
        'downloaded_at': DateTime.now().toIso8601String(),
      };

      await _box.put(resource.id, data);
    } catch (e) {
      throw Exception('Download failed: $e');
    }
  }

  Future<void> deleteResource(String resourceId) async {
    if (!_initialized) await init();
    final data = _box.get(resourceId);
    
    String? path;
    if (data is Map) {
      path = data['local_path'];
    } else if (data is String) {
      path = data;
    }

    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _box.delete(resourceId);
  }
}
