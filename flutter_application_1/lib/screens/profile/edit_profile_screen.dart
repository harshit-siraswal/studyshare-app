import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../config/theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/cloudinary_service.dart';

class EditProfileScreen extends StatefulWidget {
  final String initialName;
  final String? initialPhotoUrl;
  final String? initialBio;

  const EditProfileScreen({
    super.key,
    required this.initialName,
    required this.initialPhotoUrl,
    required this.initialBio,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _api = BackendApiService();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  PlatformFile? _pickedImage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _bioController = TextEditingController(text: widget.initialBio ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path != null) {
        await _cropImage(file.path!);
      } else {
         // Fallback for web or if path is null
         setState(() => _pickedImage = file);
      }
    }
  }

  Future<void> _cropImage(String sourcePath) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        uiSettings: [
          AndroidUiSettings(
              toolbarTitle: 'Edit Photo',
              toolbarColor: AppTheme.primary,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.original,
              lockAspectRatio: false),
          IOSUiSettings(
            title: 'Edit Photo',
          ),
        ],
      );

      if (croppedFile != null) {
        final file = File(croppedFile.path);
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
            _pickedImage = PlatformFile(
              name: p.basename(croppedFile.path),
              size: bytes.length,
              path: croppedFile.path,
              bytes: bytes,
            );
        });
      }
    } catch (e) {
      debugPrint('Error cropping image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to crop image')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      String? photoUrl = widget.initialPhotoUrl;
      if (_pickedImage != null) {
        photoUrl = await CloudinaryService.uploadFile(_pickedImage!);
      }

      if (!mounted) return;
      final res = await _api.updateProfile(
        displayName: name,
        bio: _bioController.text.trim(),
        profilePhotoUrl: photoUrl,
        context: context,
      );
      
      if (!mounted) return;
      Navigator.pop(context, res['profile']);
    } catch (e) {
      debugPrint('Error updating profile: $e'); // Log full error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update profile')), // Generic message
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ImageProvider? get _avatarImage {
    if (_pickedImage?.bytes != null) {
      return MemoryImage(_pickedImage!.bytes!);
    }
    if (_pickedImage?.path != null) {
      return FileImage(File(_pickedImage!.path!));
    }
    if (widget.initialPhotoUrl != null) {
      return NetworkImage(widget.initialPhotoUrl!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        title: Text('Edit Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Save', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: GestureDetector(
                onTap: _saving ? null : _pickPhoto,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                      backgroundImage: _avatarImage,
                      child: _avatarImage == null
                          ? Text(nameInitial(_nameController.text), style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primary))
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioController,
              enabled: !_saving,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Bio',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String nameInitial(String name) => name.isNotEmpty ? name[0].toUpperCase() : 'U';
}

