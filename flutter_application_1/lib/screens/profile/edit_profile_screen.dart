import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../config/theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/cloudinary_service.dart';
import '../../data/departments_data.dart';
import '../../data/academic_subjects_data.dart';
import '../../models/user.dart';

class EditProfileScreen extends StatefulWidget {
  final String initialName;
  final String? initialPhotoUrl;
  final String? initialBio;
  final String? initialSemester;
  final String? initialBranch;
  final String? initialSubject;
  final String role; // Need to know if they are a TEACHER
  final String? initialAdminKey;

  const EditProfileScreen({
    super.key,
    required this.initialName,
    required this.initialPhotoUrl,
    required this.initialBio,
    this.initialSemester,
    this.initialBranch,
    this.initialSubject,
    required this.role,
    this.initialAdminKey,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const List<String> _semesterOptions = semesterOptions;
  final _api = BackendApiService();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _adminKeyController;
  late final TextEditingController _subjectController;
  String? _selectedSemester;
  String? _selectedBranch;
  String? _selectedSubject;
  List<String> _availableSubjects = [];
  List<DepartmentData> _departments = [];
  bool _loadingDepartments = true;
  PlatformFile? _pickedImage;
  bool _saving = false;
  bool _departmentsEmpty = false;

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _bioController = TextEditingController(text: widget.initialBio ?? '');
    _adminKeyController = TextEditingController(
      text: widget.initialAdminKey ?? '',
    );
    _selectedSemester = _normalizedSemester(widget.initialSemester);
    _selectedBranch = _normalizedSelection(widget.initialBranch);
    _selectedSubject = _normalizedSelection(widget.initialSubject);
    _subjectController = TextEditingController(text: _selectedSubject ?? '');
    _refreshSubjectOptionsForBranch(
      _selectedBranch,
      keepExistingSelection: true,
    );
    _loadDepartments();
  }

  void _refreshSubjectOptionsForBranch(
    String? branch, {
    bool keepExistingSelection = false,
  }) {
    final subjects = getSubjectsForBranchAndSemester(branch, _selectedSemester);
    _availableSubjects = _uniqueNonEmptyOptions(subjects);
    final typedSubject = _subjectController.text.trim();
    if (typedSubject.isNotEmpty) {
      _selectedSubject = typedSubject;
    } else if (!keepExistingSelection) {
      _selectedSubject = null;
    }
  }

  Future<void> _loadDepartments() async {
    try {
      final deps = await DepartmentsProvider.getDepartments();
      if (!mounted) return;
      setState(() {
        if (deps.isEmpty) {
          _departments = [];
          _departmentsEmpty = true;
          _selectedBranch = null;
          _refreshSubjectOptionsForBranch(null);
        } else {
          _departments = deps;
          _departmentsEmpty = false;
          if (_selectedBranch != null) {
            final normalizedBranchCode = normalizeBranchCode(_selectedBranch);
            final matched = deps.firstWhere(
              (d) =>
                  normalizeBranchCode(d.name) == normalizedBranchCode ||
                  normalizeBranchCode(d.full) == normalizedBranchCode,
              orElse: () => const DepartmentData(
                name: '',
                full: '',
                color: Color(0x00000000),
              ),
            );
            if (matched.name.isNotEmpty) {
              _selectedBranch = matched.name;
            } else {
              _selectedBranch = null;
            }
          }
          _refreshSubjectOptionsForBranch(
            _selectedBranch,
            keepExistingSelection: true,
          );
        }
        _loadingDepartments = false;
      });
    } catch (e, st) {
      debugPrint('Error loading departments: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load departments.')),
      );
      setState(() {
        _departments = [];
        _departmentsEmpty = true;
        _selectedBranch = null;
        _refreshSubjectOptionsForBranch(null);
        _loadingDepartments = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _adminKeyController.dispose();
    _subjectController.dispose();
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
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Edit Photo'),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to crop image')));
      }
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

    setState(() => _saving = true);
    try {
      String? photoUrl = widget.initialPhotoUrl;
      if (_pickedImage != null) {
        photoUrl = await CloudinaryService.uploadFile(_pickedImage!);
      }
      final normalizedSubject = _normalizedSelection(
        _subjectController.text.trim(),
      );
      final normalizedBranch = normalizeBranchCode(_selectedBranch);
      final normalizedAdminKey = _adminKeyController.text.trim();
      final canSubmitAdminKey =
          widget.role == AppRoles.teacher || widget.role == AppRoles.admin;

      if (!mounted) return;
      final res = await _api.updateProfile(
        displayName: name,
        bio: _bioController.text.trim(),
        profilePhotoUrl: photoUrl,
        semester: _selectedSemester,
        branch: normalizedBranch.isEmpty ? _selectedBranch : normalizedBranch,
        subject: normalizedSubject,
        adminKey: canSubmitAdminKey && normalizedAdminKey.isNotEmpty
            ? normalizedAdminKey
            : null,
        context: context,
      );

      if (!mounted) return;
      Navigator.pop(context, res['profile']);
    } catch (e) {
      debugPrint('Error updating profile: $e'); // Log full error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update profile'),
          ), // Generic message
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
    final semesterValue = _safeDropdownValue(
      _selectedSemester,
      _semesterOptions,
    );
    final branchOptions = _uniqueNonEmptyOptions(
      _departments.map((dep) => dep.name),
    );
    final branchValue = _safeDropdownValue(_selectedBranch, branchOptions);
    final subjectOptions = _uniqueNonEmptyOptions(_availableSubjects);
    final subjectValue = _safeDropdownValue(
      _subjectController.text.trim(),
      subjectOptions,
    );

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
                    value: semesterValue,
                    decoration: InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: _semesterOptions
                        .map(
                          (sem) =>
                              DropdownMenuItem(value: sem, child: Text(sem)),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (val) => setState(() {
                            _selectedSemester = val;
                            _refreshSubjectOptionsForBranch(
                              _selectedBranch,
                              keepExistingSelection: true,
                            );
                          }),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _loadingDepartments
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<String>(
                          key: ValueKey(
                            'branch-${branchOptions.join('|')}-${branchValue ?? ''}',
                          ),
                          isExpanded: true,
                          value: branchValue,
                          decoration: InputDecoration(
                            labelText: 'Branch',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: _departmentsEmpty
                              ? [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text("No departments available"),
                                  ),
                                ]
                              : branchOptions
                                    .map(
                                      (depName) => DropdownMenuItem(
                                        value: depName,
                                        child: Text(depName),
                                      ),
                                    )
                                    .toList(),
                          onChanged: _saving || _departmentsEmpty
                              ? null
                              : (val) => setState(() {
                                  _selectedBranch = val;
                                  _refreshSubjectOptionsForBranch(val);
                                }),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'subject-${subjectOptions.join('|')}-${subjectValue ?? ''}',
              ),
              value: subjectValue,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Subject (suggested)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              hint: Text(
                _selectedBranch == null
                    ? 'Select branch first'
                    : (subjectOptions.isEmpty
                          ? 'No subjects found'
                          : 'Select subject'),
              ),
              items: subjectOptions
                  .map(
                    (subject) =>
                        DropdownMenuItem(value: subject, child: Text(subject)),
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
            if (widget.role == AppRoles.teacher ||
                widget.role == AppRoles.admin) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _adminKeyController,
                enabled: !_saving,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Admin Key (Optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.key),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String nameInitial(String name) =>
      name.isNotEmpty ? name[0].toUpperCase() : 'U';
}
