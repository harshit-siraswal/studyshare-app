import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/supabase_service.dart';
import '../../models/resource.dart';
import '../../models/department_account.dart';
import '../../widgets/resource_card.dart';
import '../../widgets/notice_card.dart';
import '../../config/theme.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supabase = SupabaseService();
  late TabController _tabController;
  
  List<Map<String, dynamic>> _allBookmarks = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Department accounts (Twitter-style) - Mirrored from NoticesScreen
  final List<DepartmentAccount> _departmentAccounts = [
    DepartmentAccount(id: 'general', name: 'General Notices', handle: '@general', avatarLetter: 'G', color: const Color(0xFF3B82F6)),
    DepartmentAccount(id: 'cse', name: 'Computer Science', handle: '@cse_dept', avatarLetter: 'CS', color: const Color(0xFF8B5CF6)),
    DepartmentAccount(id: 'ece', name: 'Electronics & Comm', handle: '@ece_dept', avatarLetter: 'EC', color: const Color(0xFF10B981)),
    DepartmentAccount(id: 'eee', name: 'Electrical Engg', handle: '@eee_dept', avatarLetter: 'EE', color: const Color(0xFFF59E0B)),
    DepartmentAccount(id: 'me', name: 'Mechanical Engg', handle: '@mech_dept', avatarLetter: 'ME', color: const Color(0xFFEF4444)),
    DepartmentAccount(id: 'ce', name: 'Civil Engineering', handle: '@civil_dept', avatarLetter: 'CE', color: const Color(0xFF6366F1)),
    DepartmentAccount(id: 'it', name: 'Information Tech', handle: '@it_dept', avatarLetter: 'IT', color: const Color(0xFF14B8A6)),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchBookmarks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchBookmarks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final bookmarks = await _supabase.getBookmarks();
      if (mounted) {
        setState(() {
          _allBookmarks = bookmarks;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching bookmarks: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load bookmarks. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.black : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text('Bookmarks', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Resources'),
            Tab(text: 'Notices'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchBookmarks,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList('all'),
                    _buildList('resource'),
                    _buildList('notice'),
                  ],
                ),
    );
  }

  Widget _buildList(String type) {
    // Create a copy to avoid mutating the original list
    List<Map<String, dynamic>> filtered = List.from(_allBookmarks);
    
    // Filter invalid entries first (where both potential targets are missing)
    filtered.removeWhere((b) =>
        b['resource_id'] == null &&
        b['notice_id'] == null &&
        b['type'] == null &&
        b['content'] == null &&
        b['resource'] == null &&
        b['notice'] == null);

    if (type != 'all') {
      filtered = filtered.where((b) {
        final resolvedType = (b['type'] ??
                (b['resource_id'] != null
                    ? 'resource'
                    : b['notice_id'] != null
                        ? 'notice'
                        : null))
            ?.toString();
        return resolvedType == type;
      }).toList();
    }
    
    // Always sort by created_at descending
    filtered.sort((a, b) {
      final aDate = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
      final bDate = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
      return bDate.compareTo(aDate);
    });

    if (filtered.isEmpty) {
      return const Center(child: Text('No bookmarks found'));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final bookmark = filtered[index];
        
        final resolvedType = (bookmark['type'] ??
                (bookmark['resource_id'] != null
                    ? 'resource'
                    : bookmark['notice_id'] != null
                        ? 'notice'
                        : null))
            ?.toString();
        final content = bookmark['content'] ?? bookmark['resource'] ?? bookmark['notice'];

        if (resolvedType == 'resource' && content != null) {
          final resource = Resource.fromJson(Map<String, dynamic>.from(content));
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ResourceCard(
              resource: resource,
              userEmail: _supabase.currentUserEmail ?? '',
            ),
          );
        } else if (resolvedType == 'notice' && content != null) {
          final noticeMap = Map<String, dynamic>.from(content);
          
          // Resolve DepartmentAccount
          final deptId = noticeMap['department'] as String? ?? 'general';
          final account = _departmentAccounts.firstWhere(
            (a) => a.id == deptId,
            orElse: () => _departmentAccounts.first, 
          );

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: NoticeCard(
              notice: noticeMap,
              account: account,
              isDark: isDark,
            ),
          );
        }
        // Log unexpected data states for debugging
        debugPrint('Bookmark missing expected data: ${bookmark['id']}');
        return const SizedBox.shrink();
      },    );
  }
}
