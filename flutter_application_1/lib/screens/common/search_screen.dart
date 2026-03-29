import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../widgets/room_card.dart';

class SearchScreen extends StatefulWidget {
  final List<Map<String, dynamic>> allRooms;
  final String userEmail;
  final String collegeId;
  final String collegeDomain;

  const SearchScreen({
    super.key,
    required this.allRooms,
    required this.userEmail,
    required this.collegeId,
    required this.collegeDomain,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> _searchResults = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;

  // Mock tags for discovery - In real app, could be derived from actual room tags
  final List<String> _suggestedTags = [
    'Placement',
    'Hackathon',
    'DSA',
    'Web Dev',
    'App Dev',
    'Machine Learning',
    'Events',
    'General',
    'Gaming',
    'Music',
    'Sports',
  ];

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();

    // Auto-focus search field after transition
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches = prefs.getStringList('recent_searches') ?? [];
    });
  }

  Future<void> _addRecentSearch(String query) async {
    if (query.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    List<String> updated = [
      query,
      ..._recentSearches.where((s) => s != query),
    ]; // Add to top, remove dupes
    if (updated.length > 5) updated = updated.sublist(0, 5); // Keep max 5

    await prefs.setStringList('recent_searches', updated);
    setState(() => _recentSearches = updated);
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_searches');
    setState(() => _recentSearches = []);
  }

  Future<void> _removeRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = _recentSearches.where((s) => s != query).toList();
    await prefs.setStringList('recent_searches', updated);
    setState(() => _recentSearches = updated);
  }

  void _onSearchChanged(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      if (_isSearching) {
        _searchResults = widget.allRooms.where((room) {
          final name = room['name']?.toString().toLowerCase() ?? '';
          final desc = room['description']?.toString().toLowerCase() ?? '';
          final tags = _extractTags(room['tags']).join(' ');

          final q = query.toLowerCase();
          return name.contains(q) || desc.contains(q) || tags.contains(q);
        }).toList();
      } else {
        _searchResults = [];
      }
    });
  }

  void _onSearchSubmit(String query) {
    if (query.trim().isNotEmpty) {
      _addRecentSearch(query.trim());
    }
  }

  List<String> _extractTags(dynamic rawTags) {
    if (rawTags is List) {
      return rawTags
          .map((entry) => entry?.toString().trim().toLowerCase() ?? '')
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }

    final normalized = rawTags?.toString().trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return const <String>[];

    if (normalized.contains(',')) {
      return normalized
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }

    return <String>[normalized];
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
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
            // Search Bar Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 20,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Hero(
                      tag: 'search_bar',
                      child: Material(
                        color: Colors.transparent,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _focusNode,
                          onChanged: _onSearchChanged,
                          onSubmitted: _onSearchSubmit,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search rooms, tags...',
                            hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey
                                  : Colors.grey.shade600,
                            ),
                            filled: true,
                            fillColor: cardColor,
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: isDark
                                  ? Colors.grey
                                  : Colors.grey.shade600,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: isDark
                                          ? Colors.grey
                                          : Colors.grey.shade600,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      _onSearchChanged('');
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
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

  Widget _buildInitialContent(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Chips / Tags Scroller
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _suggestedTags.length,
              separatorBuilder: (ctx, i) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final tag = _suggestedTags[i];
                return GestureDetector(
                  onTap: () {
                    _searchController.text = tag;
                    _onSearchChanged(tag);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Recent Searches
          if (_recentSearches.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Searches',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                TextButton(
                  onPressed: _clearRecentSearches,
                  child: Text(
                    'Clear All',
                    style: TextStyle(color: AppTheme.primary, fontSize: 12),
                  ),
                ),
              ],
            ),
            ..._recentSearches.map(
              (term) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.history_rounded,
                  color: isDark ? Colors.grey : Colors.grey.shade400,
                ),
                title: Text(
                  term,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: isDark ? Colors.grey : Colors.grey.shade400,
                  ),
                  onPressed: () => _removeRecentSearch(term),
                ),
                onTap: () {
                  _searchController.text = term;
                  _onSearchChanged(term);
                },
              ),
            ),
          ],

          if (_recentSearches.isEmpty) ...[
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.manage_search_rounded,
                    size: 64,
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Find study groups, events, and more',
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchResults(bool isDark) {
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: isDark ? Colors.white12 : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No rooms found for "${_searchController.text}"',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
            ),
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
                  child: RoomCard(
                    room: _searchResults[index],
                    userEmail: widget.userEmail,
                    collegeDomain: widget.collegeDomain,
                    onReturn: () {
                      // Optional: handle something on return
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
