import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/department_option.dart';
import '../../services/backend_api_service.dart';
import '../../services/supabase_service.dart';

/// Full-page notice composer. Replaces the old `showPostNoticeDialog`
/// AlertDialog so authors get room to write and preview the attachment.
///
/// Pops with `true` when a notice was posted, `false`/null otherwise.
class PostNoticeScreen extends StatefulWidget {
  final String collegeId;

  const PostNoticeScreen({super.key, required this.collegeId});

  @override
  State<PostNoticeScreen> createState() => _PostNoticeScreenState();
}

class _PostNoticeScreenState extends State<PostNoticeScreen> {
  static const List<String> _allowedAttachmentExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'pdf',
  ];
  static const int _maxAttachmentBytes = 10 * 1024 * 1024;

  final BackendApiService _backendApi = BackendApiService();
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();

  List<DepartmentOption> _departmentOptions = <DepartmentOption>[];
  String? _selectedDept;
  PlatformFile? _selectedAttachment;
  bool _isSubmitting = false;
  bool _isLoadingDepartments = true;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    List<DepartmentOption> fetched = <DepartmentOption>[];
    try {
      fetched = await _supabaseService.getNoticeDepartments();
    } catch (e) {
      debugPrint('Failed to load notice departments: $e');
    }
    final effective = fetched.isNotEmpty ? fetched : departmentOptions;
    final unique = <DepartmentOption>[
      ...{
        for (final option in effective)
          if (option.id.trim().isNotEmpty && option.name.trim().isNotEmpty)
            option.id.trim(): DepartmentOption(
              id: option.id.trim(),
              name: option.name.trim(),
            ),
      }.values,
    ];
    if (!mounted) return;
    setState(() {
      _departmentOptions = unique;
      _selectedDept = unique.any((option) => option.id == 'general')
          ? 'general'
          : (unique.isNotEmpty ? unique.first.id : null);
      _isLoadingDepartments = false;
    });
  }

  String _fileExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  bool _isDocumentAttachment(PlatformFile file) =>
      _fileExtension(file.name) == 'pdf';

  bool _isImageAttachment(PlatformFile file) =>
      !_isDocumentAttachment(file) &&
      _allowedAttachmentExtensions.contains(_fileExtension(file.name));

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedAttachmentExtensions,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.size > _maxAttachmentBytes) {
        _showSnack('Attachment must be under 10MB.');
        return;
      }
      if (!mounted) return;
      setState(() => _selectedAttachment = file);
    } catch (e) {
      debugPrint('Notice attachment pick failed: $e');
      _showSnack('Unable to pick attachment right now.');
    }
  }

  bool get _canSubmit =>
      !_isSubmitting &&
      _titleCtrl.text.trim().isNotEmpty &&
      _contentCtrl.text.trim().isNotEmpty &&
      (_selectedDept ?? '').trim().isNotEmpty;

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty || _contentCtrl.text.trim().isEmpty) {
      _showSnack('Please fill title and content');
      return;
    }
    final normalizedDept = (_selectedDept ?? '').trim();
    if (_departmentOptions.isEmpty || normalizedDept.isEmpty) {
      _showSnack('Please select a valid department before posting.');
      return;
    }

    setState(() => _isSubmitting = true);
    var posted = false;
    try {
      String? uploadedFileUrl;
      String? uploadedImageUrl;
      String? uploadedFileType;
      final attachment = _selectedAttachment;
      if (attachment != null) {
        final ext = _fileExtension(attachment.name);
        uploadedFileType = ext == 'pdf' ? 'pdf' : 'image';
        final uploadPlan = await _backendApi.getAdminUploadPresign(
          filename: attachment.name,
          category: 'notice',
        );
        final uploadUrl = uploadPlan['uploadUrl']?.toString().trim();
        final publicUrl = uploadPlan['publicUrl']?.toString().trim();
        if (uploadUrl == null ||
            uploadUrl.isEmpty ||
            publicUrl == null ||
            publicUrl.isEmpty) {
          throw const FormatException('Failed to get attachment upload URL.');
        }
        await _backendApi.uploadToPresignedUrl(
          file: attachment,
          uploadUrl: uploadUrl,
          contentType: _backendApi.inferContentType(attachment.name),
        );
        uploadedFileUrl = publicUrl;
        if (_isImageAttachment(attachment)) {
          uploadedImageUrl = uploadedFileUrl;
        }
      }

      await _supabaseService.addNotice(
        collegeId: widget.collegeId,
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        department: normalizedDept,
        imageUrl: uploadedImageUrl,
        fileUrl: uploadedFileUrl,
        fileType: uploadedFileType,
      );
      posted = true;
      if (!mounted) return;
      Navigator.pop(context, true);
      _showSnack('Notice posted successfully!');
    } catch (e) {
      debugPrint('Post notice failed: $e');
      if (!mounted) return;
      final errorMessage = e is BackendApiHttpException
          ? e.message.trim()
          : e.toString().replaceFirst('Exception: ', '').trim();
      _showSnack(
        errorMessage.isNotEmpty
            ? errorMessage
            : 'Failed to post notice. Please try again.',
      );
    } finally {
      if (!posted && mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF0B0F14) : Colors.white;
    final fieldFill = isDark ? const Color(0xFF1C1F26) : const Color(0xFFF3F4F6);
    final borderColor = isDark ? Colors.white10 : const Color(0xFFE2E8F0);
    final mutedColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Icon(Icons.campaign_rounded, color: AppTheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'Post Notice',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Share important updates with your campus. Notices reach every student following the department.',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: mutedColor,
              ),
            ),
            const SizedBox(height: 20),
            _buildLabel('Title', isDark),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              onChanged: (_) => setState(() {}),
              decoration: _fieldDecoration(
                hintText: 'e.g. Mid-semester exam schedule released',
                isDark: isDark,
                fillColor: fieldFill,
                borderColor: borderColor,
              ),
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            _buildLabel('Content', isDark),
            const SizedBox(height: 8),
            TextField(
              controller: _contentCtrl,
              maxLines: 8,
              minLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: _fieldDecoration(
                hintText:
                    'Write the full notice. Dates, venues, and links help students act quickly.',
                isDark: isDark,
                fillColor: fieldFill,
                borderColor: borderColor,
              ),
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _buildLabel('Department', isDark),
            const SizedBox(height: 8),
            if (_isLoadingDepartments)
              Container(
                height: 54,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: fieldFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Loading departments...',
                      style: GoogleFonts.inter(fontSize: 13, color: mutedColor),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue:
                    _departmentOptions.any(
                      (option) => option.id == _selectedDept,
                    )
                    ? _selectedDept
                    : null,
                decoration: _fieldDecoration(
                  hintText: 'Select department',
                  isDark: isDark,
                  fillColor: fieldFill,
                  borderColor: borderColor,
                ).copyWith(
                  prefixIcon: const Icon(Icons.apartment_rounded, size: 20),
                ),
                dropdownColor: isDark ? const Color(0xFF1C1F26) : Colors.white,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 14,
                ),
                items: _departmentOptions
                    .map(
                      (dept) => DropdownMenuItem(
                        value: dept.id,
                        child: Text(dept.name),
                      ),
                    )
                    .toList(),
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedDept = value);
                        }
                      },
              ),
            const SizedBox(height: 20),
            _buildLabel('Attachment', isDark),
            const SizedBox(height: 8),
            _buildAttachmentCard(isDark, fieldFill, borderColor, mutedColor),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isSubmitting) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  disabledBackgroundColor: AppTheme.primary.withValues(
                    alpha: 0.35,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _isSubmitting ? 'Posting...' : 'Post notice',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white70 : const Color(0xFF334155),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    required bool isDark,
    required Color fillColor,
    required Color borderColor,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.inter(
        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
        fontSize: 13.5,
      ),
      counterStyle: GoogleFonts.inter(
        fontSize: 11,
        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
      ),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppTheme.primary, width: 1.2),
      ),
    );
  }

  Widget _buildAttachmentCard(
    bool isDark,
    Color fieldFill,
    Color borderColor,
    Color mutedColor,
  ) {
    final attachment = _selectedAttachment;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fieldFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  attachment != null
                      ? (_isDocumentAttachment(attachment)
                            ? Icons.description_rounded
                            : Icons.image_rounded)
                      : Icons.attach_file_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment == null
                          ? 'Attach image or PDF'
                          : attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      attachment == null
                          ? 'Optional. It will open inside the app.'
                          : '${_isDocumentAttachment(attachment) ? 'Document' : 'Image'} • ${_formatBytes(attachment.size)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: mutedColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (attachment != null)
                IconButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() => _selectedAttachment = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove attachment',
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _pickAttachment,
              icon: Icon(
                attachment == null
                    ? Icons.upload_file_rounded
                    : Icons.autorenew_rounded,
                size: 18,
              ),
              label: Text(attachment == null ? 'Choose file' : 'Change file'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: BorderSide(
                  color: AppTheme.primary.withValues(alpha: 0.35),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
