import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/resource.dart';
import '../../services/supabase_service.dart';
import '../../widgets/resource_card.dart';

class FollowingSearchScreen extends StatefulWidget {
  final String collegeId;
  final String userEmail;
  final String searchHint;
  final bool canManageAdminResources;
  final List<Resource> resources;
  final Future<void> Function(String resourceId, String newStatus)? onModerate;
  final Future<void> Function(Resource resource)? onDelete;

  const FollowingSearchScreen({
    super.key,
    required this.collegeId,
    required this.userEmail,
    required this.searchHint,
    required this.canManageAdminResources,
    required this.resources,
    this.onModerate,
    this.onDelete,
  });

  @override
  State<FollowingSearchScreen> createState() => _FollowingSearchScreenState();
}

class _FollowingSearchScreenState extends State<FollowingSearchScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late List<Resource> _allResources;
  List<Resource> _results = [];
  bool _isLoading = false;

  String _selectedType = 'All';
  String _selectedSort = 'Recent';
  String? _selectedSemester;
  String? _selectedBranch;
  String? _selectedSubject;

  final List<String> _types = ['All', 'Notes', 'PYQ', 'Videos'];
  final List<String> _sortOptions = ['Recent', 'Most upvotes', 'Teacher'];
  final List<String> _semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];
  List<String> _branches = [];
  List<String> _subjects = [];
  int _subjectFetchId = 0;

  bool get _hasFilters =>
      _selectedType != 'All' ||
      _selectedSort != 'Recent' ||
      _selectedSemester != null ||
      _selectedBranch != null ||
      _selectedSubject != null;

  int get _activeFilterCount => [
        _selectedType != 'All',
        _selectedSort != 'Recent',
        _selectedSemester != null,
        _selectedBranch != null,
        _selectedSubject != null,
      ].where((value) => value).length;

  @override
  void initState() {
    super.initState();
    _allResources = List<Resource>.from(widget.resources);
    _fetchBranches();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant FollowingSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resources != widget.resources) {
      _allResources = List<Resource>.from(widget.resources);
      if (_searchController.text.trim().isNotEmpty || _hasFilters) {
        _performSearch();
      }
    }
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
    if (!mounted) return;
    setState(() => _branches = branches);
  }

  Future<void> _performSearch() async {
    setState(() => _isLoading = true);
    final query = _searchController.text.trim().toLowerCase();
    final type = _selectedType == 'All' ? null : _selectedType.toLowerCase();
    final semester = _selectedSemester?.toLowerCase();
    final branch = _selectedBranch?.toLowerCase();
    final subject = _selectedSubject?.toLowerCase();

    final results = _allResources.where((resource) {
      if (query.isNotEmpty) {
        final haystacks = <String>[
          resource.title,
          resource.description ?? '',
          resource.subject ?? '',
          resource.branch ?? '',
          resource.semester ?? '',
          resource.uploadedByName ?? '',
        ];
        if (!haystacks.any((value) => value.toLowerCase().contains(query))) {
          return false;
        }
      }
      if (type != null && resource.type.trim().toLowerCase() != type) return false;
      if (semester != null &&
          (resource.semester ?? '').trim().toLowerCase() != semester) {
        return false;
      }
      if (branch != null &&
          (resource.branch ?? '').trim().toLowerCase() != branch) {
        return false;
      }
      if (subject != null &&
          (resource.subject ?? '').trim().toLowerCase() != subject) {
        return false;
      }
      return true;
    }).toList();

    if (_selectedSort == 'Most upvotes') {
      results.sort((a, b) => b.upvotes.compareTo(a.upvotes));
    } else if (_selectedSort == 'Teacher') {
      results.sort((a, b) {
        if (a.isTeacherUpload == b.isTeacherUpload) return 0;
        return a.isTeacherUpload ? -1 : 1;
      });
    } else {
      results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    if (!mounted) return;
    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  Future<void> _applyModeration(Resource resource, String newStatus) async {
    final callback = widget.onModerate;
    if (callback == null) return;
    await callback(resource.id, newStatus);
    if (!mounted) return;
    final updated = Resource.fromJson({
      ...resource.toJson(),
      'status': newStatus,
      'is_approved': Resource.isApprovedStatusValue(newStatus),
    });
    setState(() {
      final index = _allResources.indexWhere((item) => item.id == resource.id);
      if (index != -1) {
        _allResources[index] = updated;
      }
    });
    await _performSearch();
  }

  Future<void> _removeResource(Resource resource) async {
    final callback = widget.onDelete;
    if (callback == null) return;
    await callback(resource);
    if (!mounted) return;
    setState(() {
      _allResources.removeWhere((item) => item.id == resource.id);
    });
    await _performSearch();
  }

  void _showPicker({
    required String title,
    required List<String> items,
    required String selectedValue,
    required ValueChanged<String> onSelected,
    required bool isDark,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final selected = item == selectedValue;
            return ListTile(
              title: Text(
                item,
                style: GoogleFonts.inter(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? AppTheme.primary
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
              trailing: selected
                  ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                onSelected(item);
              },
            );
          }),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final dividerColor = isDark ? Colors.white10 : const Color(0xFFE5E7EB);
          return Container(
            height: MediaQuery.of(context).size.height * 0.74,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1116) : Colors.white,
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
                          setModalState(() {});
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
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    children: [
                      _buildSelectionRow('Sort by', _selectedSort, isDark, () {
                        _showPicker(
                          title: 'Sort by',
                          items: _sortOptions,
                          selectedValue: _selectedSort,
                          isDark: isDark,
                          onSelected: (value) {
                            setState(() => _selectedSort = value);
                            setModalState(() {});
                          },
                        );
                      }),
                      Divider(height: 1, color: dividerColor),
                      _buildSelectionRow('Type', _selectedType, isDark, () {
                        _showPicker(
                          title: 'Type',
                          items: _types,
                          selectedValue: _selectedType,
                          isDark: isDark,
                          onSelected: (value) {
                            setState(() => _selectedType = value);
                            setModalState(() {});
                          },
                        );
                      }),
                      Divider(height: 1, color: dividerColor),
                      _buildSelectionRow('Semester', _selectedSemester ?? 'All', isDark, () {
                        _showPicker(
                          title: 'Semester',
                          items: ['All', ..._semesters],
                          selectedValue: _selectedSemester ?? 'All',
                          isDark: isDark,
                          onSelected: (value) {
                            setState(() => _selectedSemester = value == 'All' ? null : value);
                            setModalState(() {});
                          },
                        );
                      }),
                      Divider(height: 1, color: dividerColor),
                      _buildSelectionRow('Branch', _selectedBranch ?? 'All', isDark, () {
                        _showPicker(
                          title: 'Branch',
                          items: _branches.isEmpty ? ['All'] : ['All', ..._branches],
                          selectedValue: _selectedBranch ?? 'All',
                          isDark: isDark,
                          onSelected: (value) async {
                            setState(() {
                              _selectedBranch = value == 'All' ? null : value;
                              _selectedSubject = null;
                              _subjectFetchId++;
                            });
                            setModalState(() {});
                            final fetchId = _subjectFetchId;
                            if (_selectedBranch == null) {
                              setState(() => _subjects = []);
                              setModalState(() {});
                              return;
                            }
                            final subjects = await _supabaseService.getUniqueValues(
                              'subject',
                              widget.collegeId,
                              branch: _selectedBranch,
                            );
                            if (!mounted || fetchId != _subjectFetchId) return;
                            setState(() => _subjects = subjects);
                            setModalState(() {});
                          },
                        );
                      }),
                      Divider(height: 1, color: dividerColor),
                      _buildSelectionRow(
                        'Subject',
                        _selectedSubject ?? (_selectedBranch == null ? 'Select branch first' : 'All'),
                        isDark,
                        _selectedBranch == null
                            ? null
                            : () {
                                _showPicker(
                                  title: 'Subject',
                                  items: _subjects.isEmpty ? ['All'] : ['All', ..._subjects],
                                  selectedValue: _selectedSubject ?? 'All',
                                  isDark: isDark,
                                  onSelected: (value) {
                                    setState(() => _selectedSubject = value == 'All' ? null : value);
                                    setModalState(() {});
                                  },
                                );
                              },
                      ),
                    ],
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
                    ),
                    child: Text(
                      'Show results',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectionRow(
    String label,
    String value,
    bool isDark,
    VoidCallback? onTap,
  ) {
    final mutedColor = isDark ? Colors.white70 : const Color(0xFF6B7280);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF111827),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: mutedColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: mutedColor),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildEmptySearchState({
    required bool isDark,
    required IconData icon,
    required String label,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: isDark ? Colors.white12 : Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: isDark ? Colors.grey : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    final dividerColor = isDark ? Colors.white10 : Colors.black12;
    final searchSurfaceColor = isDark ? Colors.black : const Color(0xFFF4F6FB);
    final searchBorderColor = _hasFilters
        ? AppTheme.primary.withValues(alpha: 0.55)
        : (isDark ? Colors.white24 : const Color(0xFFE1E7F0));
    final filterBackground = _hasFilters
        ? AppTheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)
        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06));
    final filterTextColor = _hasFilters
        ? AppTheme.primary
        : (isDark ? Colors.white70 : const Color(0xFF111827));

    final showResults = _searchController.text.trim().isNotEmpty || _hasFilters;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: bgColor,
              padding: const EdgeInsets.only(top: 16, bottom: 10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        tag: 'following_search_bar',
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: searchSurfaceColor,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: searchBorderColor,
                                width: _hasFilters ? 1.2 : 0.9,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.07),
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
                                    color: isDark ? Colors.white70 : const Color(0xFF19212E),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _focusNode,
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: (_) => _performSearch(),
                                    style: TextStyle(
                                      color: isDark ? Colors.white : const Color(0xFF111827),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: widget.searchHint,
                                      hintStyle: TextStyle(
                                        color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                if (_searchController.text.isNotEmpty)
                                  IconButton(
                                    iconSize: 18,
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.clear_rounded,
                                      color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _results = []);
                                    },
                                  ),
                                Container(width: 1, height: 28, color: dividerColor),
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
                                            borderRadius: BorderRadius.circular(11),
                                            border: Border.all(
                                              color: _hasFilters
                                                  ? AppTheme.primary.withValues(alpha: 0.4)
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
                                              alignment: Alignment.center,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF0EA5E9),
                                                shape: BoxShape.circle,
                                              ),
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
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : !showResults
                  ? _buildEmptySearchState(
                      isDark: isDark,
                      icon: Icons.search_rounded,
                      label: widget.canManageAdminResources
                          ? 'Search moderation resources'
                          : 'Search following resources',
                    )
                  : _results.isEmpty
                  ? _buildEmptySearchState(
                      isDark: isDark,
                      icon: Icons.search_off_rounded,
                      label: 'No resources found',
                    )
                  : AnimationLimiter(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final resource = _results[index];
                          final isApproved = resource.isApprovedStatus;
                          final isPending = resource.isPendingStatus;
                          final isRejected = resource.isRejectedStatus;
                          return AnimationConfiguration.staggeredList(
                            position: index,
                            duration: const Duration(milliseconds: 375),
                            child: SlideAnimation(
                              verticalOffset: 50.0,
                              child: FadeInAnimation(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: ResourceCard(
                                    resource: resource,
                                    userEmail: widget.userEmail,
                                    deferRemoteStateHydration: true,
                                    showModerationControls:
                                        widget.canManageAdminResources,
                                    onApprove:
                                        widget.canManageAdminResources &&
                                            !isApproved
                                        ? () => _applyModeration(
                                            resource,
                                            Resource.approvedStatus,
                                          )
                                        : null,
                                    onReject:
                                        widget.canManageAdminResources &&
                                            isPending
                                        ? () => _applyModeration(
                                            resource,
                                            Resource.rejectedStatus,
                                          )
                                        : null,
                                    onRetract:
                                        widget.canManageAdminResources &&
                                            isApproved
                                        ? () => _applyModeration(
                                            resource,
                                            Resource.rejectedStatus,
                                          )
                                        : (widget.canManageAdminResources &&
                                              isRejected
                                          ? () => _applyModeration(
                                              resource,
                                              Resource.pendingStatus,
                                            )
                                          : null),
                                    onDelete: widget.canManageAdminResources
                                        ? () => _removeResource(resource)
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
