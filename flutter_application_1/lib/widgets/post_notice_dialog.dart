import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/department_option.dart';
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
  final imageUrlCtrl = TextEditingController();

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
                  value:
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
                TextField(
                  controller: imageUrlCtrl,
                  decoration: InputDecoration(
                    labelText: 'Image URL (optional)',
                    hintText: 'https://example.com/image.png',
                    labelStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                    hintStyle: GoogleFonts.inter(
                      color: AppTheme.textMuted.withValues(alpha: 0.5),
                    ),
                    prefixIcon: const Icon(Icons.image_outlined),
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
              onPressed: () async {
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

                final imageUrl = imageUrlCtrl.text.trim();
                if (imageUrl.isNotEmpty) {
                  final uri = Uri.tryParse(imageUrl);
                  final isValid =
                      uri != null &&
                      uri.isAbsolute &&
                      (uri.scheme == 'http' || uri.scheme == 'https');
                  if (!isValid) {
                    ScaffoldMessenger.of(parentCtx).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please enter a valid image URL (http/https)',
                        ),
                      ),
                    );
                    return;
                  }
                }

                try {
                  await supabaseService.addNotice(
                    collegeId: collegeId,
                    title: titleCtrl.text.trim(),
                    content: contentCtrl.text.trim(),
                    department: normalizedDept,
                    imageUrl: imageUrl.isEmpty ? null : imageUrl,
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
                  ScaffoldMessenger.of(parentCtx).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to post notice. Please try again.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text(
                'Post notice',
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
    imageUrlCtrl.dispose();
  }

  return posted;
}
