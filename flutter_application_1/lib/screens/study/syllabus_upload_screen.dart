import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../data/academic_subjects_data.dart';
import '../../services/cloudinary_service.dart';
import '../../services/supabase_service.dart';

class SyllabusUploadScreen extends StatefulWidget {
  final String collegeId;
  final String department;
  final String departmentName;
  final Color departmentColor;
  final String? initialSemester;
  final String? initialSubject;

  const SyllabusUploadScreen({
    super.key,
    required this.collegeId,
    required this.department,
    required this.departmentName,
    required this.departmentColor,
    this.initialSemester,
    this.initialSubject,
  });

  @override
  State<SyllabusUploadScreen> createState() => _SyllabusUploadScreenState();
}

class _SyllabusUploadScreenState extends State<SyllabusUploadScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _titleController = TextEditingController();

  final List<String> _semesters = semesterOptions;
  List<String> _availableSubjects = [];

  String? _selectedSemester;
  String? _selectedSubject;
  PlatformFile? _selectedPdf;
  bool _isUploading = false;

  static const int _maxPdfBytes = 12 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _selectedSemester = widget.initialSemester;
    _selectedSubject = widget.initialSubject;
    _availableSubjects = _getSubjectsForBranch();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  List<String> _getSubjectsForBranch() {
    return getSubjectsForBranchAndSemester(
      widget.department,
      _selectedSemester,
    );
  }

  void _onSemesterChanged(String? newValue) {
    final normalized = (newValue ?? '').trim();
    if (normalized.isEmpty || normalized == _selectedSemester) return;
    setState(() {
      _selectedSemester = normalized;
      _selectedSubject = null;
      _availableSubjects = _getSubjectsForBranch();
    });
  }

  void _onSubjectChanged(String? newValue) {
    final normalized = (newValue ?? '').trim();
    if (normalized.isEmpty || normalized == _selectedSubject) return;
    setState(() => _selectedSubject = normalized);
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.size > _maxPdfBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF must be under 12MB.')),
        );
        return;
      }

      setState(() {
        _selectedPdf = file;
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = _titleFromFileName(file.name);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to pick a PDF right now.')),
      );
    }
  }

  String _titleFromFileName(String filename) {
    final dot = filename.lastIndexOf('.');
    final base = dot > 0 ? filename.substring(0, dot) : filename;
    return base.replaceAll('_', ' ').trim();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get _canUpload =>
      (_selectedSemester?.trim().isNotEmpty ?? false) &&
      (_selectedSubject?.trim().isNotEmpty ?? false) &&
      _selectedPdf != null &&
      _titleController.text.trim().isNotEmpty;

  Future<void> _submitUpload() async {
    if (_selectedSemester == null || _selectedSemester!.trim().isEmpty) {
      _showSnack('Please select a semester.');
      return;
    }
    if (_selectedSubject == null || _selectedSubject!.trim().isEmpty) {
      _showSnack('Please select a subject.');
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      _showSnack('Please enter a title.');
      return;
    }
    if (_selectedPdf == null) {
      _showSnack('Please choose a PDF to upload.');
      return;
    }

    setState(() => _isUploading = true);
    try {
      final pdfUrl = await CloudinaryService.uploadFile(
        _selectedPdf!,
        timeout: const Duration(seconds: 90),
      );

      await _supabaseService.uploadSyllabus(
        collegeId: widget.collegeId,
        department: widget.department,
        semester: _selectedSemester!,
        subject: _selectedSubject!,
        title: _titleController.text.trim(),
        fileUrl: pdfUrl,
      );

      if (!mounted) return;
      Navigator.pop<Map<String, String>>(context, {
        'didUpload': 'true',
        'semester': _selectedSemester!,
        'subject': _selectedSubject!,
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('Upload failed: $e');
      setState(() => _isUploading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        title: Text(
          'Upload Syllabus',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
        children: [
          _headerCard(isDark),
          const SizedBox(height: 16),
          _buildStepCard(
            stepLabel: 'Step 1',
            title: 'Course details',
            subtitle: 'Choose the semester and subject for this syllabus.',
            isDark: isDark,
            child: Column(
              children: [
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
          const SizedBox(height: 14),
          _buildStepCard(
            stepLabel: 'Step 2',
            title: 'Upload PDF',
            subtitle: 'Attach the official syllabus document.',
            isDark: isDark,
            child: _filePickerCard(isDark),
          ),
          const SizedBox(height: 14),
          _buildStepCard(
            stepLabel: 'Step 3',
            title: 'Title & confirmation',
            subtitle: 'Give it a clear title for students to search.',
            isDark: isDark,
            child: Column(
              children: [
                _titleField(isDark),
                const SizedBox(height: 12),
                _summaryCard(isDark),
                const SizedBox(height: 12),
                _guidelinesCard(isDark),
              ],
            ),
          ),
          if (_isUploading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      bottomNavigationBar: _bottomUploadBar(isDark),
    );
  }

  Widget _headerCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: widget.departmentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.menu_book_rounded,
              color: widget.departmentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.departmentName,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Upload a syllabus PDF for students in this department.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, bool isDark) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white70 : Colors.black54,
      ),
    );
  }

  Widget _buildStepCard({
    required String stepLabel,
    required String title,
    required String subtitle,
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.departmentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  stepLabel,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: widget.departmentColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black54,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _summaryCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          _summaryRow(
            'Semester',
            _selectedSemester?.trim().isNotEmpty == true
                ? _selectedSemester!
                : 'Not selected',
            isDark,
          ),
          const SizedBox(height: 8),
          _summaryRow(
            'Subject',
            _selectedSubject?.trim().isNotEmpty == true
                ? _selectedSubject!
                : 'Not selected',
            isDark,
          ),
          const SizedBox(height: 8),
          _summaryRow(
            'File',
            _selectedPdf?.name ?? 'No PDF selected',
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, bool isDark) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
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

  Widget _filePickerCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, color: widget.departmentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedPdf?.name ?? 'Attach syllabus PDF',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _selectedPdf == null
                ? 'Pick a PDF file. Students will open it inside StudyShare.'
                : 'PDF - ${_formatBytes(_selectedPdf!.size)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isUploading ? null : _pickPdf,
            icon: Icon(
              _selectedPdf == null
                  ? Icons.upload_file_rounded
                  : Icons.autorenew_rounded,
            ),
            label: Text(_selectedPdf == null ? 'Choose PDF' : 'Change PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.departmentColor,
              side: BorderSide(
                color: widget.departmentColor.withValues(alpha: 0.35),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleField(bool isDark) {
    return TextField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: 'Title',
        labelStyle: GoogleFonts.inter(color: AppTheme.textMuted),
        filled: true,
        fillColor: isDark ? AppTheme.darkBackground : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _guidelinesCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upload tips',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '- Use the official syllabus PDF\n'
            '- Keep the file under 12MB\n'
            '- Title should match the subject and semester',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomUploadBar(bool isDark) {
    final canUpload = _canUpload && !_isUploading;
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
          onTap: canUpload ? _submitUpload : null,
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
                    child: _isUploading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_upload_rounded,
                            color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isUploading ? 'Uploading...' : 'Upload syllabus',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedSemester == null || _selectedSubject == null
                              ? 'Select semester and subject'
                              : 'Sem $_selectedSemester - $_selectedSubject',
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
}
