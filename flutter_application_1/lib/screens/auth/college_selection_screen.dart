import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../config/theme.dart';
import '../../models/college.dart';
import '../../services/supabase_service.dart';
import '../../data/school_data.dart';

class CollegeSelectionScreen extends StatefulWidget {
  final Function(String id, String name, String domain, {String? selectedClass})
  onCollegeSelected;

  const CollegeSelectionScreen({super.key, required this.onCollegeSelected});

  @override
  State<CollegeSelectionScreen> createState() => _CollegeSelectionScreenState();
}

class _CollegeSelectionScreenState extends State<CollegeSelectionScreen> {
  static const String _collegeRequestEmail = AppConfig.supportEmail;
  static const Duration _collegeFetchTimeout = Duration(seconds: 8);
  static const List<Map<String, dynamic>> _starterCollegeDirectory = [
    {'id': 'kiet', 'name': 'KIET Group of Institutions', 'domain': 'kiet.edu'},
    {'id': 'iiitbh', 'name': 'IIIT Bhagalpur', 'domain': 'iiitbh.ac.in'},
    {
      'id': 'iiitsonepat',
      'name': 'IIIT Sonepat',
      'domain': 'iiitsonepat.ac.in',
    },
    {'id': 'abes', 'name': 'ABES Engineering College', 'domain': 'abes.ac.in'},
    {'id': 'du', 'name': 'Delhi University', 'domain': 'du.ac.in'},
    {
      'id': 'iitd',
      'name': 'Indian Institute of Technology Delhi',
      'domain': 'iitd.ac.in',
    },
    {
      'id': 'iitb',
      'name': 'Indian Institute of Technology Bombay',
      'domain': 'iitb.ac.in',
    },
    {
      'id': 'iitm',
      'name': 'Indian Institute of Technology Madras',
      'domain': 'smail.iitm.ac.in',
    },
    {
      'id': 'bitspilani',
      'name': 'Birla Institute of Technology and Science, Pilani',
      'domain': 'bits-pilani.ac.in',
    },
    {
      'id': 'vit',
      'name': 'Vellore Institute of Technology',
      'domain': 'vit.ac.in',
    },
    {
      'id': 'nittrichy',
      'name': 'National Institute of Technology Tiruchirappalli',
      'domain': 'nitt.edu',
    },
    {'id': 'anna', 'name': 'Anna University', 'domain': 'student.annauniv.edu'},
    {'id': 'amity', 'name': 'Amity University', 'domain': 'amity.edu'},
    {
      'id': 'srm',
      'name': 'SRM Institute of Science and Technology',
      'domain': 'srmist.edu.in',
    },
    {
      'id': 'manipal',
      'name': 'Manipal Institute of Technology',
      'domain': 'learner.manipal.edu',
    },
    {
      'id': 'thapar',
      'name': 'Thapar Institute of Engineering and Technology',
      'domain': 'thapar.edu',
    },
    {
      'id': 'coep',
      'name': 'COEP Technological University',
      'domain': 'coeptech.ac.in',
    },
    {'id': 'iiitn', 'name': 'IIIT Nagpur', 'domain': 'iiitn.ac.in'},
    {
      'id': 'usar',
      'name': 'University School of Automation and Robotics, GGSIPU',
      'domain': 'ipu.ac.in',
    },
    // Indian School - Kendriya Vidyalaya, IIT Delhi
    {
      'id': 'kviitdelhi',
      'name': 'Kendriya Vidyalaya, IIT Delhi',
      'domain': 'kviitdelhi.edu.in',
      'is_school': true,
    },
  ];

  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();

  List<College> _colleges = [];
  List<College> _filteredColleges = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final starterDirectory = _buildStarterCollegeDirectory();
    _colleges = starterDirectory;
    _filteredColleges = starterDirectory;
    _isLoading = starterDirectory.isEmpty;
    _loadColleges();
    _searchController.addListener(_filterColleges);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<College> _buildStarterCollegeDirectory() {
    return _starterCollegeDirectory
        .map(
          (entry) => College(
            id: entry['id'] ?? '',
            name: entry['name'] ?? '',
            domain: entry['domain'] ?? '',
            isSchool: entry['is_school'] == true,
          ),
        )
        .where(
          (college) =>
              college.id.isNotEmpty &&
              college.name.isNotEmpty &&
              college.domain.isNotEmpty,
        )
        .toList(growable: false);
  }

  List<College> _mergeCollegeDirectories(
    List<College> starterDirectory,
    List<College> remoteColleges,
  ) {
    final mergedColleges = <College>[];

    bool sameCollege(College left, College right) {
      final leftId = left.id.trim().toLowerCase();
      final rightId = right.id.trim().toLowerCase();
      if (leftId.isNotEmpty && leftId == rightId) return true;

      final leftDomain = left.domain.trim().toLowerCase();
      final rightDomain = right.domain.trim().toLowerCase();
      return leftDomain.isNotEmpty && leftDomain == rightDomain;
    }

    void addCollege(College college, {required bool replaceExisting}) {
      if (replaceExisting) {
        mergedColleges.removeWhere(
          (existing) => sameCollege(existing, college),
        );
      } else if (mergedColleges.any(
        (existing) => sameCollege(existing, college),
      )) {
        return;
      }
      mergedColleges.add(college);
    }

    for (final college in starterDirectory) {
      addCollege(college, replaceExisting: false);
    }
    for (final college in remoteColleges) {
      addCollege(college, replaceExisting: true);
    }

    return mergedColleges.toList(growable: false);
  }

  Future<void> _loadColleges() async {
    final starterDirectory = _buildStarterCollegeDirectory();

    try {
      final colleges = await _supabaseService.getColleges().timeout(
        _collegeFetchTimeout,
      );
      final effectiveColleges = _mergeCollegeDirectories(
        starterDirectory,
        colleges,
      );

      if (mounted) {
        setState(() {
          _colleges = effectiveColleges;
          _filteredColleges = effectiveColleges;
          _isLoading = false;
          _error = effectiveColleges.isEmpty
              ? 'No colleges are available right now. Please request your college via email.'
              : '';
        });
      }
    } catch (e) {
      debugPrint(
        'College list fetch failed. Falling back to starter directory: $e',
      );
      if (mounted) {
        setState(() {
          if (_colleges.isEmpty) {
            _colleges = starterDirectory;
            _filteredColleges = starterDirectory;
          }
          _error = starterDirectory.isEmpty
              ? 'Failed to load colleges. Please retry or request your college via email.'
              : '';
          _isLoading = false;
        });
      }
    }
  }

  void _filterColleges() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredColleges = _colleges;
      } else {
        _filteredColleges = _colleges
            .where((c) => c.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  void _selectCollege(College college) async {
    if (college.isSchool) {
      final selectedClass = await _showClassSelectionSheet(college);
      if (selectedClass == null || selectedClass.isEmpty) return;
      widget.onCollegeSelected(
        college.id,
        college.name,
        college.domain,
        selectedClass: selectedClass,
      );
      return;
    }
    widget.onCollegeSelected(college.id, college.name, college.domain);
  }

  Future<String?> _showClassSelectionSheet(College college) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final bgColor = isDark ? const Color(0xFF0F1116) : Colors.white;
          return Container(
            height: MediaQuery.of(context).size.height * 0.55,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Text(
                    'Select Your Class',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    itemCount: schoolClassOptions.length,
                    itemBuilder: (context, index) {
                      final classOption = schoolClassOptions[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          classOption,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.textMuted,
                        ),
                        onTap: () => Navigator.pop(context, classOption),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Logo with Notion-style animation
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Select Your College',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppTheme.textOnDark
                          : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose your institution to access personalized resources',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Search bar — compact, round, pill style
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.inter(
                        color: isDark
                            ? AppTheme.textOnDark
                            : AppTheme.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search for your college...',
                        hintStyle: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppTheme.textMuted,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // College list
            Expanded(child: _buildCollegeList(isDark)),

            // Request new college button
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      _openCollegeRequestEmail();
                    },
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: AppTheme.primary,
                    ),
                    label: Text(
                      "Can't find your college? Request to add it by email",
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollegeList(bool isDark) {
    if (_isLoading) {
      return _buildLoadingSkeleton(isDark);
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: AppTheme.error.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _error,
              style: GoogleFonts.inter(color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = '';
                });
                _loadColleges();
              },
              child: const Text('Retry'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _openCollegeRequestEmail,
              child: const Text('Request your college via email'),
            ),
          ],
        ),
      );
    }

    if (_filteredColleges.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: AppTheme.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No colleges found',
              style: GoogleFonts.inter(fontSize: 18, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: GoogleFonts.inter(
                color: AppTheme.textMuted.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _openCollegeRequestEmail,
              child: const Text('Request your college via email'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _filteredColleges.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: isDark
            ? AppTheme.darkBorder.withValues(alpha: 0.5)
            : AppTheme.lightBorder.withValues(alpha: 0.5),
        indent: 64,
      ),
      itemBuilder: (context, index) {
        final college = _filteredColleges[index];
        return _buildCollegeListItem(college, isDark, index);
      },
    );
  }

  Widget _buildCollegeListItem(College college, bool isDark, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index.clamp(0, 10) * 50)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectCollege(college),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
            child: Row(
              children: [
                // College avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      college.initial,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // College info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        college.name,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppTheme.textOnDark
                              : AppTheme.textPrimary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${college.domain}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Arrow icon
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(bool isDark) {
    final baseColor = isDark ? AppTheme.darkCard : Colors.grey.shade200;
    final highlightColor = isDark ? AppTheme.darkBorder : Colors.grey.shade100;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: 5,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: isDark
            ? AppTheme.darkBorder.withValues(alpha: 0.5)
            : AppTheme.lightBorder.withValues(alpha: 0.5),
        indent: 64,
      ),
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 120,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCollegeRequestEmail() async {
    final requestedName = _searchController.text.trim();
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: _collegeRequestEmail,
      queryParameters: {
        'subject': 'StudyShare College Add Request',
        'body': [
          'Hi,',
          '',
          'Please add my college to StudyShare.',
          if (requestedName.isNotEmpty)
            'Requested college name: $requestedName',
          'App version: ${AppConfig.appVersion}',
          '',
          'Thanks.',
        ].join('\n'),
      },
    );

    try {
      final launched = await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open email app. Please email $_collegeRequestEmail manually.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open email app. Please email $_collegeRequestEmail manually.',
          ),
        ),
      );
    }
  }
}
