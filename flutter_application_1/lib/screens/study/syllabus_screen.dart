import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../models/user.dart';
import '../../services/supabase_service.dart';
import '../viewer/pdf_viewer_screen.dart';
import '../../data/syllabus_subjects_data.dart'; // Import the new data file

class SyllabusScreen extends StatefulWidget {
  final String collegeId;
  final String department;
  final String departmentName;
  final Color departmentColor;

  const SyllabusScreen({
    super.key,
    required this.collegeId,
    required this.department,
    required this.departmentName,
    required this.departmentColor,
  });

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  final SupabaseService _supabaseService = SupabaseService();

  List<Map<String, dynamic>> _syllabusItems = [];
  bool _isLoading = false;
  bool _hasFetched = false;
  bool _isTeacherOrAdmin = false;

  // Selection State
  String? _selectedSemester;
  String? _selectedSubject;

  // Available Options
  final List<String> _semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];
  List<String> _availableSubjects = [];

  @override
  void initState() {
    super.initState();
    _checkTeacherRole();
  }

  Future<void> _checkTeacherRole() async {
    try {
      final profile = await _supabaseService.getCurrentUserProfile(
        maxAttempts: 1,
      );
      final role = await _supabaseService.getCurrentUserRole();
      final hasAdminKey =
          profile['admin_key']?.toString().trim().isNotEmpty == true;
      // TODO: uploadSyllabus must enforce admin_key verification server-side;
      // client-side key presence must never be the sole authorization gate.
      if (mounted) {
        setState(() {
          _isTeacherOrAdmin =
              role == AppRoles.teacher ||
              role == AppRoles.admin ||
              role == AppRoles.moderator ||
              hasAdminKey;
        });
      }
    } catch (e, st) {
      debugPrint('Failed to resolve teacher/admin role: $e\n$st');
      if (!mounted) return;
      setState(() => _isTeacherOrAdmin = false);
    }
  }

  void _onSemesterChanged(String? newValue) {
    final normalized = (newValue ?? '').trim();
    if (normalized.isEmpty) return;

    if (normalized == _selectedSemester) return;

    setState(() {
      _selectedSemester = normalized;
      _selectedSubject = null; // Reset subject
      _availableSubjects = _getSubjectsForBranch();
      _syllabusItems = []; // Clear list until subject selected
      _hasFetched = false;
    });
  }

  void _onSubjectChanged(String? newValue) {
    final normalized = (newValue ?? '').trim();
    if (normalized.isEmpty || normalized == _selectedSubject) return;

    setState(() {
      _selectedSubject = normalized;
    });

    _fetchSyllabus();
  }

  List<String> _getSubjectsForBranch() {
    // Map 'CSE' -> 'cse' for lookup
    final branchKey = widget.department.trim().toLowerCase();

    Branch? branch;
    try {
      branch = Branch.values.byName(branchKey);
    } on ArgumentError {
      branch = null;
    }
    if (branch == null) return [];

    final subjects = syllabusSubjects[branch] ?? [];
    final unique =
        subjects
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return unique;
  }

  Future<void> _fetchSyllabus() async {
    if (_selectedSemester == null || _selectedSubject == null) return;

    setState(() {
      _isLoading = true;
      _hasFetched = true;
    });

    try {
      final items = await _supabaseService.getSyllabus(
        collegeId: widget.collegeId,
        department: widget.department,
        semester: _selectedSemester,
        subject: _selectedSubject,
      );

      if (mounted) {
        setState(() {
          _syllabusItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load syllabus. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: widget.departmentColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  widget.department,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.departmentName} Syllabus',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Select Semester & Subject',
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
      ),
      body: Column(
        children: [
          // Filters Section
          Container(
            color: isDark ? AppTheme.darkCard : Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Semester Dropdown
                _buildDropdown(
                  label: 'Semester',
                  value: _selectedSemester,
                  items: _semesters,
                  onChanged: _onSemesterChanged,
                  icon: Icons.calendar_today_rounded,
                  isDark: isDark,
                  hint: 'Select Semester',
                ),

                const SizedBox(height: 12),

                // Subject Dropdown
                _buildDropdown(
                  label: 'Subject',
                  value: _selectedSubject,
                  items: _availableSubjects,
                  onChanged: _onSubjectChanged,
                  icon: Icons.book_rounded,
                  isDark: isDark,
                  hint: _selectedSemester == null
                      ? 'Select Semester First'
                      : (_availableSubjects.isEmpty
                            ? 'No subjects found'
                            : 'Select Subject'),
                  isDisabled: _selectedSemester == null,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Expanded(
            child: _isLoading
                ? _buildShimmerLoading(isDark)
                : (!_hasFetched)
                ? _buildInitialState(isDark)
                : _syllabusItems.isEmpty
                ? _buildEmptyState(isDark)
                : _buildSyllabusList(isDark),
          ),
        ],
      ),
      floatingActionButton: _isTeacherOrAdmin
          ? FloatingActionButton.extended(
              onPressed: () {
                if (_selectedSemester == null || _selectedSubject == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Select semester and subject before uploading.',
                      ),
                    ),
                  );
                  return;
                }
                _showUploadSyllabusDialog(isDark);
              },
              backgroundColor:
                  (_selectedSemester != null && _selectedSubject != null)
                  ? widget.departmentColor
                  : Colors.grey,
              icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
              label: Text(
                'Upload Syllabus',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    required IconData icon,
    required bool isDark,
    String? hint,
    bool isDisabled = false,
  }) {
    // Dropdown styling colors
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final bgColor = isDark ? AppTheme.darkBackground : Colors.grey[50];
    final textColor = isDark ? Colors.white : Colors.black;
    final selectedValue = (value != null && items.contains(value))
        ? value
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDisabled
            ? (isDark ? Colors.white10 : Colors.grey[100])
            : bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedValue,
          isExpanded: true,
          hint: Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.textMuted),
              const SizedBox(width: 10),
              Text(
                hint ?? label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: isDisabled ? Colors.grey : widget.departmentColor,
          ),
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
          dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
          onChanged: isDisabled ? null : onChanged,
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selectedValue == item
                        ? widget.departmentColor
                        : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(item),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading(bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
      highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          height: 80,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_list_rounded,
            size: 64,
            color: widget.departmentColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Select Filters',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a Semester and Subject\nto view syllabus documents',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 64,
            color: AppTheme.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No documents found',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No syllabus available for\n${_selectedSubject ?? 'Unknown'} (Sem ${_selectedSemester ?? '?'})',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSyllabusList(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _syllabusItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _syllabusItems[index];
        return _buildSyllabusCard(item, isDark);
      },
    );
  }

  Widget _buildSyllabusCard(Map<String, dynamic> item, bool isDark) {
    final title = item['title'] ?? item['name'] ?? 'Syllabus Document';
    final semester = item['semester']?.toString() ?? '';
    final fileUrl =
        item['pdf_url'] ??
        item['file_url'] ??
        item['url'] ??
        ''; // Web uses 'pdf_url'
    final subject = item['subject'] ?? '';

    // Note: 'pdf_url' seems to be the key in Web (SyllabusItem interface)
    // SupabaseService generally returns raw JSON, so check DB keys if needed.
    // Usually 'url' or 'file_url'. I added fallback to 'pdf_url'.

    return Material(
      color: isDark ? AppTheme.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: InkWell(
        onTap: () {
          if (fileUrl.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    PdfViewerScreen(pdfUrl: fileUrl, title: title),
              ),
            );
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('No PDF available')));
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // PDF Icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: widget.departmentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.picture_as_pdf_rounded,
                  color: widget.departmentColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildTag('Sem $semester', isDark),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            subject,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textMuted.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? Colors.white24 : Colors.grey[200]!),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : Colors.grey[700],
        ),
      ),
    );
  }

  void _showUploadSyllabusDialog(bool isDark) {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        title: Row(
          children: [
            Icon(Icons.upload_file_rounded, color: widget.departmentColor),
            const SizedBox(width: 8),
            Text(
              'Upload Syllabus',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
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
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: InputDecoration(
                  labelText: 'PDF URL',
                  hintText: 'https://example.com/file.pdf',
                  labelStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                  hintStyle: GoogleFonts.inter(
                    color: AppTheme.textMuted.withValues(alpha: 0.5),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sem: ${_selectedSemester ?? '?'} • ${_selectedSubject ?? 'Select subject first'} • ${widget.department}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.departmentColor,
            ),
            onPressed: () async {
              if (titleCtrl.text.isEmpty || urlCtrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
                return;
              }
              final pdfUrl = urlCtrl.text.trim();
              final uri = Uri.tryParse(pdfUrl);
              if (uri == null ||
                  !uri.isAbsolute ||
                  !(uri.scheme == 'http' || uri.scheme == 'https')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid PDF URL (http/https)'),
                  ),
                );
                return;
              }
              if (_selectedSemester == null || _selectedSubject == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please select semester and subject first'),
                  ),
                );
                return;
              }
              try {
                await _supabaseService.uploadSyllabus(
                  collegeId: widget.collegeId,
                  department: widget.department,
                  semester: _selectedSemester!,
                  subject: _selectedSubject!,
                  title: titleCtrl.text.trim(),
                  fileUrl: pdfUrl,
                );
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Syllabus uploaded successfully!'),
                    ),
                  );
                  _fetchSyllabus(); // Refresh the list
                }
              } catch (e) {
                debugPrint('Syllabus upload failed: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Upload failed. Please try again.'),
                    ),
                  );
                }
              }
            },
            child: Text(
              'Upload',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      titleCtrl.dispose();
      urlCtrl.dispose();
    });
  }
}
