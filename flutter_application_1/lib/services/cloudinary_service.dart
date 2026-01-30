import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../config/app_config.dart';

class CloudinaryService {
  static const String _uploadUrl = 
      'https://api.cloudinary.com/v1_1/${AppConfig.cloudinaryCloudName}/auto/upload';

  /// Upload a file to Cloudinary
  /// Returns the secure URL of the uploaded file
  static Future<String> uploadFile(PlatformFile file) async {
    try {
      if (file.bytes == null) {
        throw 'File data is empty';
      }

      final uri = Uri.parse(_uploadUrl);
      final request = http.MultipartRequest('POST', uri);

      // Add upload preset (unsigned upload)
      request.fields['upload_preset'] = AppConfig.cloudinaryUploadPreset;
      request.fields['folder'] = 'studyspace_resources';

      // Add the file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['secure_url'] as String;
      } else {
        final error = jsonDecode(response.body);
        throw error['error']?['message'] ?? 'Upload failed';
      }
    } catch (e) {
      print('Cloudinary upload error: $e');
      rethrow;
    }
  }

  /// Upload file bytes directly
  static Future<String> uploadBytes(Uint8List bytes, String filename) async {
    try {
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

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['secure_url'] as String;
      } else {
        throw 'Upload failed: ${response.statusCode}';
      }
    } catch (e) {
      print('Cloudinary upload error: $e');
      rethrow;
    }
  }
}
