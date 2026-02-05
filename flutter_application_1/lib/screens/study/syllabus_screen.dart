import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../viewer/pdf_viewer_screen.dart';

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
  bool _isLoading = true;
  String? _selectedSemester;
  List<String> _availableSemesters = [];

  @override
  void initState() {
    super.initState();
    _loadSyllabus();
  }

  Future<void> _loadSyllabus() async {
    try {
      final items = await _supabaseService.getSyllabus(
        collegeId: widget.collegeId,
        department: widget.department,
      );
      
      // Extract unique semesters
      final semesters = items
          .map((item) => item['semester']?.toString() ?? '')
          .where((sem) => sem.isNotEmpty)
          .toSet()
          .toList();
      semesters.sort();
      
      if (mounted) {
        setState(() {
          _syllabusItems = items;
          _availableSemesters = semesters;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load syllabus. Please try again.')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_selectedSemester == null) return _syllabusItems;
    return _syllabusItems.where((item) {
      return item['semester']?.toString() == _selectedSemester;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: isDark ? Colors.white : Colors.black),
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
                    '${_syllabusItems.length} items',
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
          // Semester filter chips
          if (_availableSemesters.isNotEmpty)
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _availableSemesters.length + 1, // +1 for "All"
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildSemesterChip('All', null, isDark);
                  }
                  return _buildSemesterChip(
                    'Sem ${_availableSemesters[index - 1]}',
                    _availableSemesters[index - 1],
                    isDark,
                  );
                },
              ),
            ),
          
          const SizedBox(height: 8),
          
          // Content
          Expanded(
            child: _isLoading
                ? _buildShimmerLoading(isDark)
                : _filteredItems.isEmpty
                    ? _buildEmptyState(isDark)
                    : _buildSyllabusList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSemesterChip(String label, String? value, bool isDark) {
    final isSelected = _selectedSemester == value;
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _selectedSemester = value);
      },
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      selectedColor: widget.departmentColor.withValues(alpha: 0.2),
      checkmarkColor: widget.departmentColor,
      labelStyle: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        color: isSelected 
            ? widget.departmentColor 
            : (isDark ? Colors.white : Colors.black),
      ),
      side: BorderSide(
        color: isSelected 
            ? widget.departmentColor 
            : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
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
            'No syllabus available',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedSemester == null
                ? 'Syllabus for ${widget.departmentName} will be uploaded soon'
                : 'No syllabus for Semester $_selectedSemester',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSyllabusList(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        return _buildSyllabusCard(item, isDark);
      },
    );
  }

  Widget _buildSyllabusCard(Map<String, dynamic> item, bool isDark) {
    final title = item['title'] ?? item['name'] ?? 'Syllabus Document';
    final semester = item['semester']?.toString() ?? '';
    final fileUrl = item['file_url'] ?? item['url'] ?? '';
    final subject = item['subject'] ?? '';

    return Material(
      color: isDark ? AppTheme.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          if (fileUrl.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PdfViewerScreen(
                  pdfUrl: fileUrl,
                  title: title,
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No PDF available')),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
          ),
          child: Row(
            children: [
              // PDF Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.departmentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.picture_as_pdf_rounded,
                  color: widget.departmentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (semester.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: widget.departmentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Sem $semester',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: widget.departmentColor,
                              ),
                            ),
                          ),
                        if (semester.isNotEmpty && subject.isNotEmpty)
                          const SizedBox(width: 8),
                        if (subject.isNotEmpty)
                          Expanded(
                            child: Text(
                              subject,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
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
                color: AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
