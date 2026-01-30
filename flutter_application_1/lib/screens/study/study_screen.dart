import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../models/resource.dart';
import '../../services/supabase_service.dart';
import '../../widgets/resource_card.dart';
import '../../widgets/upload_resource_dialog.dart';
import 'bookmarks_screen.dart';
import 'syllabus_screen.dart';

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
  int _selectedTabIndex = 0;
  
  // For You resources
  List<Resource> _resources = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  
  // Following resources
  List<Resource> _followingResources = [];
  bool _isLoadingFollowing = true;

  // Filters
  String? _selectedSemester;
  String? _selectedBranch;
  String? _selectedSubject;
  String? _selectedType;

  // Filter options
  List<String> _semesters = [];
  List<String> _branches = [];
  List<String> _subjects = [];
  final List<String> _types = ['All', 'Notes', 'Video', 'PYQ'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);  // 3 tabs now
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => _selectedTabIndex = _tabController.index);
      }
    });
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
    super.dispose();
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

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _buildFilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // Header
              _buildHeader(),
            
            // Tab Bar for For You / Following
            _buildTabBar(isDark),
            
            // Search bar (only for For You tab)
            if (_selectedTabIndex == 0) _buildSearchBar(),
            
            // Quick filters (only for For You tab)
            if (_selectedTabIndex == 0) _buildQuickFilters(),
            
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // For You Tab
                  RefreshIndicator(
                    onRefresh: () => _loadResources(refresh: true),
                    color: AppTheme.primary,
                    child: _isLoading
                        ? _buildLoadingSkeleton()
                        : _resources.isEmpty
                            ? _buildEmptyState()
                            : _buildResourcesGrid(),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
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
          Icon(Icons.people_outline_rounded, size: 64, color: AppTheme.textMuted.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            'No resources from people you follow',
            style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            'Follow students to see their uploads here',
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted.withOpacity(0.7)),
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
                          color: (dept['color'] as Color).withOpacity(0.1),
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
              color: AppTheme.primary.withOpacity(0.1),
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
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
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
            onPressed: () {},
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
    
    // Check if any filter is active
    final hasActiveFilters = _selectedType != null || _selectedSubject != null;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7), // iOS system gray
          borderRadius: BorderRadius.circular(28), // More rounded, pill-like
        ),
        child: TextField(
          controller: _searchController,
          style: GoogleFonts.inter(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w400,
            fontSize: 16,
          ),
          onSubmitted: (_) => _loadResources(refresh: true),
          onChanged: (_) => setState(() {}), // Refresh to show/hide clear button
          decoration: InputDecoration(
            hintText: 'Search resources...',
            hintStyle: GoogleFonts.inter(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
              fontWeight: FontWeight.w400,
              fontSize: 16,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Icon(
                Icons.search_rounded,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
                size: 22,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 46),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Clear button (when text exists)
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() {});
                      _loadResources(refresh: true);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[400],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.grey[300] : Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // Filter button (inside the search bar)
                GestureDetector(
                  onTap: _showFilterSheet,
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: hasActiveFilters 
                          ? AppTheme.primary 
                          : (isDark ? Colors.grey[800] : Colors.grey[300]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          color: hasActiveFilters ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[700]),
                          size: 18,
                        ),
                        if (hasActiveFilters) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${(_selectedType != null ? 1 : 0) + (_selectedSubject != null ? 1 : 0)}',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickFilters() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        // Type filters row
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final type in _types)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: _selectedType == type || (_selectedType == null && type == 'All'),
                    onSelected: (selected) {
                      setState(() {
                        _selectedType = selected ? type : null;
                      });
                      _loadResources(refresh: true);
                    },
                    selectedColor: AppTheme.primary.withOpacity(0.2),
                    backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
                    labelStyle: GoogleFonts.inter(
                      color: _selectedType == type || (_selectedType == null && type == 'All')
                          ? AppTheme.primary
                          : isDark ? Colors.white : AppTheme.lightTextPrimary, // Fixed: use dark text for light mode
                      fontWeight: FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: _selectedType == type || (_selectedType == null && type == 'All')
                          ? AppTheme.primary
                          : isDark ? Colors.white24 : AppTheme.lightBorder, // Visible border in dark mode
                    ),
                  ),
                ),
              // Subject filter button
              if (_subjects.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: _showSubjectPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedSubject != null 
                            ? AppTheme.primary.withOpacity(0.2) 
                            : isDark ? AppTheme.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _selectedSubject != null 
                              ? AppTheme.primary 
                              : isDark ? Colors.white24 : AppTheme.lightBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedSubject ?? 'Subject',
                            style: GoogleFonts.inter(
                              color: _selectedSubject != null 
                                  ? AppTheme.primary 
                                  : isDark ? Colors.white : AppTheme.textPrimary, // High contrast
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: _selectedSubject != null ? AppTheme.primary : (isDark ? Colors.white70 : AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
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
    return RefreshIndicator(
      onRefresh: () async => _loadResources(refresh: true),
      color: AppTheme.primary,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _resources.length + (_isLoadingMore ? 2 : 0),
        itemBuilder: (context, index) {
          if (index >= _resources.length) {
            return _buildLoadingCard();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ResourceCard(
              resource: _resources[index],
              userEmail: widget.userEmail,
              onVoteChanged: () => _loadResources(),
            ),
          );
        },
      ),
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
            color: AppTheme.textMuted.withOpacity(0.3),
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
            style: GoogleFonts.inter(color: AppTheme.textMuted.withOpacity(0.7)),
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

  Widget _buildFilterSheet() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Filters',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setModalState(() {
                        _selectedSemester = null;
                        _selectedBranch = null;
                        _selectedSubject = null;
                      });
                      setState(() {});
                    },
                    child: const Text('Clear All'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Semester dropdown
              _buildDropdown(
                label: 'Semester',
                value: _selectedSemester,
                items: _semesters,
                onChanged: (value) {
                  setModalState(() => _selectedSemester = value);
                  setState(() => _selectedSemester = value);
                },
              ),
              const SizedBox(height: 16),
              
              // Branch dropdown
              _buildDropdown(
                label: 'Branch',
                value: _selectedBranch,
                items: _branches,
                onChanged: (value) {
                  setModalState(() => _selectedBranch = value);
                  setState(() => _selectedBranch = value);
                  _loadSubjects();
                },
              ),
              const SizedBox(height: 16),
              
              // Subject dropdown
              if (_subjects.isNotEmpty)
                _buildDropdown(
                  label: 'Subject',
                  value: _selectedSubject,
                  items: _subjects,
                  onChanged: (value) {
                    setModalState(() => _selectedSubject = value);
                    setState(() => _selectedSubject = value);
                  },
                ),
              
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _loadResources(refresh: true);
                  },
                  child: const Text('Apply Filters'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            hint: Text('Select $label', style: GoogleFonts.inter(color: AppTheme.textMuted)),
            underline: const SizedBox(),
            dropdownColor: AppTheme.darkCard,
            items: items.map((item) {
              return DropdownMenuItem(
                value: item,
                child: Text(item, style: GoogleFonts.inter(color: Colors.white)),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
