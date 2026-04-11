import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../config/theme.dart';
import '../../models/college.dart';
import '../../services/supabase_service.dart';

class CollegeSelectionScreen extends StatefulWidget {
  final Function(String id, String name, String domain) onCollegeSelected;

  const CollegeSelectionScreen({super.key, required this.onCollegeSelected});

  @override
  State<CollegeSelectionScreen> createState() => _CollegeSelectionScreenState();
}

class _CollegeSelectionScreenState extends State<CollegeSelectionScreen> {
  static const String _collegeRequestEmail = AppConfig.supportEmail;
  static const Duration _collegeFetchTimeout = Duration(seconds: 8);
  static const List<Map<String, String>> _starterCollegeDirectory = [
    {
      'id': 'kiet',
      'name': 'KIET Group of Institutions',
      'domain': 'kiet.edu',
    },
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

  Future<void> _loadColleges() async {
    final starterDirectory = _buildStarterCollegeDirectory();

    try {
      final colleges = await _supabaseService.getColleges().timeout(
        _collegeFetchTimeout,
      );
      final effectiveColleges = colleges.isNotEmpty
          ? colleges
          : starterDirectory;

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

  void _selectCollege(College college) {
    widget.onCollegeSelected(college.id, college.name, college.domain);
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

                  // Search bar - Notion style
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.inter(
                        color: isDark
                            ? AppTheme.textOnDark
                            : AppTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search for your college...',
                        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppTheme.textMuted,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _filteredColleges.length,
      itemBuilder: (context, index) {
        final college = _filteredColleges[index];
        return _buildCollegeCard(college, isDark, index);
      },
    );
  }

  Widget _buildCollegeCard(College college, bool isDark, int index) {
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
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _selectCollege(college),
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
                  // College avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        college.initial,
                        style: GoogleFonts.inter(
                          fontSize: 20,
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
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppTheme.textOnDark
                                : AppTheme.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '@${college.domain}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Arrow icon
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Shimmer.fromColors(
            baseColor: isDark ? AppTheme.darkCard : Colors.grey.shade200,
            highlightColor: isDark ? AppTheme.darkBorder : Colors.grey.shade100,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
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
