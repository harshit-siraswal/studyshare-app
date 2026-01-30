import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import 'department_account_screen.dart' as dept_screen;
import '../../widgets/notice_card.dart';
import '../../models/department_account.dart';

class NoticesScreen extends StatefulWidget {
  final String collegeId;

  const NoticesScreen({super.key, required this.collegeId});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _notices = [];
  List<Map<String, dynamic>> _filteredNotices = [];
  bool _isLoading = true;
  String? _selectedDepartment;
  
  // Track if search field is focused
  final FocusNode _searchFocusNode = FocusNode();
  
  late TabController _tabController;
  
  // Department accounts (Twitter-style)
  final List<DepartmentAccount> _departmentAccounts = [
    DepartmentAccount(id: 'general', name: 'General Notices', handle: '@general', avatarLetter: 'G', color: const Color(0xFF3B82F6)),
    DepartmentAccount(id: 'cse', name: 'Computer Science', handle: '@cse_dept', avatarLetter: 'CS', color: const Color(0xFF8B5CF6)),
    DepartmentAccount(id: 'ece', name: 'Electronics & Comm', handle: '@ece_dept', avatarLetter: 'EC', color: const Color(0xFF10B981)),
    DepartmentAccount(id: 'eee', name: 'Electrical Engg', handle: '@eee_dept', avatarLetter: 'EE', color: const Color(0xFFF59E0B)),
    DepartmentAccount(id: 'me', name: 'Mechanical Engg', handle: '@mech_dept', avatarLetter: 'ME', color: const Color(0xFFEF4444)),
    DepartmentAccount(id: 'ce', name: 'Civil Engineering', handle: '@civil_dept', avatarLetter: 'CE', color: const Color(0xFF6366F1)),
    DepartmentAccount(id: 'it', name: 'Information Tech', handle: '@it_dept', avatarLetter: 'IT', color: const Color(0xFF14B8A6)),
  ];

  DateTime? _startDate;
  DateTime? _endDate;

  Future<void> _showDateFilter() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.primary,
              brightness: isDark ? Brightness.dark : Brightness.light,
              surface: isDark ? AppTheme.darkSurface : Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _isLoading = true;
      });
      _loadNotices();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadNotices();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadNotices() async {
    try {
      debugPrint('NoticesScreen: Loading notices for collegeId: ${widget.collegeId}');
      final notices = await _supabaseService.getNotices(
        collegeId: widget.collegeId,
        startDate: _startDate,
        endDate: _endDate,
      );
      debugPrint('NoticesScreen: Loaded ${notices.length} notices');
      if (notices.isEmpty) {
        debugPrint('NoticesScreen: No notices found - check if collegeId is correct');
      }
      setState(() {
        _notices = notices;
        _filteredNotices = notices;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('NoticesScreen ERROR: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() => _isLoading = false);
    }
  }

  void _filterByDepartment(String? deptId) {
    setState(() {
      _selectedDepartment = deptId;
      _applyFilters();
    });
  }

  void _searchNotices(String query) {
    setState(() {
      _applyFilters(searchQuery: query);
    });
  }

  void _applyFilters({String? searchQuery}) {
    String query = searchQuery ?? _searchController.text;
    String? deptId = _selectedDepartment;
    
    _filteredNotices = _notices.where((notice) {
      // Department filter
      if (deptId != null) {
        final noticeDept = notice['department']?.toString().toLowerCase() ?? '';
        if (noticeDept != deptId.toLowerCase()) {
          return false;
        }
      }
      
      // Search filter - search across content text
      if (query.isNotEmpty) {
        final searchLower = query.toLowerCase();
        final title = notice['title']?.toString().toLowerCase() ?? '';
        final content = notice['content']?.toString().toLowerCase() ?? '';
        final description = notice['description']?.toString().toLowerCase() ?? '';
        
        if (!title.contains(searchLower) && 
            !content.contains(searchLower) && 
            !description.contains(searchLower)) {
          return false;
        }
      }
      
      return true;
    }).toList();
  }



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              // Header - Clean title only
              _buildHeader(isDark),
              
              // Always-visible iOS-style search bar with integrated filter
              _buildSearchBar(isDark),
              
              // Tab bar (For You / Departments)
              _buildTabBar(isDark),
              
              // Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // For You - All notices feed
                    _buildNoticesFeed(isDark),
                    
                    // Departments - List of department accounts
                    _buildDepartmentsTab(isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Text(
            'Notices',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7), // iOS system gray
          borderRadius: BorderRadius.circular(28), // Pill shape
        ),
        child: Row(
          children: [
            // Search field
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _searchNotices,
                style: GoogleFonts.inter(
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Search notices...',
                  hintStyle: GoogleFonts.inter(
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                    fontWeight: FontWeight.w400,
                    fontSize: 15,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: isDark ? Colors.white54 : Colors.grey.shade500,
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            _applyFilters();
                            setState(() {});
                          },
                          icon: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.grey.shade400,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: isDark ? Colors.white : Colors.white,
                              size: 14,
                            ),
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            
            // Integrated date filter button
            Container(
              margin: const EdgeInsets.only(right: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _showDateFilter,
                  onLongPress: _startDate != null ? () {
                    setState(() {
                      _startDate = null;
                      _endDate = null;
                      _isLoading = true;
                    });
                    _loadNotices();
                  } : null,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _startDate != null 
                          ? AppTheme.primary.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _startDate != null 
                          ? Icons.calendar_month_rounded
                          : Icons.calendar_today_rounded,
                      color: _startDate != null 
                          ? AppTheme.primary 
                          : (isDark ? Colors.white54 : Colors.grey.shade500),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        unselectedLabelColor: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
        indicatorColor: AppTheme.primary,
        indicatorWeight: 3,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 15),
        tabs: const [
          Tab(text: 'For You'),
          Tab(text: 'Departments'),
        ],
      ),
    );
  }

  Widget _buildNoticesFeed(bool isDark) {
    if (_isLoading) {
      return _buildLoadingSkeleton(isDark);
    }
    
    if (_filteredNotices.isEmpty) {
      return _buildEmptyState(isDark);
    }
    
    return RefreshIndicator(
      onRefresh: _loadNotices,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 0),
        itemCount: _filteredNotices.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
        itemBuilder: (context, index) {
          final notice = _filteredNotices[index];
          final deptId = notice['department']?.toString().toLowerCase() ?? 'general';
          final account = _departmentAccounts.firstWhere(
            (a) => a.id == deptId,
            orElse: () => _departmentAccounts[0],
          );
          
          return NoticeCard(
            notice: notice,
            account: account,
            isDark: isDark,
          );
        },
      ),
    );
  }



  Widget _buildDepartmentsTab(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _departmentAccounts.length,
      itemBuilder: (context, index) {
        final account = _departmentAccounts[index];
        final noticeCount = _notices.where((n) => 
          n['department']?.toString().toLowerCase() == account.id
        ).length;
        
        return _buildDepartmentAccountTile(account, noticeCount, isDark, index);
      },
    );
  }

  Widget _buildDepartmentAccountTile(DepartmentAccount account, int noticeCount, bool isDark, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 50)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(20 * (1 - value), 0),
            child: child,
          ),
        );
      },
      child: InkWell(
        onTap: () {
          // Navigate to department account page
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => dept_screen.DepartmentAccountScreen(
                account: DepartmentAccount(
                  id: account.id,
                  name: account.name,
                  handle: account.handle,
                  avatarLetter: account.avatarLetter,
                  color: account.color,
                ),
                collegeId: widget.collegeId,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: account.color,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Center(
                  child: Text(
                    account.avatarLetter,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: account.avatarLetter.length > 1 ? 16 : 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.name,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: AppTheme.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          account.handle,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.people_outline_rounded, size: 14, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                        const SizedBox(width: 2),
                        Text(
                          '${noticeCount * 12} followers', // Placeholder: Can wire to getDepartmentFollowerCount
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Follow button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: account.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Follow',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(bool isDark) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Shimmer.fromColors(
            baseColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[300]!,
            highlightColor: isDark ? const Color(0xFF3D3D3D) : Colors.grey[100]!,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 120,
                        height: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 64,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'No notices yet',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later for updates',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}


