import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

class CloudinaryService {
  static const String _uploadUrl = 
      'https://api.cloudinary.com/v1_1/${AppConfig.cloudinaryCloudName}/auto/upload';

  /// Upload a file to Cloudinary
  /// Returns the secure URL of the uploaded file
  static Future<String> uploadFile(PlatformFile file, {Duration? timeout}) async {
    try {
      final uri = Uri.parse(_uploadUrl);
      final request = http.MultipartRequest('POST', uri);

      // Add upload preset (unsigned upload)
      request.fields['upload_preset'] = AppConfig.cloudinaryUploadPreset;
      request.fields['folder'] = 'studyspace_resources';

      // Add the file
      if (file.path != null) {
        // Mobile / Desktop (Filesystem available)
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            file.path!,
            filename: file.name,
          ),
        );
      } else if (file.bytes != null) {
        // Web or memory-only
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
          ),
        );
      } else {
        throw Exception('File data is empty or inaccessible');
      }

      final duration = timeout ?? const Duration(seconds: 60);

      final streamedResponse = await request.send().timeout(
        duration,
        onTimeout: () => throw Exception('Upload timed out'),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['secure_url'] as String;
      } else {
        final error = jsonDecode(response.body);
        throw error['error']?['message'] ?? 'Upload failed';
      }
    } catch (e) {
      debugPrint('Cloudinary upload error: $e');
      rethrow;
    }
  }

  static Future<String> uploadBytes(Uint8List bytes, String filename, {Duration? timeout}) async {
    try {
      if (bytes.isEmpty) {
        throw Exception('File data is empty');
      }
      final uri = Uri.parse(_uploadUrl);
      final request = http.MultipartRequest('POST', uri);

      request.fields['upload_preset'] = AppConfig.cloudinaryUploadPreset;
      request.fields['folder'] = 'studyspace_resources';

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
        ),
      );

      final duration = timeout ?? const Duration(seconds: 60);

      final streamedResponse = await request.send().timeout(
        duration,
        onTimeout: () => throw Exception('Upload timed out'),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['secure_url'] as String;
      } else {
        String errorMessage;
        try {
          final error = jsonDecode(response.body);
          errorMessage = error['error']?['message'] ?? 'Upload failed: ${response.statusCode}';
        } catch (_) {
          errorMessage = 'Upload failed: ${response.statusCode}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('Cloudinary upload error: $e');
      rethrow;
    }
  }
}