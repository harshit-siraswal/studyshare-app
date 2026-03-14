import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/department_option.dart';
import '../services/cloudinary_service.dart';
import '../services/backend_api_service.dart';
import '../services/supabase_service.dart';

Future<bool> showPostNoticeDialog({
  required BuildContext context,
  required String collegeId,
  bool? isDark,
}) async {
  final parentCtx = context;
  final resolvedIsDark =
      isDark ?? Theme.of(parentCtx).brightness == Brightness.dark;
  final supabaseService = SupabaseService();
  final titleCtrl = TextEditingController();
  final contentCtrl = TextEditingController();
  PlatformFile? selectedAttachment;
  var isSubmitting = false;
  const allowedAttachmentExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'pdf',
  ];
  const maxAttachmentBytes = 10 * 1024 * 1024;

  final uniqueDepartmentOptions = <DepartmentOption>[
    ...{
      for (final option in departmentOptions)
        if (option.id.trim().isNotEmpty && option.name.trim().isNotEmpty)
          option.id.trim(): DepartmentOption(
            id: option.id.trim(),
            name: option.name.trim(),
          ),
    }.values,
  ];
  String? selectedDept =
      uniqueDepartmentOptions.any((option) => option.id == 'general')
      ? 'general'
      : (uniqueDepartmentOptions.isNotEmpty
            ? uniqueDepartmentOptions.first.id
            : null);
  var posted = false;
  final dialogBg = resolvedIsDark ? const Color(0xFF1C1C1E) : Colors.white;
  final fieldFill = resolvedIsDark
      ? const Color(0xFF2C2C2E)
      : const Color(0xFFF3F4F6);

  String fileExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  bool isDocumentAttachment(PlatformFile file) {
    final ext = fileExtension(file.name);
    return ext == 'pdf';
  }

  bool isImageAttachment(PlatformFile file) =>
      !isDocumentAttachment(file) &&
      allowedAttachmentExtensions.contains(fileExtension(file.name));

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> pickAttachment(StateSetter setDialogState) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedAttachmentExtensions,
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.size > maxAttachmentBytes) {
        if (!parentCtx.mounted) return;
        ScaffoldMessenger.of(parentCtx).showSnackBar(
          const SnackBar(content: Text('Attachment must be under 10MB.')),
        );
        return;
      }

      setDialogState(() => selectedAttachment = file);
    } catch (e) {
      debugPrint('Notice attachment pick failed: $e');
      if (!parentCtx.mounted) return;
      ScaffoldMessenger.of(parentCtx).showSnackBar(
        const SnackBar(content: Text('Unable to pick attachment right now.')),
      );
    }
  }

  try {
    await showDialog<void>(
      context: parentCtx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (stateCtx, setDialogState) => AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          title: Row(
            children: [
              Icon(Icons.campaign_rounded, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                'Post Notice',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: resolvedIsDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Share important updates with your campus.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.title_rounded),
                    filled: true,
                    fillColor: fieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  style: GoogleFonts.inter(
                    color: resolvedIsDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Content',
                    alignLabelWithHint: true,
                    labelStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.notes_rounded),
                    filled: true,
                    fillColor: fieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  style: GoogleFonts.inter(
                    color: resolvedIsDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue:
                      uniqueDepartmentOptions.any(
                        (option) => option.id == selectedDept,
                      )
                      ? selectedDept
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Department',
                    labelStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.apartment_rounded),
                    filled: true,
                    fillColor: fieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  dropdownColor: resolvedIsDark
                      ? const Color(0xFF2C2C2E)
                      : Colors.white,
                  style: GoogleFonts.inter(
                    color: resolvedIsDark ? Colors.white : Colors.black,
                    fontSize: 14,
                  ),
                  items: uniqueDepartmentOptions.map((dept) {
                    return DropdownMenuItem(
                      value: dept.id,
                      child: Text(dept.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedDept = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: fieldFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: resolvedIsDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            selectedAttachment != null
                                ? (isDocumentAttachment(selectedAttachment!)
                                      ? Icons.description_rounded
                                      : Icons.image_rounded)
                                : Icons.attach_file_rounded,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedAttachment == null
                                  ? 'Attach image or PDF'
                                  : selectedAttachment!.name,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: resolvedIsDark
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                          ),
                          if (selectedAttachment != null)
                            IconButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () {
                                      setDialogState(
                                        () => selectedAttachment = null,
                                      );
                                    },
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: 'Remove attachment',
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        selectedAttachment == null
                            ? 'Optional. Add an image or PDF. It will open inside the app.'
                            : '${isDocumentAttachment(selectedAttachment!) ? 'Document' : 'Image'} • ${formatBytes(selectedAttachment!.size)}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: isSubmitting
                                  ? null
                                  : () => pickAttachment(setDialogState),
                              icon: Icon(
                                selectedAttachment == null
                                    ? Icons.upload_file_rounded
                                    : Icons.autorenew_rounded,
                              ),
                              label: Text(
                                selectedAttachment == null
                                    ? 'Choose file'
                                    : 'Change file',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                side: BorderSide(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                textStyle: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isSubmitting) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: AppTheme.textMuted),
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: isSubmitting
                  ? null
                  : () async {
                if (titleCtrl.text.trim().isEmpty ||
                    contentCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(parentCtx).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill title and content'),
                    ),
                  );
                  return;
                }
                final normalizedDept = (selectedDept ?? '').trim();
                if (uniqueDepartmentOptions.isEmpty || normalizedDept.isEmpty) {
                  ScaffoldMessenger.of(parentCtx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please select a valid department before posting.',
                      ),
                    ),
                  );
                  return;
                }

                try {
                  setDialogState(() => isSubmitting = true);
                  String? uploadedFileUrl;
                  String? uploadedImageUrl;
                  String? uploadedFileType;
                  final attachment = selectedAttachment;
                  if (attachment != null) {
                    final ext = fileExtension(attachment.name);
                    uploadedFileType = ext == 'pdf' ? 'pdf' : 'image';
                    uploadedFileUrl = await CloudinaryService.uploadFile(
                      attachment,
                      timeout: const Duration(seconds: 90),
                    );
                    if (isImageAttachment(attachment)) {
                      uploadedImageUrl = uploadedFileUrl;
                    }
                  }

                  await supabaseService.addNotice(
                    collegeId: collegeId,
                    title: titleCtrl.text.trim(),
                    content: contentCtrl.text.trim(),
                    department: normalizedDept,
                    imageUrl: uploadedImageUrl,
                    fileUrl: uploadedFileUrl,
                    fileType: uploadedFileType,
                  );
                  posted = true;
                  if (!parentCtx.mounted) return;
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(parentCtx).showSnackBar(
                    const SnackBar(
                      content: Text('Notice posted successfully!'),
                    ),
                  );
                } catch (e) {
                  debugPrint('Post notice failed: $e');
                  if (!parentCtx.mounted) return;
                  final errorMessage = e is BackendApiHttpException
                      ? e.message.trim()
                      : e.toString().replaceFirst('Exception: ', '').trim();
                  ScaffoldMessenger.of(parentCtx).showSnackBar(
                    SnackBar(
                      content: Text(
                        errorMessage.isNotEmpty
                            ? errorMessage
                            : 'Failed to post notice. Please try again.',
                      ),
                    ),
                  );
                } finally {
                  if (!posted && parentCtx.mounted) {
                    setDialogState(() => isSubmitting = false);
                  }
                }
              },
              icon: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(
                isSubmitting ? 'Posting...' : 'Post notice',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  } finally {
    titleCtrl.dispose();
    contentCtrl.dispose();
  }

  return posted;
}
