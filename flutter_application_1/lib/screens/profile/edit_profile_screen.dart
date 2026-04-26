import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme.dart';
import '../../data/academic_subjects_data.dart';
import '../../services/backend_api_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/admin_access.dart';

class EditProfileScreen extends StatefulWidget {
  final String initialName;
  final String? initialUsername;
  final String? initialEmail;
  final String? initialPhotoUrl;
  final String? initialBio;
  final String? initialSemester;
  final String? initialBranch;
  final String? initialSubject;
  final String role;

  const EditProfileScreen({
    super.key,
    required this.initialName,
    this.initialUsername,
    this.initialEmail,
    required this.initialPhotoUrl,
    required this.initialBio,
    this.initialSemester,
    this.initialBranch,
    this.initialSubject,
    required this.role,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const List<String> _semesterOptions = semesterOptions;

  final _api = BackendApiService();
  final _supabaseService = SupabaseService();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final TextEditingController _subjectController;

  String? _selectedSemester;
  String? _selectedBranch;
  String? _selectedSubject;
  List<String> _availableSubjects = [];
  String? _selectedCollegeId;
  String? _selectedCollegeDomain;
  String? _selectedCollegeName;
  PlatformFile? _pickedImage;
  bool _saving = false;

  bool get _supportsSubjectField {
    final normalizedRole = normalizeProfileRoleValue(widget.role);
    return normalizedRole == appRoleTeacher || normalizedRole == appRoleAdmin;
  }

  List<String> _uniqueNonEmptyOptions(Iterable<String> options) {
    final seen = <String>{};
    final values = <String>[];
    for (final raw in options) {
      final normalized = raw.trim();
      if (normalized.isEmpty) continue;
      if (seen.add(normalized)) {
        values.add(normalized);
      }
    }
    return values;
  }

  String? _safeDropdownValue(String? value, List<String> options) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return options.contains(normalized) ? normalized : null;
  }

  String? _normalizedSelection(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'all') {
      return null;
    }
    return trimmed;
  }

  String? _normalizedSemester(String? value) {
    final normalized = _normalizedSelection(value);
    if (normalized == null) return null;
    return _semesterOptions.contains(normalized) ? normalized : null;
  }

  String? _normalizedBranch(String? value) {
    final normalized = normalizeBranchCode(value);
    if (normalized.isEmpty) return null;
    final knownBranch = _branchOptions.any(
      (option) => option.value == normalized,
    );
    return knownBranch ? normalized : null;
  }

  List<BranchOption> get _branchOptions => getBranchOptionsForCollege(
    collegeId: _selectedCollegeId,
    collegeDomain: _selectedCollegeDomain,
    collegeName: _selectedCollegeName,
  );

  String _deriveUsernameFromEmail(String? email) {
    final normalized = (email ?? '').trim().toLowerCase();
    if (!normalized.contains('@')) return '';
    return _sanitizeUsernameInput(normalized.split('@').first);
  }

  String _sanitizeUsernameInput(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    final cleaned = normalized
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '')
        .replaceAll(RegExp(r'^[._-]+'), '')
        .replaceAll(RegExp(r'[._-]+$'), '');
    if (cleaned.length <= 32) return cleaned;
    return cleaned.substring(0, 32);
  }

  String? _validateUsernameInput(String value) {
    if (value.isEmpty) return null;
    if (value.length < 3) {
      return 'Username must be at least 3 characters.';
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{1,31}$').hasMatch(value)) {
      return 'Use letters, numbers, dot, underscore, or hyphen.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    final seededUsername = _sanitizeUsernameInput(
      (widget.initialUsername ?? '').trim(),
    );
    final defaultUsername = _deriveUsernameFromEmail(widget.initialEmail);
    _usernameController = TextEditingController(
      text: seededUsername.isNotEmpty ? seededUsername : defaultUsername,
    );
    _bioController = TextEditingController(text: widget.initialBio ?? '');
    _selectedSemester = _normalizedSemester(widget.initialSemester);
    _selectedBranch = _normalizedBranch(widget.initialBranch);
    _selectedSubject = _supportsSubjectField
        ? _normalizedSelection(widget.initialSubject)
        : null;
    _subjectController = TextEditingController(text: _selectedSubject ?? '');
    _refreshSubjectOptionsForBranch(
      _selectedBranch,
      keepExistingSelection: true,
      preserveCustomInput: true,
    );
    _loadCollegeContext();
  }

  void _refreshSubjectOptionsForBranch(
    String? branch, {
    bool keepExistingSelection = false,
    bool preserveCustomInput = false,
  }) {
    final subjects = getSubjectsForBranchAndSemester(
      branch,
      _selectedSemester,
      collegeId: _selectedCollegeId,
      collegeDomain: _selectedCollegeDomain,
      collegeName: _selectedCollegeName,
    );
    _availableSubjects = _uniqueNonEmptyOptions(subjects);

    final currentSubject = _normalizedSelection(_subjectController.text);
    if (currentSubject == null) {
      _selectedSubject = null;
      if (!preserveCustomInput) {
        _subjectController.clear();
      }
      return;
    }

    final canKeepCurrentSubject =
        keepExistingSelection &&
        (preserveCustomInput || _availableSubjects.contains(currentSubject));
    if (canKeepCurrentSubject) {
      _selectedSubject = currentSubject;
      return;
    }

    _selectedSubject = null;
    _subjectController.clear();
  }

  Future<void> _loadCollegeContext() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selectedCollege = prefs.getString('selectedCollege');
      if (selectedCollege == null || selectedCollege.trim().isEmpty) {
        return;
      }

      final data = jsonDecode(selectedCollege) as Map<String, dynamic>;
      if (!mounted) return;

      setState(() {
        _selectedCollegeId = data['id']?.toString().trim();
        _selectedCollegeDomain = data['domain']?.toString().trim();
        _selectedCollegeName = data['name']?.toString().trim();
        _selectedBranch = _normalizedBranch(_selectedBranch);
        _refreshSubjectOptionsForBranch(
          _selectedBranch,
          keepExistingSelection: true,
          preserveCustomInput: true,
        );
      });
    } catch (e) {
      debugPrint('Failed to load college context for profile editor: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path != null) {
      await _cropImage(file.path!);
      return;
    }

    setState(() => _pickedImage = file);
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
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Edit Photo'),
        ],
      );

      if (croppedFile == null) return;

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
    } catch (e) {
      debugPrint('Error cropping image: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to crop image')));
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name cannot be empty')));
      return;
    }

    final sanitizedUsername = _sanitizeUsernameInput(_usernameController.text);
    final usernameValidationError = _validateUsernameInput(sanitizedUsername);
    if (usernameValidationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(usernameValidationError)));
      return;
    }

    final effectiveUsername = sanitizedUsername.isNotEmpty
        ? sanitizedUsername
        : _deriveUsernameFromEmail(widget.initialEmail);

    setState(() => _saving = true);
    try {
      String? photoUrl = widget.initialPhotoUrl;
      if (_pickedImage != null) {
        final upload = await _api.uploadChatImage(file: _pickedImage!);
        photoUrl =
            upload['imageUrl']?.toString().trim() ??
            upload['url']?.toString().trim() ??
            widget.initialPhotoUrl;
      }

      final normalizedSemester = _normalizedSemester(_selectedSemester);
      final normalizedBranch = _normalizedBranch(_selectedBranch);
      final normalizedSubject = _supportsSubjectField
          ? _normalizedSelection(_subjectController.text.trim())
          : null;
      final submittedProfile = _submittedProfilePayload(
        name: name,
        username: effectiveUsername,
        photoUrl: photoUrl,
        semester: normalizedSemester,
        branch: normalizedBranch,
        subject: normalizedSubject,
      );

      Map<String, dynamic> updatedProfile;
      try {
        if (!mounted) return;
        final response = await _api.updateProfile(
          displayName: name,
          username: effectiveUsername,
          bio: _bioController.text.trim(),
          profilePhotoUrl: photoUrl,
          semester: normalizedSemester,
          branch: normalizedBranch,
          subject: _supportsSubjectField ? normalizedSubject : null,
          context: context,
        );
        updatedProfile = _coerceUpdatedProfile(
          response,
          fallbackProfile: submittedProfile,
        );
      } catch (backendError) {
        if (!_shouldFallbackToDirectProfileUpdate(backendError)) {
          rethrow;
        }
        debugPrint(
          'Backend profile update failed, retrying direct Supabase update: '
          '$backendError',
        );
        updatedProfile = await _supabaseService.updateCurrentUserProfileDirect(
          displayName: name,
          username: effectiveUsername,
          bio: _bioController.text.trim(),
          profilePhotoUrl: photoUrl,
          semester: normalizedSemester,
          branch: normalizedBranch,
          subject: _supportsSubjectField ? normalizedSubject : null,
        );
      }

      if (!mounted) return;
      _supabaseService.invalidateCurrentUserProfileCache();
      Navigator.pop(context, updatedProfile);
    } catch (e) {
      debugPrint('Error updating profile: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyProfileError(e))));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
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

  String _subjectHintText(List<String> subjectOptions) {
    if (_selectedBranch == null) {
      return 'Select branch first';
    }
    if (subjectOptions.isEmpty) {
      return 'No subjects found';
    }
    return 'Select subject';
  }

  String nameInitial(String name) =>
      name.isNotEmpty ? name[0].toUpperCase() : 'U';

  Map<String, dynamic> _submittedProfilePayload({
    required String name,
    required String? username,
    required String? photoUrl,
    required String? semester,
    required String? branch,
    required String? subject,
  }) {
    return <String, dynamic>{
      'display_name': name,
      'username': username,
      'profile_photo_url': photoUrl,
      'bio': _bioController.text.trim(),
      'semester': semester,
      'branch': branch,
      if (_supportsSubjectField) 'subject': subject,
    };
  }

  Map<String, dynamic> _coerceUpdatedProfile(
    Map<String, dynamic>? response, {
    required Map<String, dynamic> fallbackProfile,
  }) {
    if (response == null || response.isEmpty) {
      return fallbackProfile;
    }

    final nestedProfile = response['profile'];
    if (nestedProfile is Map) {
      return Map<String, dynamic>.from(nestedProfile);
    }

    const profileKeys = <String>{
      'display_name',
      'profile_photo_url',
      'bio',
      'semester',
      'branch',
      'subject',
      'email',
      'id',
      'username',
    };
    if (!response.keys.any(profileKeys.contains)) {
      return fallbackProfile;
    }

    return <String, dynamic>{...fallbackProfile, ...response};
  }

  String _friendlyProfileError(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return 'Failed to update profile.';
    }

    const prefix = 'Exception:';
    final normalized = raw.startsWith(prefix)
        ? raw.substring(prefix.length).trim()
        : raw;
    return normalized.isEmpty ? 'Failed to update profile.' : normalized;
  }

  bool _shouldFallbackToDirectProfileUpdate(Object error) {
    if (isBackendCompatibilityFallbackError(error)) {
      return true;
    }

    if (error is BackendApiHttpException) {
      if (error.statusCode == 429) return true;
      if (error.statusCode >= 500) return true;
    }

    final lowered = error.toString().toLowerCase();
    return lowered.contains('timeout') ||
        lowered.contains('timed out') ||
        lowered.contains('rate limit') ||
        lowered.contains('temporarily unavailable') ||
        lowered.contains('connection');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : const Color(0xFFF8FAFC);
    final semesterValue = _safeDropdownValue(
      _selectedSemester,
      _semesterOptions,
    );
    final branchValues = _branchOptions.map((option) => option.value).toList();
    final branchValue = _safeDropdownValue(_selectedBranch, branchValues);
    final subjectOptions = _supportsSubjectField
        ? _uniqueNonEmptyOptions(_availableSubjects)
        : const <String>[];
    final subjectValue = _supportsSubjectField
        ? _safeDropdownValue(_selectedSubject, subjectOptions)
        : null;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        title: Text(
          'Edit Profile',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
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
                          ? Text(
                              nameInitial(_nameController.text),
                              style: GoogleFonts.inter(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            )
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              enabled: !_saving,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                helperText: 'Unique handle. Letters, numbers, . _ -',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                final sanitized = _sanitizeUsernameInput(value);
                if (sanitized == value) return;
                final selection = TextSelection.collapsed(
                  offset: sanitized.length,
                );
                _usernameController.value = TextEditingValue(
                  text: sanitized,
                  selection: selection,
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioController,
              enabled: !_saving,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Bio',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('semester-${semesterValue ?? ''}'),
                    initialValue: semesterValue,
                    decoration: InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: _semesterOptions
                        .map(
                          (semester) => DropdownMenuItem(
                            value: semester,
                            child: Text(semester),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _selectedSemester = value;
                            _refreshSubjectOptionsForBranch(
                              _selectedBranch,
                              keepExistingSelection: true,
                            );
                          }),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('branch-${branchValue ?? ''}'),
                    isExpanded: true,
                    initialValue: branchValue,
                    decoration: InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    selectedItemBuilder: (context) => _branchOptions
                        .map(
                          (option) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              option.shortLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    items: _branchOptions
                        .map(
                          (option) => DropdownMenuItem(
                            value: option.value,
                            child: Text(
                              option.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _selectedBranch = value;
                            _refreshSubjectOptionsForBranch(
                              value,
                              keepExistingSelection: true,
                            );
                          }),
                  ),
                ),
              ],
            ),
            if (_supportsSubjectField) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'subject-${subjectOptions.join('|')}-${subjectValue ?? ''}',
                ),
                initialValue: subjectValue,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Subject (suggested)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                hint: Text(_subjectHintText(subjectOptions)),
                items: subjectOptions
                    .map(
                      (subject) => DropdownMenuItem(
                        value: subject,
                        child: Text(subject),
                      ),
                    )
                    .toList(),
                onChanged:
                    _saving || _selectedBranch == null || subjectOptions.isEmpty
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedSubject = value;
                          _subjectController.text = value;
                        });
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subjectController,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: 'Subject',
                  hintText: 'Enter your subject',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _selectedSubject = _normalizedSelection(value);
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
