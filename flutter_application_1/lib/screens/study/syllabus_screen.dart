import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../models/user.dart';
import '../../services/cloudinary_service.dart';
import '../../services/supabase_service.dart';
import '../viewer/pdf_viewer_screen.dart';
import '../../data/academic_subjects_data.dart';
import '../../utils/admin_access.dart';
import 'syllabus_upload_screen.dart';

class SyllabusScreen extends StatefulWidget {
  final String collegeId;
  final String department;
  final String departmentName;
  final Color departmentColor;
  final bool canUploadSyllabus;

  const SyllabusScreen({
    super.key,
    required this.collegeId,
    required this.department,
    required this.departmentName,
    required this.departmentColor,
    this.canUploadSyllabus = false,
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
  final List<String> _semesters = semesterOptions;
  List<String> _availableSubjects = [];

  @override
  void initState() {
    super.initState();
    _isTeacherOrAdmin = widget.canUploadSyllabus;
    if (!_isTeacherOrAdmin) {
      _checkTeacherRole();
    }
  }

  Future<void> _checkTeacherRole() async {
    try {
      final profile = await _supabaseService.getCurrentUserProfile(
        maxAttempts: 1,
      );
      if (mounted) {
        setState(() {
          _isTeacherOrAdmin =
              canUploadSyllabusProfile(profile) ||
              isTeacherOrAdminProfile(profile) ||
              resolveEffectiveProfileRole(profile) == AppRoles.moderator;
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
    return getSubjectsForBranchAndSemester(
      widget.department,
      _selectedSemester,
    );
  }

  bool get _canUploadSyllabus =>
      (_selectedSemester?.trim().isNotEmpty ?? false) &&
      (_selectedSubject?.trim().isNotEmpty ?? false);

  EdgeInsets get _contentPadding =>
      EdgeInsets.fromLTRB(16, 16, 16, _isTeacherOrAdmin ? 120 : 24);

  Future<void> _fetchSyllabus() async {
    if (_selectedSemester == null || _selectedSubject == null) return;

    setState(() {
      _isLoading = true;
      _hasFetched = true;
    });

    try {
      final normalizedDepartment = normalizeBranchCode(widget.department);
      final items = await _supabaseService.getSyllabus(
        collegeId: widget.collegeId,
        department: normalizedDepartment.isEmpty
            ? widget.department
            : normalizedDepartment,
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
                if (_isTeacherOrAdmin) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.departmentColor.withValues(
                        alpha: isDark ? 0.18 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: widget.departmentColor.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.upload_file_rounded,
                          color: widget.departmentColor,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Teacher flow: this branch is already selected. '
                            'Choose semester and subject, then post the syllabus PDF.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white70 : Colors.black87,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
      bottomNavigationBar: _isTeacherOrAdmin ? _buildUploadCta(isDark) : null,
    );
  }

  Widget _buildUploadCta(bool isDark) {
    final canUpload = _canUploadSyllabus;
    final disabledStart = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFE2E8F0);
    final disabledEnd = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFCBD5E1);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openUploadFlow,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: canUpload
                    ? <Color>[
                        widget.departmentColor,
                        Color.lerp(widget.departmentColor, Colors.black, 0.18)!,
                      ]
                    : <Color>[disabledStart, disabledEnd],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: (canUpload ? widget.departmentColor : Colors.black)
                      .withValues(alpha: isDark ? 0.22 : 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.library_add_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upload syllabus',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          canUpload
                              ? 'Sem $_selectedSemester - ${_selectedSubject ?? ''}'
                              : 'Select semester and subject first',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.88),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUploadFlow() async {
    final normalizedDepartment = normalizeBranchCode(widget.department);
    final resolvedDepartment = normalizedDepartment.isEmpty
        ? widget.department
        : normalizedDepartment;

    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) => SyllabusUploadScreen(
          collegeId: widget.collegeId,
          department: resolvedDepartment,
          departmentName: widget.departmentName,
          departmentColor: widget.departmentColor,
          initialSemester: _selectedSemester,
          initialSubject: _selectedSubject,
        ),
      ),
    );

    if (!mounted || result == null) return;
    if (result['didUpload'] != 'true') return;

    final semester = result['semester'];
    final subject = result['subject'];
    if (semester != null && semester.trim().isNotEmpty) {
      setState(() {
        _selectedSemester = semester.trim();
        _availableSubjects = getSubjectsForBranchAndSemester(
          widget.department,
          _selectedSemester,
        );
        _selectedSubject =
            subject != null && subject.trim().isNotEmpty ? subject.trim() : null;
      });
    }

    await _fetchSyllabus();
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
        padding: _contentPadding,
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
    return Padding(
      padding: _contentPadding,
      child: Center(
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
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Padding(
      padding: _contentPadding,
      child: Center(
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
      ),
    );
  }

  Widget _buildSyllabusList(bool isDark) {
    return ListView.separated(
      padding: _contentPadding,
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
    final normalizedDepartment = normalizeBranchCode(widget.department);
    final resolvedDepartment = normalizedDepartment.isEmpty
        ? widget.department
        : normalizedDepartment;
    PlatformFile? selectedPdf;
    var isUploading = false;
    const maxPdfBytes = 12 * 1024 * 1024;

    String formatBytes(int bytes) {
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
      }
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    String titleFromFileName(String filename) {
      final dot = filename.lastIndexOf('.');
      final base = dot > 0 ? filename.substring(0, dot) : filename;
      return base.replaceAll('_', ' ').trim();
    }

    Future<void> pickPdf(StateSetter setDialogState) async {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const <String>['pdf'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;

        final file = result.files.first;
        if (file.size > maxPdfBytes) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF must be under 12MB.')),
          );
          return;
        }

        setDialogState(() {
          selectedPdf = file;
          if (titleCtrl.text.trim().isEmpty) {
            titleCtrl.text = titleFromFileName(file.name);
          }
        });
      } catch (e) {
        debugPrint('Syllabus PDF pick failed: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to pick a PDF right now.')),
        );
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.upload_file_rounded, color: widget.departmentColor),
              const SizedBox(width: 8),
              Text(
                'Post Syllabus',
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildTag('Sem ${_selectedSemester ?? '?'}', isDark),
                    _buildTag(_selectedSubject ?? 'Choose subject', isDark),
                    _buildTag(resolvedDepartment, isDark),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                    filled: true,
                    fillColor: isDark
                        ? AppTheme.darkBackground
                        : Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkBackground
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.picture_as_pdf_rounded,
                            color: widget.departmentColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedPdf?.name ?? 'Attach syllabus PDF',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        selectedPdf == null
                            ? 'Pick a PDF file. Students will open it inside StudyShare.'
                            : 'PDF • ${formatBytes(selectedPdf!.size)}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: isUploading
                            ? null
                            : () => pickPdf(setDialogState),
                        icon: Icon(
                          selectedPdf == null
                              ? Icons.upload_file_rounded
                              : Icons.autorenew_rounded,
                        ),
                        label: Text(
                          selectedPdf == null ? 'Choose PDF' : 'Change PDF',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.departmentColor,
                          side: BorderSide(
                            color: widget.departmentColor.withValues(
                              alpha: 0.35,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          textStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isUploading) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: AppTheme.textMuted),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.departmentColor,
              ),
              onPressed: isUploading
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a title')),
                        );
                        return;
                      }
                      if (selectedPdf == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please choose a PDF to upload'),
                          ),
                        );
                        return;
                      }
                      if (!_canUploadSyllabus) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please select semester and subject first',
                            ),
                          ),
                        );
                        return;
                      }

                      var uploaded = false;
                      try {
                        setDialogState(() => isUploading = true);
                        final pdfUrl = await CloudinaryService.uploadFile(
                          selectedPdf!,
                          timeout: const Duration(seconds: 90),
                        );

                        await _supabaseService.uploadSyllabus(
                          collegeId: widget.collegeId,
                          department: resolvedDepartment,
                          semester: _selectedSemester!,
                          subject: _selectedSubject!,
                          title: titleCtrl.text.trim(),
                          fileUrl: pdfUrl,
                        );
                        uploaded = true;
                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Syllabus uploaded successfully!'),
                            ),
                          );
                          _fetchSyllabus();
                        }
                      } catch (e) {
                        debugPrint('Syllabus upload failed: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Upload failed: $e')),
                          );
                        }
                      } finally {
                        if (!uploaded && mounted) {
                          setDialogState(() => isUploading = false);
                        }
                      }
                    },
              icon: isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_rounded),
              label: Text(
                isUploading ? 'Uploading...' : 'Upload PDF',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(titleCtrl.dispose);
  }

}
