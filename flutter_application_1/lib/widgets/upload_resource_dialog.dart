import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../config/theme.dart';
import '../models/resource.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import 'package:http/http.dart' as http;
import 'success_overlay.dart';
import '../utils/youtube_link_utils.dart';
import '../utils/admin_access.dart';
import '../data/academic_subjects_data.dart';

class UploadResourceDialog extends StatefulWidget {
  final String collegeId;
  final String userEmail;
  final VoidCallback? onUploadComplete;
  final PlatformFile? prefilledFile;

  const UploadResourceDialog({
    super.key,
    required this.collegeId,
    required this.userEmail,
    this.onUploadComplete,
    this.prefilledFile,
  });

  @override
  State<UploadResourceDialog> createState() => _UploadResourceDialogState();
}

class _UploadResourceDialogState extends State<UploadResourceDialog>
    with SingleTickerProviderStateMixin {
  // Form state
  int _typeIndex = 0; // 0=notes, 1=video
  String _resourceType = 'notes';
  String _title = '';
  String _description = '';
  String _semester = '';
  String _branch = '';
  String _subject = '';
  String _chapter = '';
  String _topic = '';
  String _videoUrl = '';
  PlatformFile? _selectedFile;
  Map<String, dynamic>? _academicCatalog;

  bool _isUploading = false;
  double _uploadProgress = 0;
  bool _prefilledFileUnsupported = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late TextEditingController _titleController;
  late TextEditingController _subjectController;

  // Compact config data
  static const _allowedFileExtensions = [
    'pdf',
    'doc',
    'docx',
    'ppt',
    'pptx',
    'odt',
    'odp',
    'txt',
  ];
  static const int _maxUploadBytes = 50 * 1024 * 1024;
  static const int _skipHashThresholdBytes = 8 * 1024 * 1024;
  static final Map<String, String> branches = <String, String>{
    for (final option in branchOptions) option.shortLabel: option.value,
  };

  List<String> get availableSubjects =>
      _catalogSubjectsForCurrentScope.isNotEmpty
      ? _catalogSubjectsForCurrentScope
      : getSubjectsForBranchAndSemester(_branch, _semester);

  List<String> get _catalogSubjectsForCurrentScope {
    final offerings = (_academicCatalog?['offerings'] as List?) ?? const [];
    if (_branch.isEmpty || _semester.isEmpty) return const <String>[];
    final subjects = offerings
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(
          (item) =>
              item['branch']?.toString() == _branch &&
              item['semester']?.toString() == _semester,
        )
        .map((item) => item['subject']?.toString().trim() ?? '')
        .where((subject) => subject.isNotEmpty)
        .toSet()
        .toList();
    subjects.sort();
    return subjects;
  }

  bool get _canSelectSubject =>
      _semester.trim().isNotEmpty &&
      _branch.trim().isNotEmpty &&
      availableSubjects.isNotEmpty;

  String get _subjectSelectorLabel {
    if (_semester.trim().isEmpty || _branch.trim().isEmpty) {
      return 'Select semester and branch first';
    }
    if (availableSubjects.isEmpty) {
      return 'No subjects available for this scope';
    }
    return _subject;
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _subjectController = TextEditingController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _loadAcademicCatalog();

    final prefilledFile = widget.prefilledFile;
    if (prefilledFile != null) {
      final ext = _fileExtension(prefilledFile.name);
      if (_allowedFileExtensions.contains(ext)) {
        _selectedFile = prefilledFile;
        _title = _titleFromFileName(prefilledFile.name);
        _titleController.text = _title;
      } else {
        _prefilledFileUnsupported = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showError('Shared file type is not supported for resources yet.');
          }
        });
      }
    }
  }

  Future<void> _loadAcademicCatalog() async {
    try {
      final backendApi = BackendApiService();
      final catalog = await backendApi.getAcademicCatalog();
      if (!mounted) return;
      setState(() => _academicCatalog = catalog);
    } catch (e) {
      debugPrint('Failed to load academic catalog: $e');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _titleController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  String _fileExtension(String filename) {
    final parts = filename.split('.');
    if (parts.length < 2) return '';
    return parts.last.toLowerCase();
  }

  String _titleFromFileName(String filename) {
    final dot = filename.lastIndexOf('.');
    final base = dot > 0 ? filename.substring(0, dot) : filename;
    return base.replaceAll('_', ' ').trim();
  }

  Future<String> _computeSha256Hex(List<int> bytes) async {
    return compute(_sha256Sync, bytes);
  }

  static String _sha256Sync(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  bool _shouldSkipPreUploadHash(PlatformFile file) {
    return !kIsWeb &&
        (file.path?.trim().isNotEmpty ?? false) &&
        file.size > _skipHashThresholdBytes;
  }

  void _updateTransferProgress(double fraction) {
    if (!mounted) return;
    final bounded = fraction.clamp(0.0, 1.0);
    final nextProgress = 0.4 + (bounded * 0.3);
    if ((_uploadProgress - nextProgress).abs() < 0.02 && bounded < 1.0) {
      return;
    }
    setState(() => _uploadProgress = nextProgress);
  }

  Future<void> _uploadToPresignedUrl({
    required PlatformFile file,
    required String uploadUrl,
    required String contentType,
    List<int>? bytes,
  }) async {
    final uri = Uri.parse(uploadUrl);

    if (bytes != null) {
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': contentType,
          'Cache-Control': 'max-age=31536000',
          'Content-Length': bytes.length.toString(),
        },
        body: bytes,
      );
      _updateTransferProgress(1.0);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Upload failed: ${response.statusCode}');
      }
      return;
    }

    final filePath = file.path?.trim() ?? '';
    if (filePath.isEmpty) {
      throw Exception('File path is unavailable for upload.');
    }

    final request = http.StreamedRequest('PUT', uri);
    request.headers['Content-Type'] = contentType;
    request.headers['Cache-Control'] = 'max-age=31536000';
    request.contentLength = file.size;

    final source = File(filePath).openRead();
    var uploadedBytes = 0;
    var lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

    await request.sink.addStream(
      source.map((chunk) {
        uploadedBytes += chunk.length;
        final now = DateTime.now();
        final shouldRefresh =
            uploadedBytes >= file.size ||
            now.difference(lastProgressUpdate).inMilliseconds >= 80;
        if (shouldRefresh && file.size > 0) {
          lastProgressUpdate = now;
          _updateTransferProgress(uploadedBytes / file.size);
        }
        return chunk;
      }),
    );
    await request.sink.close();

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    _updateTransferProgress(1.0);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final suffix = responseBody.trim().isEmpty ? '' : ': $responseBody';
      throw Exception('Upload failed: ${response.statusCode}$suffix');
    }
  }

  void _setSubjectValue(String value) {
    _subject = value;
    if (_subjectController.text == value) return;
    _subjectController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _clearSubjectValue() {
    _setSubjectValue('');
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedFileExtensions,
        withData: false, // Don't load full file to memory to prevent crashes
        withReadStream: kIsWeb, // For web, streams are needed for big files
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.size > _maxUploadBytes) {
          if (mounted) _showError('File must be under 50MB');
          return;
        }
        setState(() => _selectedFile = file);
      }
    } catch (e) {
      if (mounted) _showError('Error picking file');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  String _getContentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.odt')) {
      return 'application/vnd.oasis.opendocument.text';
    }
    if (lower.endsWith('.odp')) {
      return 'application/vnd.oasis.opendocument.presentation';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  Future<void> _handleSubmit() async {
    if (_isUploading) return;

    if (_title.trim().isEmpty) return _showError('Enter a title');
    if (_semester.isEmpty) return _showError('Select semester');
    if (_branch.isEmpty) return _showError('Select branch');
    if (_subject.isEmpty) return _showError('Select subject');
    String resolvedVideoUrl = '';
    if (_typeIndex == 0 && _selectedFile == null) {
      return _showError('Attach a file to contribute');
    }
    if (_typeIndex == 1) {
      final rawVideo = _videoUrl.trim();
      if (rawVideo.isEmpty) {
        return _showError('Enter video URL');
      }
      final normalizedVideo = normalizeExternalUrl(rawVideo);
      final uri = buildExternalUri(normalizedVideo);
      if (uri == null) {
        return _showError('Enter a valid HTTP/HTTPS video URL');
      }
      final youtube = parseYoutubeLink(normalizedVideo);
      resolvedVideoUrl = (youtube?.watchUri ?? uri).toString();
    }

    // Mark upload active before network pre-checks so one tap always starts the flow.
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.05;
    });

    Map<String, dynamic>? fetchedProfile;
    try {
      fetchedProfile = await SupabaseService().getCurrentUserProfile(
        maxAttempts: 1,
      );
      if (fetchedProfile.isNotEmpty &&
          resolveEffectiveProfileRole(fetchedProfile) == appRoleReadOnly &&
          !canManageAdminResourcesProfile(fetchedProfile)) {
        debugPrint(
          'Upload pre-check resolved as read-only; deferring final authorization to backend.',
        );
      }
    } catch (e) {
      debugPrint('Failed to resolve upload permissions: $e');
    }

    final shouldUseAdminResourceUpload =
        fetchedProfile != null &&
        fetchedProfile.isNotEmpty &&
        hasAdminCapability(fetchedProfile, 'upload_resource');

    try {
      final authService = AuthService();
      final backendApi = BackendApiService();

      // Progress: preparing
      setState(() => _uploadProgress = 0.2);

      final selectedScope = <String, dynamic>{
        'branch': _branch,
        'semester': _semester,
        'subject': _subject.trim(),
      };
      String? fileSha256;

      // Upload file to R2 if notes/pyq
      String? filePath;
      if (_typeIndex == 0 && _selectedFile != null) {
        setState(() => _uploadProgress = 0.4);
        try {
          final file = _selectedFile!;
          final shouldSkipHash = _shouldSkipPreUploadHash(file);

          List<int>? bytes;
          if (!shouldSkipHash && kIsWeb) {
            if (file.bytes != null) {
              bytes = file.bytes!;
            } else if (file.readStream != null) {
              final buffer = BytesBuilder(copy: false);
              await for (final chunk in file.readStream!) {
                buffer.add(chunk);
              }
              bytes = buffer.takeBytes();
            }
          } else if (!shouldSkipHash && file.path != null) {
            bytes = await File(file.path!).readAsBytes();
          }

          if (!shouldSkipHash && (bytes == null || bytes.isEmpty)) {
            throw Exception(
              'File bytes are empty or could not be read. Please try again.',
            );
          }

          if (!shouldSkipHash && bytes != null) {
            fileSha256 = await _computeSha256Hex(bytes);
          }

          final uploadPlan = await backendApi.planResourceUpload(
            filename: file.name,
            contentType: _getContentType(file.name),
            sizeBytes: file.size,
            fileSha256: fileSha256,
            type: _resourceType,
            selectedScope: selectedScope,
            collegeId: widget.collegeId,
          );

          if (uploadPlan['mode']?.toString() == 'reuse') {
            final preview = uploadPlan['resourcePreview'] as Map?;
            filePath =
                preview?['file_url']?.toString() ??
                preview?['filePath']?.toString();
          } else {
            final uploadUrl = uploadPlan['uploadUrl']?.toString();
            final publicUrl = uploadPlan['publicUrl']?.toString();

            if (uploadUrl == null || publicUrl == null) {
              throw Exception('Failed to get upload URL');
            }

            await _uploadToPresignedUrl(
              file: file,
              uploadUrl: uploadUrl,
              contentType: _getContentType(file.name),
              bytes: bytes,
            );

            filePath = publicUrl;
          }
        } catch (e) {
          _showError('File submission failed: $e');
          setState(() {
            _isUploading = false;
            _uploadProgress = 0;
          });
          return;
        }
      }

      setState(() => _uploadProgress = 0.7);

      // Get user role dynamically for source tagging
      String uploaderSource = 'student';
      var uploadStatus = Resource.pendingStatus;
      try {
        final profile = fetchedProfile;
        if (profile != null &&
            profile.isNotEmpty &&
            isTeacherOrAdminProfile(profile)) {
          uploaderSource = 'teacher';
        }
      } catch (e) {
        debugPrint('Error fetching user role for upload: $e');
      }

      if (!mounted) return;
      final resourcePayload = <String, dynamic>{
        'college_id': widget.collegeId,
        'title': _title.trim(),
        'type': _typeIndex == 1 ? 'video' : _resourceType,
        'semester': _semester,
        'branch': _branch,
        'subject': _subject,
        'selectedScope': selectedScope,
        'source': uploaderSource,
        'is_teacher_upload': uploaderSource == 'teacher',
        if (_typeIndex == 0) 'file_url': filePath,
        if (_typeIndex == 1) 'video_url': resolvedVideoUrl,
        if (_typeIndex == 0) 'pdf_url': filePath,
        if (_typeIndex == 0 && fileSha256 != null) 'fileSha256': fileSha256,
        'description': _description.trim(),
        'chapter': _chapter.trim().isEmpty ? null : _chapter.trim(),
        'topic': _topic.trim().isEmpty ? null : _topic.trim(),
        'uploaded_by_name': authService.displayName ?? 'Anonymous',
        'uploaded_by_email': widget.userEmail,
        'status': uploadStatus,
      };

      if (shouldUseAdminResourceUpload) {
        await backendApi.createResourceAsAdmin(resourcePayload);
      } else {
        await backendApi.createResource(resourcePayload, context: context);
      }

      setState(() => _uploadProgress = 1.0);
      await Future.delayed(const Duration(milliseconds: 200));

      if (mounted) {
        // Capture overlay state and callback before popping context
        final overlayState = Overlay.of(context);
        final onComplete = widget.onUploadComplete;
        Navigator.pop(context); // Close upload dialog

        // Show non-blocking success overlay
        late OverlayEntry overlayEntry;
        bool isRemoved = false;

        overlayEntry = OverlayEntry(
          builder: (context) => SuccessOverlay(
            variant: SuccessOverlayVariant.contribution,
            title: 'Contribution Added',
            message: 'Resource submitted successfully!',
            badgeLabel: null,
            autoDismissDelay: const Duration(milliseconds: 3000),
            onDismiss: () {
              if (!isRemoved) {
                isRemoved = true;
                overlayEntry.remove();
                onComplete?.call();
              }
            },
          ),
        );

        overlayState.insert(overlayEntry);
      }
    } catch (e) {
      if (mounted) _showError('Submission failed: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : AppTheme.lightCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(context).viewInsets.bottom +
                      MediaQuery.of(context).padding.bottom +
                      20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.upload_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Share Resource',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppTheme.textOnDark
                                      : AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                'Help your peers learn',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (widget.prefilledFile != null &&
                        !_prefilledFileUnsupported) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.share_rounded,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Shared file attached: ${widget.prefilledFile!.name}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Type Toggle (compact)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.darkCard
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          _buildTypeChip(
                            0,
                            Icons.description_rounded,
                            'Notes',
                            isDark,
                          ),
                          _buildTypeChip(
                            1,
                            Icons.play_circle_rounded,
                            'Video',
                            isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    _buildInput(
                      controller: _titleController,
                      hint: 'Resource title',
                      onChanged: (v) => _title = v,
                      prefixIcon: Icons.title_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    // Semester & Branch Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildChipSelector(
                            'Sem',
                            semesterOptions,
                            _semester,
                            (v) => setState(() {
                              _semester = v;
                              _clearSubjectValue();
                            }),
                            isDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildChipSelector(
                            'Branch',
                            branches.keys.toList(),
                            _branch.isEmpty
                                ? ''
                                : branches.entries
                                      .firstWhere(
                                        (e) => e.value == _branch,
                                        orElse: () => const MapEntry('', ''),
                                      )
                                      .key,
                            (v) => setState(() {
                              _branch = branches[v] ?? '';
                              _clearSubjectValue();
                            }),
                            isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Subject
                    _buildChipSelector(
                      'Subject',
                      availableSubjects,
                      _subject,
                      (v) => setState(() => _setSubjectValue(v)),
                      isDark,
                      enabled: _canSelectSubject,
                      placeholder: _subjectSelectorLabel,
                    ),
                    const SizedBox(height: 12),

                    // Chapter & Topic
                    if (_subject.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(
                              hint: 'Chapter (Optional)',
                              onChanged: (v) => _chapter = v,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildInput(
                              hint: 'Topic (Optional)',
                              onChanged: (v) => _topic = v,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Resource Type (for notes)
                    if (_typeIndex == 0)
                      Row(
                        children: [
                          _buildMiniChip(
                            'Notes',
                            _resourceType == 'notes',
                            () => setState(() => _resourceType = 'notes'),
                            isDark,
                          ),
                          const SizedBox(width: 8),
                          _buildMiniChip(
                            'PYQ',
                            _resourceType == 'pyq',
                            () => setState(() => _resourceType = 'pyq'),
                            isDark,
                          ),
                        ],
                      ),
                    if (_typeIndex == 0) const SizedBox(height: 16),

                    // File Upload / Video URL
                    if (_typeIndex == 0)
                      _buildFileUpload(isDark)
                    else
                      _buildInput(
                        hint: 'YouTube / video URL',
                        onChanged: (v) => _videoUrl = v,
                        prefixIcon: Icons.link_rounded,
                        keyboardType: TextInputType.url,
                        isDark: isDark,
                      ),
                    const SizedBox(height: 16),

                    // Description
                    _buildInput(
                      hint: 'Description (Optional)',
                      onChanged: (v) => _description = v,
                      prefixIcon: Icons.description_outlined,
                      maxLines: 3,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),

                    // Progress with stages
                    if (_isUploading) ...[
                      // Stage indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStageIndicator(
                            'Preparing',
                            _uploadProgress >= 0.1,
                            _uploadProgress >= 0.2,
                          ),
                          _buildStageIndicator(
                            'Sending file',
                            _uploadProgress >= 0.2,
                            _uploadProgress >= 0.7,
                          ),
                          _buildStageIndicator(
                            'Saving',
                            _uploadProgress >= 0.7,
                            _uploadProgress >= 0.95,
                          ),
                          _buildStageIndicator(
                            'Done',
                            _uploadProgress >= 0.95,
                            _uploadProgress >= 1.0,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _getUploadStageText(),
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${(_uploadProgress * 100).toInt()}%',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _uploadProgress,
                          backgroundColor: isDark
                              ? AppTheme.darkCard
                              : Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation(
                            AppTheme.primary,
                          ),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isUploading
                                ? null
                                : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300,
                              ),
                              foregroundColor: isDark
                                  ? Colors.white
                                  : AppTheme.textPrimary,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _isUploading ? null : _handleSubmit,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isUploading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.volunteer_activism_rounded,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _typeIndex == 0
                                            ? 'Contribute'
                                            : 'Share',
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(int index, IconData icon, String label, bool isDark) {
    final isSelected = _typeIndex == index;
    // For unselected state in light mode, textMuted is fine (grayish).
    // isSelected will be Primary + White Text.
    final unselectedTextColor = isDark
        ? AppTheme.textMuted
        : AppTheme.textPrimary.withValues(alpha: 0.6);
    return Expanded(
      child: GestureDetector(
        onTap: _isUploading ? null : () => setState(() => _typeIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : unselectedTextColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : unselectedTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageIndicator(String label, bool isActive, bool isComplete) {
    // Stage indicator likely OK with default colors but check darkCard usage
    // Active/Complete uses Primary/Success (OK). Inactive uses darkCard -> need light alternative.
    // However, this method doesn't take isDark as param, need to pass or infer?
    // Let's assume passed-in context or just use neutral grey for inactive.

    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isComplete
                ? AppTheme.success
                : (isActive
                      ? AppTheme.primary
                      : AppTheme.textMuted.withValues(alpha: 0.2)),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isComplete ? Icons.check : Icons.circle,
            size: 12,
            color: isComplete || isActive ? Colors.white : AppTheme.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? AppTheme.primary : AppTheme.textMuted,
          ),
        ),
      ],
    );
  }

  String _getUploadStageText() {
    if (_uploadProgress < 0.2) return 'Preparing submission...';
    if (_uploadProgress < 0.7) return 'Sending file...';
    if (_uploadProgress < 0.95) return 'Saving to database...';
    return 'Complete!';
  }

  Widget _buildInput({
    required String hint,
    required Function(String) onChanged,
    required bool isDark,
    TextEditingController? controller,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    final fillColor = isDark ? Colors.black26 : Colors.grey.shade100;
    final hintColor = isDark ? AppTheme.textMuted : Colors.grey.shade500;
    final textColor = isDark ? Colors.white : AppTheme.textPrimary;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      enabled: !_isUploading,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: GoogleFonts.inter(color: textColor, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: hintColor),
        filled: true,
        fillColor: fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 18, color: hintColor)
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildChipSelector(
    String label,
    List<String> items,
    String selected,
    Function(String) onSelect,
    bool isDark, {
    bool enabled = true,
    String? placeholder,
  }) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.grey.shade100;
    final borderColor = isDark ? AppTheme.glassBorder : Colors.transparent;
    final textColor = isDark ? Colors.white : AppTheme.textPrimary;
    final hintColor = AppTheme.textMuted;
    final effectiveEnabled = enabled && items.isNotEmpty;
    final displayText = selected.isEmpty
        ? (placeholder ?? 'Select $label')
        : selected;

    return GestureDetector(
      onTap: _isUploading || !effectiveEnabled
          ? null
          : () => _showBottomSheetPicker(
              label,
              items,
              selected,
              onSelect,
              isDark,
            ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: selected.isEmpty
                      ? hintColor
                      : (effectiveEnabled
                            ? textColor
                            : textColor.withValues(alpha: 0.55)),
                ),
              ),
            ),
            Icon(
              effectiveEnabled
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.lock_outline_rounded,
              color: hintColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showBottomSheetPicker(
    String label,
    List<String> items,
    String selected,
    Function(String) onSelect,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkBorder : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Title
            Text(
              'Select $label',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            // Items
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = item == selected;
                  return ListTile(
                    title: Text(
                      item,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: isSelected
                            ? AppTheme.primary
                            : (isDark ? Colors.white : AppTheme.textPrimary),
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: AppTheme.primary,
                          )
                        : null,
                    onTap: () {
                      onSelect(item);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniChip(
    String label,
    bool isSelected,
    VoidCallback onTap,
    bool isDark,
  ) {
    final unselectedBg = isDark ? AppTheme.darkCard : Colors.grey.shade100;
    final unselectedBorder = isDark ? AppTheme.glassBorder : Colors.transparent;
    final unselectedText = isDark
        ? AppTheme.textMuted
        : AppTheme.textPrimary.withValues(alpha: 0.6);

    return GestureDetector(
      onTap: _isUploading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.2)
              : unselectedBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primary : unselectedBorder,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppTheme.primary : unselectedText,
          ),
        ),
      ),
    );
  }

  Widget _buildFileUpload(bool isDark) {
    final bg = isDark ? AppTheme.darkCard : Colors.grey.shade100;
    final borderColor = isDark ? AppTheme.glassBorder : Colors.transparent;
    final textColor = isDark ? Colors.white : AppTheme.textPrimary;

    return GestureDetector(
      onTap: _isUploading ? null : _pickFile,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _selectedFile != null ? AppTheme.success : borderColor,
            width: _selectedFile != null ? 2 : 1,
          ),
        ),
        child: _selectedFile != null
            ? Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppTheme.success,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFile!.name,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${(_selectedFile!.size / 1024 / 1024).toStringAsFixed(1)} MB',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _selectedFile = null),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_upload_rounded,
                    color: AppTheme.textMuted.withValues(alpha: 0.5),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tap to select file',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                      Text(
                        'PDF, DOC, PPT, TXT up to 50MB',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

/// Show upload dialog
Future<void> showUploadDialog(
  BuildContext context,
  String collegeId,
  String userEmail, {
  VoidCallback? onComplete,
  PlatformFile? prefilledFile,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => UploadResourceDialog(
      collegeId: collegeId,
      userEmail: userEmail,
      onUploadComplete: onComplete,
      prefilledFile: prefilledFile,
    ),
  );
}
