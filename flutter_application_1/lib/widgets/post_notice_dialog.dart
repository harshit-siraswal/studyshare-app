import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../services/supabase_service.dart';

const List<Map<String, String>> _departmentOptions = [
  {'id': 'general', 'name': 'General Notices'},
  {'id': 'cse', 'name': 'Computer Science'},
  {'id': 'ece', 'name': 'Electronics & Comm'},
  {'id': 'eee', 'name': 'Electrical Engg'},
  {'id': 'me', 'name': 'Mechanical Engg'},
  {'id': 'ce', 'name': 'Civil Engineering'},
  {'id': 'it', 'name': 'Information Tech'},
];

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

  var selectedDept = 'general';
  var posted = false;

  try {
    await showDialog<void>(
      context: parentCtx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (stateCtx, setDialogState) => AlertDialog(
          backgroundColor: resolvedIsDark
              ? const Color(0xFF1C1C1E)
              : Colors.white,
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
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: GoogleFonts.inter(color: AppTheme.textMuted),
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
                  initialValue: selectedDept,
                  decoration: InputDecoration(
                    labelText: 'Department',
                    labelStyle: GoogleFonts.inter(color: AppTheme.textMuted),
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
                  items: _departmentOptions.map((dept) {
                    return DropdownMenuItem(
                      value: dept['id'],
                      child: Text(dept['name'] ?? ''),
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
              ),
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
                    department: selectedDept,
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
              child: Text(
                'Post',
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
