import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../models/resource.dart';
import '../../services/supabase_service.dart';
import '../../services/download_service.dart';
import '../../services/resource_state_repository.dart';
import '../../services/subscription_service.dart';
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

class _ResourceSearchScreenState extends State<ResourceSearchScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final ResourceStateRepository _resourceStateRepository =
      ResourceStateRepository();
  final DownloadService _downloadService = DownloadService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<Resource> _searchResults = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;
  bool _isLoading = false;
  int _subjectFetchId = 0;

  String _selectedType = 'All';
  String _selectedSort = 'Recent';
  String? _selectedSemester;
  String? _selectedBranch;
  String? _selectedSubject;

  final List<String> _types = ['All', 'Notes', 'PYQ', 'Videos', 'Downloads'];
  final List<String> _sortOptions = ['Recent', 'Most upvotes', 'Teacher'];
  final List<String> _semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];
  List<String> _branches = [];
  List<String> _subjects = [];

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _fetchBranches();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchBranches() async {
    final branches = await _supabaseService.getUniqueValues(
      'branch',
      widget.collegeId,
    );
    if (mounted) {
      setState(() => _branches = branches);
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

    var updated = [query, ..._recentSearches.where((s) => s != query)];
    if (updated.length > 5) {
      updated = updated.sublist(0, 5);
    }

    await prefs.setStringList('resource_recent_searches', updated);
    if (mounted) {
      setState(() => _recentSearches = updated);
    }
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('resource_recent_searches');
    if (mounted) {
      setState(() => _recentSearches = []);
    }
  }

  Future<void> _removeRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final updated = _recentSearches.where((s) => s != query).toList();
    await prefs.setStringList('resource_recent_searches', updated);
    if (mounted) {
      setState(() => _recentSearches = updated);
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _isSearching = query.trim().isNotEmpty;
    });
  }

  Future<void> _performSearch() async {
    setState(() {
      _isSearching = true;
      _isLoading = true;
    });

    try {
      // Handle Downloads separately: fetch from local storage, not API
      if (_selectedType == 'Downloads') {
        final hasPremiumAccess = await _subscriptionService.isPremium();
        final downloadedResults = await _downloadService
            .getAllDownloadedResourcesForUser(
              widget.userEmail,
              hasPremiumAccess: hasPremiumAccess,
            );
        final query = _searchController.text.trim().toLowerCase();
        final selectedSemester = _selectedSemester?.toLowerCase();
        final selectedBranch = _selectedBranch?.toLowerCase();
        final selectedSubject = _selectedSubject?.toLowerCase();
        var localResults = downloadedResults.where((resource) {
          if (query.isNotEmpty) {
            final matchesQuery =
                resource.title.toLowerCase().contains(query) ||
                (resource.description?.toLowerCase().contains(query) ?? false);
            if (!matchesQuery) return false;
          }
          if (selectedSemester != null &&
              (resource.semester ?? '').toLowerCase() != selectedSemester) {
            return false;
          }
          if (selectedBranch != null &&
              (resource.branch ?? '').toLowerCase() != selectedBranch) {
            return false;
          }
          if (selectedSubject != null &&
              (resource.subject ?? '').toLowerCase() != selectedSubject) {
            return false;
          }
          return true;
        }).toList();

        if (query.isNotEmpty) {
          _addRecentSearch(_searchController.text);
        }

        final localSort = _mapSortOption(_selectedSort);
        if (localSort == 'upvotes') {
          localResults.sort((a, b) => b.upvotes.compareTo(a.upvotes));
        } else if (localSort == 'teacher') {
          localResults.sort((a, b) {
            if (a.isTeacherUpload != b.isTeacherUpload) {
              return a.isTeacherUpload ? -1 : 1;
            }
            final createdAtComparison = b.createdAt.compareTo(a.createdAt);
            if (createdAtComparison != 0) return createdAtComparison;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
        } else {
          localResults.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }

        if (!mounted) return;
        setState(() {
          _searchResults = localResults;
          _isLoading = false;
        });
        return;
      }

      // For all other types, query the API
      final results = await _supabaseService.getResources(
        collegeId: widget.collegeId,
        searchQuery: _searchController.text.isEmpty
            ? null
            : _searchController.text,
        type: _mapResourceType(_selectedType),
        sortBy: _mapSortOption(_selectedSort),
        semester: _selectedSemester,
        branch: _selectedBranch,
        subject: _selectedSubject,
      );

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });

      if (widget.userEmail.trim().isNotEmpty && results.isNotEmpty) {
        unawaited(() async {
          try {
            await _resourceStateRepository.prefetchResourceStateForResources(
              userEmail: widget.userEmail,
              resources: results,
            );
          } catch (e, stackTrace) {
            debugPrint('Search prefetch failed: $e\n$stackTrace');
          }
        }());
      }

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

  bool get _hasActiveFilters {
    return _selectedType != 'All' ||
        _selectedSort != 'Recent' ||
        _selectedSemester != null ||
        _selectedBranch != null ||
        _selectedSubject != null;
  }

  int get _activeFilterCount {
    return [
      _selectedType != 'All',
      _selectedSort != 'Recent',
      _selectedSemester != null,
      _selectedBranch != null,
      _selectedSubject != null,
    ].where((v) => v).length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    final dividerColor = isDark ? Colors.white10 : Colors.black12;
    final searchSurfaceColor = isDark ? Colors.black : const Color(0xFFF4F6FB);
    final searchBorderColor = _hasActiveFilters
        ? AppTheme.primary.withValues(alpha: 0.55)
        : (isDark ? Colors.white24 : const Color(0xFFE1E7F0));
    final filterBackground = _hasActiveFilters
        ? AppTheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)
        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06));
    final filterTextColor = _hasActiveFilters
        ? AppTheme.primary
        : (isDark ? Colors.white70 : const Color(0xFF111827));

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: bgColor,
              padding: const EdgeInsets.only(top: 16, bottom: 10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                        tag: 'resource_search_bar',
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: searchSurfaceColor,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: searchBorderColor,
                                width: _hasActiveFilters ? 1.2 : 0.9,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isDark ? 0.22 : 0.07,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : const Color(0xFFDCE3EE),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF19212E),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _focusNode,
                                    onChanged: _onSearchChanged,
                                    onSubmitted: (_) => _performSearch(),
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF111827),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Search resources...',
                                      hintStyle: TextStyle(
                                        color: isDark
                                            ? Colors.grey[400]
                                            : const Color(0xFF6B7280),
                                      ),
                                      isDense: true,
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                if (_searchController.text.isNotEmpty)
                                  IconButton(
                                    iconSize: 18,
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.clear_rounded,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : const Color(0xFF6B7280),
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _isSearching = false;
                                        _searchResults = [];
                                      });
                                    },
                                  ),
                                Container(
                                  width: 1,
                                  height: 28,
                                  color: dividerColor,
                                ),
                                const SizedBox(width: 8),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _showFilterSheet,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: filterBackground,
                                            borderRadius: BorderRadius.circular(
                                              11,
                                            ),
                                            border: Border.all(
                                              color: _hasActiveFilters
                                                  ? AppTheme.primary.withValues(
                                                      alpha: 0.4,
                                                    )
                                                  : dividerColor,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.tune_rounded,
                                            size: 18,
                                            color: filterTextColor,
                                          ),
                                        ),
                                        if (_activeFilterCount > 0)
                                          Positioned(
                                            right: -4,
                                            top: -5,
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF0EA5E9),
                                                shape: BoxShape.circle,
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                _activeFilterCount.toString(),
                                                style: GoogleFonts.inter(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) =>
            _buildFilterSheetContent(setModalState),
      ),
    );
  }

  Widget _buildFilterSheetContent(StateSetter setModalState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F1116) : Colors.white;
    final dividerColor = isDark ? Colors.white10 : const Color(0xFFE5E7EB);
    void syncSheet() => setModalState(() {});

    return Container(
      height: MediaQuery.of(context).size.height * 0.74,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
            child: Row(
              children: [
                const SizedBox(width: 52),
                Expanded(
                  child: Text(
                    'Sort & filter',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedType = 'All';
                      _selectedSort = 'Recent';
                      _selectedSemester = null;
                      _selectedBranch = null;
                      _selectedSubject = null;
                      _subjects = [];
                    });
                    syncSheet();
                  },
                  child: Text(
                    'Clear',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white : const Color(0xFF111827),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dividerColor),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                children: [
                  _buildSheetSelectionRow(
                    label: 'Sort by',
                    value: _selectedSort,
                    isValueActive: _selectedSort != 'Recent',
                    isDark: isDark,
                    onTap: () {
                      _showPickerSheet(
                        title: 'Sort by',
                        items: _sortOptions,
                        selectedValue: _selectedSort,
                        isDark: isDark,
                        onSelected: (value) {
                          setState(() => _selectedSort = value);
                          syncSheet();
                        },
                      );
                    },
                  ),
                  Divider(height: 1, color: dividerColor),
                  _buildSheetSelectionRow(
                    label: 'Type',
                    value: _selectedType,
                    isValueActive: _selectedType != 'All',
                    isDark: isDark,
                    onTap: () {
                      _showPickerSheet(
                        title: 'Type',
                        items: _types,
                        selectedValue: _selectedType,
                        isDark: isDark,
                        onSelected: (value) {
                          setState(() => _selectedType = value);
                          syncSheet();
                        },
                      );
                    },
                  ),
                  Divider(height: 1, color: dividerColor),
                  _buildSheetSelectionRow(
                    label: 'Semester',
                    value: _selectedSemester ?? 'All',
                    isValueActive: _selectedSemester != null,
                    isDark: isDark,
                    onTap: () {
                      _showPickerSheet(
                        title: 'Semester',
                        items: ['All', ..._semesters],
                        selectedValue: _selectedSemester ?? 'All',
                        isDark: isDark,
                        onSelected: (value) {
                          setState(() {
                            _selectedSemester = value == 'All' ? null : value;
                          });
                          syncSheet();
                        },
                      );
                    },
                  ),
                  Divider(height: 1, color: dividerColor),
                  _buildSheetSelectionRow(
                    label: 'Branch',
                    value: _selectedBranch ?? 'All',
                    isValueActive: _selectedBranch != null,
                    isDark: isDark,
                    onTap: () {
                      _showPickerSheet(
                        title: 'Branch',
                        items: _branches.isEmpty
                            ? ['All']
                            : ['All', ..._branches],
                        selectedValue: _selectedBranch ?? 'All',
                        isDark: isDark,
                        onSelected: (value) async {
                          setState(() {
                            _selectedBranch = value == 'All' ? null : value;
                            _selectedSubject = null;
                            _subjectFetchId++;
                          });
                          syncSheet();

                          final currentFetchId = _subjectFetchId;
                          if (_selectedBranch == null) {
                            setState(() => _subjects = []);
                            syncSheet();
                            return;
                          }

                          final subjects = await _supabaseService
                              .getUniqueValues(
                                'subject',
                                widget.collegeId,
                                branch: _selectedBranch,
                              );

                          if (!mounted || currentFetchId != _subjectFetchId) {
                            return;
                          }
                          setState(() => _subjects = subjects);
                          syncSheet();
                        },
                      );
                    },
                  ),
                  Divider(height: 1, color: dividerColor),
                  _buildSheetSelectionRow(
                    label: 'Subject',
                    value:
                        _selectedSubject ??
                        (_selectedBranch == null
                            ? 'Select branch first'
                            : 'All'),
                    isValueActive: _selectedSubject != null,
                    isDark: isDark,
                    enabled: _selectedBranch != null,
                    onTap: _selectedBranch == null
                        ? null
                        : () {
                            _showPickerSheet(
                              title: 'Subject',
                              items: _subjects.isEmpty
                                  ? ['All']
                                  : ['All', ..._subjects],
                              selectedValue: _selectedSubject ?? 'All',
                              isDark: isDark,
                              onSelected: (value) {
                                setState(() {
                                  _selectedSubject = value == 'All'
                                      ? null
                                      : value;
                                });
                                syncSheet();
                              },
                            );
                          },
                  ),
                  Divider(height: 1, color: dividerColor),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: ElevatedButton(
              onPressed: () {
                _performSearch();
                Navigator.pop(context);
              },
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
                'Show results',
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
  }

  Widget _buildSheetSelectionRow({
    required String label,
    required String value,
    required bool isValueActive,
    required bool isDark,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final mutedColor = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final valueColor = enabled
        ? (isValueActive ? AppTheme.primary : mutedColor)
        : mutedColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
          child: Row(
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: enabled ? textColor : mutedColor,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: valueColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: enabled ? mutedColor : mutedColor.withValues(alpha: 0.6),
              ),
            ],
          ),
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
          maxHeight: MediaQuery.of(context).size.height * 0.55,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
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
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? AppTheme.primary
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppTheme.primary,
                            size: 20,
                          )
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

  Widget _buildInitialContent(bool isDark) {
    if (_recentSearches.isEmpty) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
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
              child: const Text(
                'Clear All',
                style: TextStyle(color: AppTheme.primary, fontSize: 12),
              ),
            ),
          ],
        ),
        ..._recentSearches.map(
          (term) => ListTile(
            leading: Icon(
              Icons.history_rounded,
              color: isDark ? Colors.grey : Colors.grey.shade400,
            ),
            title: Text(
              term,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
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
              _performSearch();
            },
          ),
        ),
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
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: isDark ? Colors.white12 : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No resources found',
              style: TextStyle(
                color: isDark ? Colors.grey : Colors.grey.shade600,
              ),
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
                  child: ResourceCard(
                    resource: _searchResults[index],
                    userEmail: widget.userEmail,
                    deferRemoteStateHydration: true,
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
    if (uiType == 'Videos') return 'video';
    if (uiType == 'Downloads') {
      throw StateError(
        'uiType "Downloads" is local-only and must not be mapped to an API type',
      );
    }
    return uiType.toLowerCase();
  }

  String? _mapSortOption(String sortLabel) {
    switch (sortLabel) {
      case 'Most upvotes':
        return 'upvotes';
      case 'Teacher':
        return 'teacher';
      default:
        return null;
    }
  }
}
