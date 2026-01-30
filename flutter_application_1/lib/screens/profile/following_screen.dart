import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import 'user_profile_screen.dart';

class FollowingScreen extends StatefulWidget {
  final String userEmail;

  const FollowingScreen({
    super.key,
    required this.userEmail,
  });

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _following = [];
  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _subscriptions = [];
  
  List<Map<String, dynamic>> _filteredFollowing = [];
  List<Map<String, dynamic>> _filteredFollowers = [];
  List<Map<String, dynamic>> _filteredSubscriptions = [];
  
  bool _isLoading = true;
  String _sortBy = 'Recent';
  String _searchQuery = '';

  final List<String> _sortOptions = ['Recent', 'A-Z', 'Z-A'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _applyFilters();
    });
  }

  void _applyFilters() {
    // Filter by search query
    _filteredFollowing = _filterList(_following);
    _filteredFollowers = _filterList(_followers);
    _filteredSubscriptions = _filterList(_subscriptions);
    
    // Sort
    _filteredFollowing = _sortList(_filteredFollowing);
    _filteredFollowers = _sortList(_filteredFollowers);
    _filteredSubscriptions = _sortList(_filteredSubscriptions);
  }

  List<Map<String, dynamic>> _filterList(List<Map<String, dynamic>> list) {
    if (_searchQuery.isEmpty) return List.from(list);
    return list.where((user) {
      final name = (user['display_name'] ?? user['email']?.toString().split('@')[0] ?? '').toLowerCase();
      final email = (user['email'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) || email.contains(_searchQuery);
    }).toList();
  }

  List<Map<String, dynamic>> _sortList(List<Map<String, dynamic>> list) {
    final sorted = List<Map<String, dynamic>>.from(list);
    switch (_sortBy) {
      case 'A-Z':
        sorted.sort((a, b) {
          final nameA = a['display_name'] ?? a['email']?.toString().split('@')[0] ?? '';
          final nameB = b['display_name'] ?? b['email']?.toString().split('@')[0] ?? '';
          return nameA.toString().toLowerCase().compareTo(nameB.toString().toLowerCase());
        });
        break;
      case 'Z-A':
        sorted.sort((a, b) {
          final nameA = a['display_name'] ?? a['email']?.toString().split('@')[0] ?? '';
          final nameB = b['display_name'] ?? b['email']?.toString().split('@')[0] ?? '';
          return nameB.toString().toLowerCase().compareTo(nameA.toString().toLowerCase());
        });
        break;
      case 'Recent':
      default:
        // Keep original order (most recent first)
        break;
    }
    return sorted;
  }

  Future<void> _loadData() async {
    try {
      final following = await _supabaseService.getFollowing(widget.userEmail);
      final followers = await _supabaseService.getFollowers(widget.userEmail);
      // Subscriptions could be premium follows or department follows
      // For now, we'll use following as subscriptions placeholder
      final subscriptions = following.where((f) => f['is_subscribed'] == true).toList();
      
      setState(() {
        _following = following;
        _followers = followers;
        _subscriptions = subscriptions;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showSortOptions(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sort by',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            ..._sortOptions.map((option) => ListTile(
              leading: Icon(
                _sortBy == option ? Icons.check_circle : Icons.circle_outlined,
                color: _sortBy == option ? AppTheme.primary : AppTheme.textMuted,
              ),
              title: Text(
                option,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: _sortBy == option ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              onTap: () {
                setState(() {
                  _sortBy = option;
                  _applyFilters();
                });
                Navigator.pop(context);
              },
            )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
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
          'People',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search people...',
                      hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
              // Tab bar
              TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textMuted,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: [
                  Tab(text: 'Followers ${_followers.isNotEmpty ? "(${_followers.length})" : ""}'),
                  Tab(text: 'Following ${_following.isNotEmpty ? "(${_following.length})" : ""}'),
                  Tab(text: 'Subscriptions ${_subscriptions.isNotEmpty ? "(${_subscriptions.length})" : ""}'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Sort bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isLoading ? 'Loading...' : '${_getCurrentListCount()} people',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                  ),
                ),
                GestureDetector(
                  onTap: () => _showSortOptions(context, isDark),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sort, size: 16, color: isDark ? Colors.white70 : Colors.black54),
                        const SizedBox(width: 6),
                        Text(
                          _sortBy,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down, size: 16, color: isDark ? Colors.white70 : Colors.black54),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUserList(_filteredFollowers, isDark, 'followers'),
                _buildUserList(_filteredFollowing, isDark, 'following'),
                _buildUserList(_filteredSubscriptions, isDark, 'subscriptions'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _getCurrentListCount() {
    switch (_tabController.index) {
      case 0:
        return _filteredFollowers.length;
      case 1:
        return _filteredFollowing.length;
      case 2:
        return _filteredSubscriptions.length;
      default:
        return 0;
    }
  }

  Widget _buildUserList(List<Map<String, dynamic>> users, bool isDark, String type) {
    if (_isLoading) {
      return _buildLoadingSkeleton(isDark);
    }

    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getEmptyIcon(type),
              size: 48,
              color: AppTheme.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty 
                  ? 'No results found'
                  : _getEmptyMessage(type),
              style: GoogleFonts.inter(
                fontSize: 16,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            if (_searchQuery.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Try a different search term',
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: users.length,
        itemBuilder: (context, index) => _buildUserCard(users[index], isDark),
      ),
    );
  }

  IconData _getEmptyIcon(String type) {
    switch (type) {
      case 'followers':
        return Icons.people_outline;
      case 'following':
        return Icons.person_add_outlined;
      case 'subscriptions':
        return Icons.star_outline;
      default:
        return Icons.people_outline;
    }
  }

  String _getEmptyMessage(String type) {
    switch (type) {
      case 'followers':
        return 'No followers yet';
      case 'following':
        return 'Not following anyone yet';
      case 'subscriptions':
        return 'No subscriptions yet';
      default:
        return 'No people found';
    }
  }

  Widget _buildUserCard(Map<String, dynamic> user, bool isDark) {
    final name = user['display_name'] ?? user['email']?.toString().split('@')[0] ?? 'User';
    final email = user['email'] ?? '';
    final hasNewPost = user['has_new_post'] == true;
    
    return GestureDetector(
      onTap: () => _openUserProfile(email, name),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          children: [
            // Avatar with new post indicator
            Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: hasNewPost 
                          ? [AppTheme.primary, AppTheme.accent]
                          : [AppTheme.primary.withOpacity(0.7), AppTheme.secondary],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      name[0].toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (hasNewPost)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasNewPost) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'NEW',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            
            // View button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'View',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openUserProfile(String email, String displayName) {
    if (email.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userEmail: email,
          userName: displayName,
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Shimmer.fromColors(
          baseColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
          highlightColor: isDark ? const Color(0xFF334155) : Colors.grey.shade100,
          child: Container(
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}
