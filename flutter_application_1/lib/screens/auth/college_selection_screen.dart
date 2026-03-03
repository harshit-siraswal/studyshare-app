import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
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
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();

  List<College> _colleges = [];
  List<College> _filteredColleges = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadColleges();
    _searchController.addListener(_filterColleges);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadColleges() async {
    try {
      final colleges = await _supabaseService.getColleges();
      if (mounted) {
        setState(() {
          _colleges = colleges;
          _filteredColleges = colleges;
          _isLoading = false;
          _error = colleges.isEmpty
              ? 'No colleges are available right now. You can still continue with manual setup.'
              : '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load colleges. Please retry or use manual setup.';
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
                      color: isDark ? AppTheme.textLight : AppTheme.textPrimary,
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
                            ? AppTheme.textLight
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
                    onPressed: () => _showManualCollegeDialog(isDark),
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: AppTheme.primary,
                    ),
                    label: Text(
                      'Use manual college setup',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _showRequestCollegeDialog(isDark);
                    },
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: AppTheme.primary,
                    ),
                    label: Text(
                      "Can't find your college? Request to add it",
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
              onPressed: () => _showManualCollegeDialog(isDark),
              child: const Text('Use manual setup'),
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
              onPressed: () => _showManualCollegeDialog(isDark),
              child: const Text('Use manual setup'),
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
                                ? AppTheme.textLight
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

  Future<void> _showRequestCollegeDialog(bool isDark) async {
    final parentContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(parentContext);
    final nameController = TextEditingController();
    final domainController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightCard,
      isScrollControlled: true, // Better for keyboards
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom:
                MediaQuery.of(context).viewInsets.bottom +
                24, // Handle keyboard
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request New College',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.textLight : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'If your college is not listed, you can request to add it.',
                style: GoogleFonts.inter(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 24),
              _buildStyledTextField(
                controller: nameController,
                hintText: 'College Name',
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildStyledTextField(
                controller: domainController,
                hintText: 'College Email Domain (e.g., college.edu)',
                isDark: isDark,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final domain = domainController.text.trim().toLowerCase();
                    if (name.isEmpty || domain.isEmpty) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('Please enter college name and domain'),
                        ),
                      );
                      return;
                    }
                    if (!_isValidDomain(domain)) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please enter a valid college domain (e.g., kiet.edu)',
                          ),
                        ),
                      );
                      return;
                    }

                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'College request submission is coming soon. Please contact support for now.',
                        ),
                      ),
                    );
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Request Coming Soon',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    // Dispose controllers after sheet is closed
    nameController.dispose();
    domainController.dispose();
  }

  Future<void> _showManualCollegeDialog(bool isDark) async {
    final parentContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(parentContext);
    final nameController = TextEditingController();
    final domainController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manual College Setup',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.textLight : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your college details to continue if listing is unavailable.',
                style: GoogleFonts.inter(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 18),
              _buildStyledTextField(
                controller: nameController,
                hintText: 'College Name',
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _buildStyledTextField(
                controller: domainController,
                hintText: 'College Domain (e.g., kiet.edu)',
                isDark: isDark,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final domain = domainController.text
                        .trim()
                        .toLowerCase()
                        .replaceAll('@', '');
                    if (name.isEmpty || domain.isEmpty) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('Please enter college name and domain'),
                        ),
                      );
                      return;
                    }
                    if (!_isValidDomain(domain)) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please enter a valid college domain (e.g., kiet.edu)',
                          ),
                        ),
                      );
                      return;
                    }

                    final generatedId =
                        'local-${domain.replaceAll('.', '-')}-${DateTime.now().millisecondsSinceEpoch}';
                    Navigator.pop(context);
                    _selectCollege(
                      College(
                        id: generatedId,
                        name: name,
                        domain: domain,
                        isActive: true,
                      ),
                    );
                  },
                  child: Text(
                    'Continue',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    nameController.dispose();
    domainController.dispose();
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String hintText,
    required bool isDark,
  }) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(
        color: isDark ? AppTheme.textLight : AppTheme.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
        filled: true,
        fillColor: isDark ? AppTheme.darkCard : AppTheme.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.4),
        ),
      ),
    );
  }

  bool _isValidDomain(String domain) {
    final pattern = RegExp(
      r'^(?!\.)(?!.*\.\.)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$',
    );
    return pattern.hasMatch(domain);
  }
}
