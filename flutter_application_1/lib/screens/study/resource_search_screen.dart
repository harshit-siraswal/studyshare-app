import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../models/resource.dart';
import '../../services/supabase_service.dart';
import '../../widgets/resource_card.dart';

class ResourceSearchScreen extends StatefulWidget {
  final String collegeId;
  final String userEmail;

  const ResourceSearchScreen({
    super.key,
    required this.collegeId,
    required this.userEmail,
  });

  @override
  State<ResourceSearchScreen> createState() => _ResourceSearchScreenState();
}

class _ResourceSearchScreenState extends State<ResourceSearchScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late TabController _tabController;
  
  List<Resource> _searchResults = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;
  bool _isLoading = false;
  int _subjectFetchId = 0; // Token to track subject fetch requests

  // Filters
  String _selectedType = 'All'; // Controlled by TabController
  String? _selectedSemester;
  String? _selectedBranch;
  String? _selectedSubject;

  final List<String> _types = ['All', 'Video', 'PYQ', 'Downloads'];
  final List<String> _semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];
  List<String> _branches = []; // Fetched from DB
  List<String> _subjects = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _types.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadRecentSearches();
    _fetchBranches();
    
    // Auto-focus search field after transition
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        _selectedType = _types[_tabController.index];
      });
      if (_isSearching) _performSearch();
    }
  }
  Future<void> _fetchBranches() async {
    final branches = await _supabaseService.getUniqueValues('branch', widget.collegeId);
    if (mounted) {
      setState(() => _branches = branches);
    }
  }
  
  Future<void> _loadSubjects() async {
    if (_selectedBranch != null) {
      final subjects = await _supabaseService.getUniqueValues('subject', widget.collegeId);
      if (mounted) setState(() => _subjects = subjects);
    } else {
      if (mounted) setState(() => _subjects = []);
    }
  }
  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recentSearches = prefs.getStringList('resource_recent_searches') ?? [];
    });
  }

  Future<void> _addRecentSearch(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    List<String> updated = [query, ..._recentSearches.where((s) => s != query)]; // Add to top, remove dupes
    if (updated.length > 5) updated = updated.sublist(0, 5); // Keep max 5
    await prefs.setStringList('resource_recent_searches', updated);
    if (mounted) setState(() => _recentSearches = updated);
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('resource_recent_searches');
    if (mounted) setState(() => _recentSearches = []);
  }

  Future<void> _removeRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final updated = _recentSearches.where((s) => s != query).toList();
    await prefs.setStringList('resource_recent_searches', updated);
    if (mounted) setState(() => _recentSearches = updated);
  }

  void _onSearchChanged(String query) {
     setState(() {
       _isSearching = query.isNotEmpty;
     });
  }

  Future<void> _performSearch() async {
    setState(() {
       _isSearching = true;
       _isLoading = true;
    });

    try {
      final results = await _supabaseService.getResources(
        collegeId: widget.collegeId,
        searchQuery: _searchController.text.isEmpty ? null : _searchController.text,
        type: _mapResourceType(_selectedType),
        semester: _selectedSemester,
        branch: _selectedBranch,
        subject: _selectedSubject,
      );
      
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
      
      if (_searchController.text.isNotEmpty) {
        _addRecentSearch(_searchController.text);
      }
    } catch (e, stackTrace) {
      debugPrint('Search error: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _searchResults = [];
      });
    }
  }
  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar & Tabs Header
            Container(
              color: bgColor,
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                         IconButton(
                          icon: Icon(Icons.arrow_back_ios_rounded, size: 20, color: isDark ? Colors.white : Colors.black),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Hero(
                            tag: 'resource_search_bar',
                            child: Material(
                              color: Colors.transparent,
                              child: TextField(
                                controller: _searchController,
                                focusNode: _focusNode,
                                onChanged: _onSearchChanged,
                                onSubmitted: (_) => _performSearch(),
                                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: 'Search resources...',
                                  hintStyle: TextStyle(color: isDark ? Colors.grey : Colors.grey.shade600),
                                  filled: true,
                                  fillColor: cardColor,
                                  prefixIcon: Icon(Icons.search_rounded, color: isDark ? Colors.grey : Colors.grey.shade600),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_searchController.text.isNotEmpty)
                                        IconButton(
                                          icon: Icon(Icons.clear, color: isDark ? Colors.grey : Colors.grey.shade600),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _isSearching = false;
                                              _searchResults = [];
                                            });
                                          },
                                        ),
                                      // Filter Button in Suffix
                                      Semantics(
                                        label: 'Open filters',
                                        button: true,
                                        child: GestureDetector(
                                          onTap: _showFilterSheet,
                                          child: Padding(
                                            padding: const EdgeInsets.only(right: 12.0),
                                            child: Icon(
                                              Icons.tune_rounded,
                                              color: (_selectedSemester != null || _selectedBranch != null || _selectedSubject != null) 
                                                  ? AppTheme.primary 
                                                  : (isDark ? Colors.grey : Colors.grey.shade600),
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                   ),
                                   border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),                  
                  const SizedBox(height: 12),
                  
                  // Tabs
                  TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    labelColor: isDark ? Colors.white : Colors.black,
                    unselectedLabelColor: isDark ? Colors.grey : Colors.grey.shade600,
                    indicatorColor: AppTheme.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorWeight: 3,
                    labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                    tabs: _types.map((t) => Tab(text: t)).toList(),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: _isSearching 
                  ? _buildSearchResults(isDark)
                  : _buildInitialContent(isDark),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildFilterSheetContent(),
    );
  }

  Widget _buildFilterSheetContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    // ... Reuse similar sheet logic but strictly for Sem/Branch/Subject lists ...
    return StatefulBuilder(
      builder: (context, setSheetState) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filters', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    TextButton(
                      onPressed: () {
                        setSheetState(() {
                          _selectedSemester = null;
                          _selectedBranch = null;
                          _selectedSubject = null;
                        });
                        setState(() {
                           _selectedSemester = null;
                           _selectedBranch = null;
                           _selectedSubject = null;
                           _subjects = [];
                        }); 
                        Navigator.pop(context);
                        _performSearch();
                      },
                      child: const Text('Reset', style: TextStyle(color: Colors.red)),
                    )
                  ],
                ),
                
              const SizedBox(height: 20),
              // Semesters
              DropdownButtonFormField<String>(
                value: _selectedSemester,
                dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                decoration: InputDecoration(
                  labelText: 'Semester',
                  filled: true,
                  fillColor: isDark ? Colors.black12 : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                items: _semesters.map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: isDark ? Colors.white : Colors.black)))).toList(),
                onChanged: (val) {
                  setSheetState(() => _selectedSemester = val);
                  setState(() => _selectedSemester = val); 
                },
              ),
              const SizedBox(height: 16),
              // Branch
              DropdownButtonFormField<String>(
                value: _selectedBranch,
                dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                decoration: InputDecoration(
                  labelText: 'Branch',
                  filled: true,
                  fillColor: isDark ? Colors.black12 : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b, style: TextStyle(color: isDark ? Colors.white : Colors.black)))).toList(),
                onChanged: (val) async {
                   setSheetState(() {
                     _selectedBranch = val;
                     _selectedSubject = null; 
                   });
                   setState(() { 
                     _selectedBranch = val;
                     _selectedSubject = null;
                     _subjectFetchId++; // Increment token
                   });
                   
                   final currentFetchId = _subjectFetchId;

                   // Fetch subjects and update sheet
                   if (val != null) {
                     final subjects = await _supabaseService.getUniqueValues('subject', widget.collegeId, branch: val);
                     if (mounted && _subjectFetchId == currentFetchId) {
                        setState(() => _subjects = subjects);
                        setSheetState(() {}); // Trigger rebuild of sheet to show subjects
                     }
                   }
                },
              ),
              const SizedBox(height: 16),
              // Subject
              if (_selectedBranch != null && _subjects.isNotEmpty)
                 DropdownButtonFormField<String>(
                  value: _selectedSubject,
                  dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    filled: true,
                    fillColor: isDark ? Colors.black12 : Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: _subjects.map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: isDark ? Colors.white : Colors.black)))).toList(),
                  onChanged: (val) {
                    setSheetState(() => _selectedSubject = val);
                    setState(() => _selectedSubject = val);
                  },
                ),

              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _performSearch();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('Apply Filters', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      }
    );
  }

  Widget _buildInitialContent(bool isDark) {
    if (_recentSearches.isEmpty) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text('Recent Searches', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black54)),
             TextButton(onPressed: _clearRecentSearches, child: Text('Clear All', style: TextStyle(color: AppTheme.primary, fontSize: 12))),
           ],
        ),
        ..._recentSearches.map((term) => ListTile(
           leading: Icon(Icons.history_rounded, color: isDark ? Colors.grey : Colors.grey.shade400),
           title: Text(term, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
           trailing: IconButton(
             icon: Icon(Icons.close, size: 16, color: isDark ? Colors.grey : Colors.grey.shade400),
             onPressed: () => _removeRecentSearch(term),
           ),
           onTap: () {
             _searchController.text = term;
             _performSearch();
           },
        )),
      ],
    );
  }
  
  Widget _buildSearchResults(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
       return Center(
         child: Column(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
             Icon(Icons.search_off_rounded, size: 64, color: isDark ? Colors.white12 : Colors.grey.shade300),
             const SizedBox(height: 16),
             Text('No resources found', style: TextStyle(color: isDark ? Colors.grey : Colors.grey.shade600)),
           ],
         ),
       );
    }

    return AnimationLimiter(
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 375),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: ResourceCard(
                    resource: _searchResults[index],
                    userEmail: widget.userEmail,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String? _mapResourceType(String uiType) {
    if (uiType == 'All') return null;
    if (uiType == 'Downloads') return 'notes';
    return uiType.toLowerCase();
  }
}
