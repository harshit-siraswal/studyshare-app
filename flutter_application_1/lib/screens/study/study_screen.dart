
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../config/theme.dart';
import '../../models/resource.dart';
import '../notifications/notification_screen.dart';
import '../../providers/theme_provider.dart';
import '../../services/supabase_service.dart';
import '../../services/download_service.dart';
import '../../widgets/resource_card.dart';
import 'bookmarks_screen.dart';
import 'syllabus_screen.dart';
import 'resource_search_screen.dart';

class StudyScreen extends StatefulWidget {
  final String collegeId;
  final String collegeName;
  final String userEmail;
  final VoidCallback? onChangeCollege;

  const StudyScreen({
    super.key,
    required this.collegeId,
    required this.collegeName,
    required this.userEmail,
    this.onChangeCollege,
  });

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  // Tab state
  // int _selectedTabIndex = 0; // Removed unused
  
  // For You resources
  List<Resource> _resources = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  
  // Following resources
  List<Resource> _followingResources = [];
  bool _isLoadingFollowing = true;

  // Downloaded resources
  List<Resource> _downloadedResources = [];

  // Filters
  String? _selectedSemester;
  String? _selectedBranch;
  String? _selectedSubject;
  String? _selectedType;

  // Filter options
  List<String> _semesters = [];
  List<String> _branches = [];
  List<String> _subjects = [];
  final List<String> _types = ['All', 'Notes', 'Video', 'PYQ', 'Downloads'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);  // 3 tabs: For You, Following, Syllabus
    // _tabController.addListener(() { ... }); // Removed
    _loadFilters();
    _loadResources();
    _loadFollowingFeed();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playRetroSound() async {
    try {
      // User requested a retro machine sound. 
      // Ensure the file exists at assets/sounds/retro_scroll.mp3
      await _audioPlayer.stop(); // Stop previous to prevent overlap buildup
      await _audioPlayer.play(AssetSource('sounds/retro_scroll.mp3'), volume: 0.3);
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  Future<void> _loadFollowingFeed() async {
    try {
      final resources = await _supabaseService.getFollowingFeed(
        userEmail: widget.userEmail,
        collegeId: widget.collegeId,
      );
      setState(() {
        _followingResources = resources;
        _isLoadingFollowing = false;
      });
    } catch (e) {
      setState(() => _isLoadingFollowing = false);
    }
  }

  Future<void> _loadFilters() async {
    final semesters = await _supabaseService.getUniqueValues('semester', widget.collegeId);
    final branches = await _supabaseService.getUniqueValues('branch', widget.collegeId);
    
    setState(() {
      _semesters = ['All', ...semesters];
      _branches = ['All', ...branches];
    });
  }

  Future<void> _loadSubjects() async {
    if (_selectedBranch != null && _selectedBranch != 'All') {
      final subjects = await _supabaseService.getUniqueValues('subject', widget.collegeId);
      setState(() {
        _subjects = ['All', ...subjects];
      });
    } else {
      setState(() => _subjects = []);
    }
  }

  Future<void> _loadResources({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _resources = [];
        _isLoading = true;
      });
    }

    // Handle Downloads Filter
    if (_selectedType == 'Downloads') {
      setState(() {
        _resources = DownloadService().getAllDownloadedResources();
        _isLoading = false;
      });
      return;
    }

    try {
      final resources = await _supabaseService.getResources(
        collegeId: widget.collegeId,
        semester: _selectedSemester != 'All' ? _selectedSemester : null,
        branch: _selectedBranch != 'All' ? _selectedBranch : null,
        subject: _selectedSubject != 'All' ? _selectedSubject : null,
        type: _selectedType != 'All' ? _selectedType?.toLowerCase() : null,
        searchQuery: _searchController.text.isNotEmpty ? _searchController.text : null,
        offset: 0,
      );
      
      setState(() {
        _resources = resources;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreResources();
    }
  }

  Future<void> _loadMoreResources() async {
    if (_isLoadingMore || _isLoading) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      final moreResources = await _supabaseService.getResources(
        collegeId: widget.collegeId,
        semester: _selectedSemester != 'All' ? _selectedSemester : null,
        branch: _selectedBranch != 'All' ? _selectedBranch : null,
        subject: _selectedSubject != 'All' ? _selectedSubject : null,
        type: _selectedType != 'All' ? _selectedType?.toLowerCase() : null,
        searchQuery: _searchController.text.isNotEmpty ? _searchController.text : null,
        offset: _resources.length,
      );
      
      setState(() {
        _resources.addAll(moreResources);
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  // Unused method removed

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // Header
              _buildHeader(),
            
            // Tab Bar for For You / Following
            _buildTabBar(isDark),
            
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // For You Tab
                  Column(
                    children: [
                       _buildSearchBar(),
                       _buildQuickFilters(),
                       Expanded(
                         child: RefreshIndicator(
                            onRefresh: () => _loadResources(refresh: true),
                            color: AppTheme.primary,
                            child: _isLoading
                                ? _buildLoadingSkeleton()
                                : _resources.isEmpty
                                    ? _buildEmptyState()
                                    : _buildResourcesGrid(),
                          ),
                       ),
                    ],
                  ),
                  
                  // Following Tab
                  RefreshIndicator(
                    onRefresh: _loadFollowingFeed,
                    color: AppTheme.primary,
                    child: _isLoadingFollowing
                        ? _buildLoadingSkeleton()
                        : _followingResources.isEmpty
                            ? _buildFollowingEmptyState()
                            : _buildFollowingGrid(),
                  ),
                  // Syllabus Tab
                  _buildSyllabusTab(isDark),
                ],
              ),
            ),
          ],
        ), // Column
        ), // Padding
      ), // SafeArea
    ); // Scaffold
  }

  Widget _buildTabBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: AppTheme.primary,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.textMuted,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
        padding: const EdgeInsets.all(4),
        tabs: const [
          Tab(text: 'For You'),
          Tab(text: 'Following'),
          Tab(text: 'Syllabus'),
        ],
      ),
    );
  }

  Widget _buildFollowingEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline_rounded, size: 64, color: AppTheme.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            'No resources from people you follow',
            style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            'Follow students to see their uploads here',
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowingGrid() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _followingResources.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ResourceCard(
            resource: _followingResources[index],
            userEmail: widget.userEmail,
          ),
        );
      },
    );
  }

  Widget _buildSyllabusTab(bool isDark) {
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final secondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    
    // Department list with colors
    final departments = [
      {'name': 'CSE', 'full': 'Computer Science', 'color': const Color(0xFF8B5CF6)},
      {'name': 'ECE', 'full': 'Electronics & Comm', 'color': const Color(0xFF10B981)},
      {'name': 'EEE', 'full': 'Electrical Engg', 'color': const Color(0xFFF59E0B)},
      {'name': 'ME', 'full': 'Mechanical Engg', 'color': const Color(0xFFEF4444)},
      {'name': 'CE', 'full': 'Civil Engineering', 'color': const Color(0xFF6366F1)},
      {'name': 'IT', 'full': 'Information Tech', 'color': const Color(0xFF14B8A6)},
    ];
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Department',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'View syllabus by department',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 20),
          
          // Department Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
            ),
            itemCount: departments.length,
            itemBuilder: (context, index) {
              final dept = departments[index];
              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SyllabusScreen(
                        collegeId: widget.collegeId,
                        department: dept['name'] as String,
                        departmentName: dept['full'] as String,
                        departmentColor: dept['color'] as Color,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: (dept['color'] as Color).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            dept['name'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: dept['color'] as Color,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        dept['full'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: textColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: 24),
          
          // Semester selector hint
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Select a department to view semester-wise syllabus PDFs',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          // College badge - Wrapped in Flexible to prevent overflow
          Flexible(
            child: InkWell(
              onTap: widget.onChangeCollege,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school_rounded, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.collegeName.length > 15 
                            ? '${widget.collegeName.substring(0, 12)}...'
                            : widget.collegeName,
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.onChangeCollege != null) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down_rounded, size: 16, color: AppTheme.primary),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          // Bookmarks button
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BookmarksScreen(
                    userEmail: widget.userEmail,
                    collegeId: widget.collegeId,
                  ),
                ),
              );
            },
            icon: Icon(
              Icons.bookmark_outline_rounded,
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
            ),
          ),
          // Notification bell
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationScreen()),
              );
            },
            icon: Icon(
              Icons.notifications_outlined,
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActiveFilters = (_selectedSemester != null && _selectedSemester != 'All') ||
        (_selectedBranch != null && _selectedBranch != 'All') ||
        _selectedSubject != null ||
        (_selectedType != null && _selectedType != 'All');

    return GestureDetector(
      onTap: () {
         Navigator.of(context).push(
           PageRouteBuilder(
             pageBuilder: (context, animation, secondaryAnimation) => ResourceSearchScreen(
               collegeId: widget.collegeId,
               userEmail: widget.userEmail,
             ),
             transitionsBuilder: (context, animation, secondaryAnimation, child) {
               const begin = Offset(0.0, 0.05); 
               const end = Offset.zero;
               const curve = Curves.easeOutCubic;
               var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
               return FadeTransition(
                 opacity: animation,
                 child: SlideTransition(position: animation.drive(tween), child: child),
               );
             },
             transitionDuration: const Duration(milliseconds: 200),
           ),
         );
      },
      child: Container(
        height: 50,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(30), // Rounded
          border: Border.all(
            color: isDark ? Colors.white24 : Colors.black12,
            width: 0.5,
          ),
          boxShadow: [
             if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              color: isDark ? Colors.grey : Colors.black54,
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              'Search resources...',
              style: GoogleFonts.inter(
                color: isDark ? const Color(0xFF8E8E93) : Colors.grey.shade400,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            const Spacer(),
            // Filter Icon Button
            GestureDetector(
              onTap: _showFilterOptionsSheet,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: hasActiveFilters ? AppTheme.primary : (isDark ? Colors.grey[800] : Colors.grey[200]),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: hasActiveFilters ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Horizontal list of resource type filters
  Widget _buildQuickFilters() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = _types[index];
          final isSelected = _selectedType == type || (_selectedType == null && type == 'All');
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedType = type == 'All' ? null : type;
                _loadResources(refresh: true);
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : (isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.primary : (isDark ? Colors.white24 : Colors.grey.shade300),
                  width: 0.5,
                ),
              ),
              child: Text(
                type,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showFilterOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Use transparent to handle rounded corners
      isScrollControlled: true,
      builder: (context) => _buildFilterSheetContent(),
    );
  }

  Widget _buildFilterSheetContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black;
    final subTitleColor = isDark ? Colors.grey : Colors.black54;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, 
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Title / Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Reset all
                    setState(() {
                      _selectedSemester = null;
                      _selectedBranch = null;
                      _selectedSubject = null;
                      _selectedType = null;
                      _loadResources(refresh: true);
                    });
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Reset',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Semester - Dropdown Select
                  Text('Semester', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: subTitleColor)),
                  const SizedBox(height: 12),
                  _buildFilterDropdown(
                    value: _selectedSemester ?? 'All',
                    items: _semesters,
                    onChanged: (val) {
                      setState(() {
                        _selectedSemester = val == 'All' ? null : val;
                        _loadResources(refresh: true);
                      });
                      (context as Element).markNeedsBuild();
                    },
                    isDark: isDark,
                  ),
                    
                  const SizedBox(height: 24),

                  // Branch - Dropdown Select
                  Text('Branch', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: subTitleColor)),
                  const SizedBox(height: 12),
                  _buildFilterDropdown(
                    value: _selectedBranch ?? 'All',
                    items: _branches,
                    onChanged: (val) {
                      setState(() {
                        _selectedBranch = val == 'All' ? null : val;
                        _loadResources(refresh: true);
                        _loadSubjects();
                      });
                      (context as Element).markNeedsBuild();
                    },
                    isDark: isDark,
                  ),
                    
                   const SizedBox(height: 24),
                   
                   // Subject - Dropdown Select (always visible, disabled if no branch)
                   Text('Subject', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: subTitleColor)),
                   const SizedBox(height: 12),
                   _buildFilterDropdown(
                     value: _selectedSubject ?? 'Select...',
                     items: _subjects.isEmpty ? ['Select a branch first'] : _subjects,
                     onChanged: _selectedBranch == null || _selectedBranch == 'All' ? null : (val) {
                       setState(() {
                         _selectedSubject = val == 'All' ? null : val;
                         _loadResources(refresh: true);
                       });
                       (context as Element).markNeedsBuild();
                     },
                     isDark: isDark,
                     enabled: _selectedBranch != null && _selectedBranch != 'All',
                   ),
                ],
              ),
            ),
          ),
          
          // Apply Button Area
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
            ),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(
                'Show Results',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactFilterChip(String label, bool isSelected, Function(bool) onSelected) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: onSelected,
        selectedColor: AppTheme.primary.withValues(alpha: 0.2),
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          color: isSelected ? AppTheme.primary : (isDark ? Colors.white : Colors.black87),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : (isDark ? Colors.white24 : Colors.grey.shade300),
          width: 0.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        visualDensity: VisualDensity.compact,
      );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required Function(String)? onChanged,
    required bool isDark,
    bool enabled = true,
  }) {
    return GestureDetector(
      onTap: enabled && onChanged != null ? () {
        _showPickerSheet(
          title: 'Select',
          items: items,
          selectedValue: value,
          onSelected: onChanged,
          isDark: isDark,
        );
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white24 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: enabled 
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.grey : Colors.grey.shade500),
                fontWeight: FontWeight.w500,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: enabled 
                  ? (isDark ? Colors.white70 : Colors.black54)
                  : (isDark ? Colors.grey.shade700 : Colors.grey.shade400),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _showPickerSheet({
    required String title,
    required List<String> items,
    required String selectedValue,
    required Function(String) onSelected,
    required bool isDark,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Items list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = item == selectedValue;
                  return ListTile(
                    title: Text(
                      item,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? AppTheme.primary : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    trailing: isSelected 
                        ? const Icon(Icons.check_rounded, color: AppTheme.primary, size: 20)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelected(item);
                    },
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  void _showSubjectPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkBorder : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Subject',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.textLight,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text('All Subjects', style: GoogleFonts.inter(color: isDark ? Colors.white : AppTheme.textLight)),
              trailing: _selectedSubject == null 
                  ? const Icon(Icons.check_circle, color: AppTheme.primary) 
                  : null,
              onTap: () {
                setState(() => _selectedSubject = null);
                _loadResources(refresh: true);
                Navigator.pop(context);
              },
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _subjects.length,
                itemBuilder: (context, index) {
                  final subject = _subjects[index];
                  return ListTile(
                    title: Text(subject, style: GoogleFonts.inter(color: isDark ? Colors.white : AppTheme.textLight)),
                    trailing: _selectedSubject == subject 
                        ? const Icon(Icons.check_circle, color: AppTheme.primary) 
                        : null,
                    onTap: () {
                      setState(() => _selectedSubject = subject);
                      _loadResources(refresh: true);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourcesGrid() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Stack(
      children: [
        ListWheelScrollView.useDelegate(
          controller: _scrollController,
          itemExtent: 220, // Fixed height for cards
          perspective: 0.003,
          diameterRatio: 2.0, // Adjusts the curve
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (index) {
            _playRetroSound();
            // Optional: trigger load more if needed
          },
          childDelegate: ListWheelChildBuilderDelegate(
            builder: (context, index) {
              if (_resources.isEmpty) return null;
              final resource = _resources[index % _resources.length];
              
              return Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ResourceCard(
                    resource: resource,
                    userEmail: widget.userEmail,
                    onVoteChanged: () => _loadResources(),
                  ),
                ),
              );
            },
            childCount: null, // Infinite loop
          ),
        ),
        
        // Gradient Fade at Bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 140, // Height of the fade
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    (isDark ? AppTheme.darkBackground : AppTheme.lightBackground).withOpacity(0.0),
                    (isDark ? AppTheme.darkBackground : AppTheme.lightBackground),
                  ],
                  stops: const [0.0, 0.8],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => _buildLoadingCard(),
    );
  }

  Widget _buildLoadingCard() {
    return Shimmer.fromColors(
      baseColor: AppTheme.darkCard,
      highlightColor: AppTheme.darkBorder,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 80,
            color: AppTheme.textMuted.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No resources found',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters or search',
            style: GoogleFonts.inter(color: AppTheme.textMuted.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _selectedSemester = null;
                _selectedBranch = null;
                _selectedSubject = null;
                _selectedType = null;
                _searchController.clear();
              });
              _loadResources(refresh: true);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reset Filters'),
          ),
        ],
      ),
    );
  }

  // Legacy filter methods removed


  void _loadDownloadedResources() {
    setState(() {
      _downloadedResources = DownloadService().getAllDownloadedResources();
    });
  }

  Widget _buildDownloadsTab() {
    if (_downloadedResources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.offline_pin_rounded, size: 64, color: AppTheme.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No downloads yet',
              style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              'Download notes to access them offline',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted.withValues(alpha: 0.7)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _downloadedResources.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ResourceCard(
            resource: _downloadedResources[index],
            userEmail: widget.userEmail,
          ),
        );
      },
    );
  }
}
