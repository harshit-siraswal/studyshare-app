import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String heroTag;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  bool _isDownloading = false;

  Future<void> _shareImage() async {
    String? savePath;
    try {
      setState(() => _isDownloading = true);
      
      // Download to temp directory
      var tempDir = await getTemporaryDirectory();
      
      String ext = _getImageExtension(widget.imageUrl);
      savePath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}$ext';
      
      await Dio().download(
        widget.imageUrl, 
        savePath,
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );
      
      if (!mounted) return;
      setState(() => _isDownloading = false);
      
      // Share
      await Share.shareXFiles([XFile(savePath)], text: 'Check out this image from MyStudySpace!');
    } catch (e) {
      debugPrint('Error sharing image: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to share image')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
      // Cleanup temp file after delay to allow share sheet to grab it
      if (savePath != null) {
        Future.delayed(const Duration(minutes: 1), () async {
          try {
            final file = File(savePath!);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (cleanupError) {
            debugPrint('Error cleaning up temp share file: $cleanupError');
          }
        });
      }
    }
  }

  Future<void> _downloadImage() async {
    try {
       setState(() => _isDownloading = true);

       if (Platform.isAndroid) {
         final androidInfo = await DeviceInfoPlugin().androidInfo;
         final sdkInt = androidInfo.version.sdkInt;

         // For Android SDK < 29 (Android 10), we need storage permission
         if (sdkInt < 29) {
           var status = await Permission.storage.status;
           if (status.isDenied) {
             status = await Permission.storage.request();
           }
           
           if (!status.isGranted) {
              if (mounted) setState(() => _isDownloading = false);
              if (status.isPermanentlyDenied) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text('Storage permission required. Please enable it in settings.')),
                  );
                  await openAppSettings();
                }
              }
              return;
          }
        }         // For SDK >= 29 (Android 10+), we use scoped storage/public directories which don't need
         // WRITE_EXTERNAL_STORAGE for app-specific or media store writes.
         // SDK >= 33 would need READ_MEDIA_IMAGES for reading, but we are writing here.
       }

       // Get Downloads Directory
       Directory? downloadsDir;
       if (Platform.isAndroid) {
         downloadsDir = await getDownloadsDirectory();
         if (downloadsDir == null || !await downloadsDir.exists()) {
           downloadsDir = await getExternalStorageDirectory(); // fallback
         }
       } else {
         downloadsDir = await getApplicationDocumentsDirectory(); 
       }

       if (downloadsDir == null) {
          throw Exception('Could not access storage directory');
       }

       // Derive extension
       String ext = p.extension(widget.imageUrl).toLowerCase();
       if (!['.jpg', '.jpeg', '.png', '.webp', '.gif'].contains(ext)) {
          ext = '.jpg';
       }

       String fileName = 'mystudyspace_${DateTime.now().millisecondsSinceEpoch}$ext';
       String savePath = p.join(downloadsDir.path, fileName);
       
       debugPrint('Downloading to $savePath');
       
       await Dio().download(widget.imageUrl, savePath);
       
       if (!mounted) return;
       
       ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Platform.isAndroid 
              ? 'Image saved to Downloads folder' 
              : 'Image saved to Files')),
       );
    } catch (e) {
      debugPrint('Error saving image: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save image')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PhotoView(
            imageProvider: NetworkImage(widget.imageUrl),
            heroAttributes: PhotoViewHeroAttributes(tag: widget.heroTag),
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorBuilder: (context, error, stackTrace) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load image',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
          ),
          
          // App Bar (Transparent Overlay)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Row(
                      children: [
                        if (_isDownloading)
                           const Padding(
                             padding: EdgeInsets.only(right: 16),
                             child: SizedBox(
                               width: 20, 
                               height: 20, 
                               child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                             ),
                           ),
                        IconButton( // Download
                          icon: const Icon(Icons.download_rounded, color: Colors.white),
                          tooltip: 'Save to Phone',
                          onPressed: _isDownloading ? null : _downloadImage,
                        ),
                        IconButton( // Share
                          icon: const Icon(Icons.share_rounded, color: Colors.white),
                          tooltip: 'Share',
                          onPressed: _isDownloading ? null : _shareImage,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getImageExtension(String url) {
    // Strip query parameters before extracting extension
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url;
    String ext = p.extension(path).toLowerCase();
    if (!['.jpg', '.jpeg', '.png', '.webp', '.gif'].contains(ext)) {
      return '.jpg';
    }
    return ext;
  }
}