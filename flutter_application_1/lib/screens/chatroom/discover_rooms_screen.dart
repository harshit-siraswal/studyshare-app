import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';

import '../../services/backend_api_service.dart';
import '../../widgets/advanced_search_bar.dart';
import '../../widgets/room_card.dart';
import '../common/search_screen.dart';
import '../../models/user.dart';

class DiscoverRoomsScreen extends StatefulWidget {
  final String collegeId;
  final String collegeDomain;
  final String userEmail;

  const DiscoverRoomsScreen({
    super.key,
    required this.collegeId,
    required this.collegeDomain,
    required this.userEmail,
  });

  @override
  State<DiscoverRoomsScreen> createState() => _DiscoverRoomsScreenState();
}

class _DiscoverRoomsScreenState extends State<DiscoverRoomsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _rooms = [];
  bool _isLoading = true;
  bool _hasWriteAccess = false;
  bool _roleLoaded = false;
  bool _roleLoadFailed = false;
  String? _loadErrorMessage;

  bool get _isReadOnly {
    if (_hasWriteAccess) return false;
    final email = widget.userEmail;
    final domain = widget.collegeDomain;
    if (domain.isEmpty) return true;
    return !email.endsWith(domain);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _supabaseService.attachContext(context);
    });
    _loadWriterRole();
    _loadRooms();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadRooms() async {
    try {
      final results = await Future.wait<Object?>([
        _supabaseService.getChatRooms(widget.userEmail, widget.collegeId),
        _supabaseService.getUserRoomIds(widget.userEmail),
      ]);
      final rooms = (results[0] as List).cast<Map<String, dynamic>>();
      final joinedIds = (results[1] as List)
          .map((id) => id.toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      // Show only public rooms that the user hasn't joined yet
      final publicRooms = rooms.where((r) {
        final isPrivate = r['is_private'] == true;
        final roomId = r['id'];
        return !isPrivate &&
            roomId != null &&
            !joinedIds.contains(roomId.toString().trim());
      }).toList();

      if (mounted) {
        setState(() {
          _rooms = publicRooms;
          _isLoading = false;
          _loadErrorMessage = null;
        });
      }
    } catch (e, st) {
      debugPrint('DiscoverRoomsScreen._loadRooms failed: $e\n$st');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadErrorMessage = 'Failed to load rooms. Please try again.';
        });
      }
    }
  }

  Future<void> _loadWriterRole() async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final authIdentity = _authService.currentIdentity;
        if (authIdentity != null) {
          if (!mounted) return;
          setState(() {
            _hasWriteAccess = authIdentity.canUploadResources;
            _roleLoaded = true;
            _roleLoadFailed = false;
          });
          return;
        }

        final role = await _supabaseService.getCurrentUserRole();
        if (!mounted) return;
        setState(() {
          _hasWriteAccess = role != AppRoles.readOnly;
          _roleLoaded = true;
          _roleLoadFailed = false;
        });
        return;
      } catch (e, st) {
        debugPrint(
          'DiscoverRoomsScreen._loadWriterRole attempt '
          '$attempt/$maxAttempts failed: $e\n$st',
        );
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _hasWriteAccess = false;
      _roleLoaded = true;
      _roleLoadFailed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    final isBusy = _isLoading;
    final canWrite = _roleLoaded && !_isReadOnly;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () =>
              Navigator.pop(context, true), // Return true to refresh parent
        ),
        title: Text(
          'Discover Rooms',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          if (canWrite)
            IconButton(
              icon: Icon(
                Icons.lock_open_rounded,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: _showJoinRoomDialog,
              tooltip: 'Join by Code',
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: AdvancedSearchBar(
              onTap: () {
                Navigator.of(context)
                    .push(
                      PageRouteBuilder(
                        transitionDuration: const Duration(milliseconds: 500),
                        pageBuilder: (context, animation, secondaryAnimation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SearchScreen(
                              allRooms: _rooms,
                              userEmail: widget.userEmail,
                              collegeId: widget.collegeId,
                              collegeDomain: widget.collegeDomain,
                            ),
                          );
                        },
                      ),
                    )
                    .then((_) {
                      // Optional: Reload rooms explicitly if needed
                      // _loadRooms();
                    });
              },
            ),
          ),
          if (_roleLoadFailed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.withValues(alpha: 0.12)
                      : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: isDark ? Colors.orange.shade300 : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Role check failed. Writer permissions may be limited.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _roleLoaded = false;
                          _roleLoadFailed = false;
                        });
                        _loadWriterRole();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),

          Expanded(
            child: isBusy
                ? _buildRoomGridSkeleton(isDark)
                : _loadErrorMessage != null
                ? Center(
                    child: Text(
                      _loadErrorMessage!,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _rooms.isEmpty
                ? Center(
                    child: Text(
                      'No public rooms found',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      20,
                      20,
                      canWrite ? 120 : 20,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio:
                              0.85, // Adjusted for RoomCard content
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    itemCount: _rooms.length,
                    itemBuilder: (context, index) {
                      return RoomCard(
                        room: _rooms[index],
                        userEmail: widget.userEmail,
                        collegeDomain: widget.collegeDomain,
                        onReturn: _loadRooms,
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? Hero(
              tag: 'fab_main',
              createRectTween: (begin, end) =>
                  MaterialRectCenterArcTween(begin: begin, end: end),
              child: FloatingActionButton(
                heroTag: null,
                onPressed: _showCreateRoomDialog,
                backgroundColor: AppTheme.primary,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            )
          : null,
    );
  }

  Widget _buildRoomGridSkeleton(bool isDark) {
    final base = isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE9ECF2);
    final highlight = isDark
        ? const Color(0xFF3A3A40)
        : const Color(0xFFF6F8FC);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.35, end: 1),
          duration: Duration(milliseconds: 700 + (index * 80)),
          curve: Curves.easeInOut,
          builder: (context, value, child) {
            return Opacity(opacity: value, child: child);
          },
          child: Container(
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 110,
                  height: 14,
                  decoration: BoxDecoration(
                    color: highlight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 84,
                  height: 10,
                  decoration: BoxDecoration(
                    color: highlight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 22,
                      decoration: BoxDecoration(
                        color: highlight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 70,
                      height: 22,
                      decoration: BoxDecoration(
                        color: highlight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showJoinRoomDialog() async {
    final rootContext = context;
    if (_isReadOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Read-only access. Use your college email to join rooms.',
          ),
        ),
      );
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeController = TextEditingController();

    try {
      await showDialog<void>(
        context: rootContext,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          title: Text(
            'Join Room',
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
          content: TextField(
            controller: codeController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: 'Enter Code',
              filled: true,
              fillColor: isDark ? Colors.black45 : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final code = codeController.text.trim();
                if (code.isEmpty) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('Please enter a room code.')),
                  );
                  return;
                }
                try {
                  await BackendApiService().joinChatRoom(
                    code,
                    widget.userEmail,
                    widget.collegeId,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                  if (mounted) {
                    _loadRooms();
                  }
                } catch (e, st) {
                  debugPrint('Join room failed: $e\n$st');
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                  if (rootContext.mounted) {
                    final messenger = ScaffoldMessenger.of(rootContext);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Failed to join room. Please try again.'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Join'),
            ),
          ],
        ),
      );
    } finally {
      codeController.dispose();
    }
  }

  Future<void> _showCreateRoomDialog() async {
    final parentContext = context;
    if (_isReadOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Read-only access. Use your college email to create rooms.',
          ),
        ),
      );
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    List<String> selectedTags = [];
    String? createRoomError;
    bool isPrivate = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void showDialogError(String message) {
              setDialogState(() {
                createRoomError = message;
              });
            }

            void addTag() {
              final value = tagCtrl.text.trim();
              if (value.isEmpty) return;
              final normalized = value.startsWith('#') ? value : '#$value';
              final tagBody = normalized.substring(1);
              final isAllowedTag = RegExp(
                r'^[A-Za-z0-9_-]+$',
              ).hasMatch(tagBody);
              const maxTagLength = 24;

              if (tagBody.length < 2) {
                showDialogError('Tag must have at least 2 characters after #.');
                return;
              }
              if (tagBody.length > maxTagLength) {
                showDialogError('Tag cannot exceed $maxTagLength characters.');
                return;
              }
              if (!isAllowedTag) {
                showDialogError(
                  'Tag can only contain letters, numbers, underscores, and hyphens.',
                );
                return;
              }
              if (selectedTags.contains(normalized)) {
                showDialogError('Tag already added.');
                return;
              }
              setDialogState(() {
                selectedTags.add(normalized);
                tagCtrl.clear();
                createRoomError = null;
              });
            }

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Create Room',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: () {
                      showDialog(
                        context: dialogContext,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: isDark
                              ? const Color(0xFF2C2C2E)
                              : Colors.white,
                          title: Text(
                            'About Tags',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          content: Text(
                            'Tags help other students find your room.\n\nAdd at least one tag like #placement, #hackathon, #dsa, etc.\n\nTags will be displayed on the room card.',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Got it'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Room Name',
                          filled: true,
                          fillColor: isDark
                              ? Colors.black45
                              : Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Description',
                          filled: true,
                          fillColor: isDark
                              ? Colors.black45
                              : Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // TAGS SECTION
                      Text(
                        'Tags (Required)',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: tagCtrl,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Add a tag (e.g. #dsa)',
                                isDense: true,
                                filled: true,
                                fillColor: isDark
                                    ? Colors.black45
                                    : Colors.grey.shade100,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) {
                                addTag();
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            color: AppTheme.primary,
                            onPressed: () {
                              addTag();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ...selectedTags.map(
                            (tag) => Chip(
                              label: Text(
                                tag,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onDeleted: () => setDialogState(
                                () => selectedTags.remove(tag),
                              ),
                              backgroundColor: AppTheme.primary.withValues(
                                alpha: 0.1,
                              ),
                              deleteIconColor: AppTheme.primary,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          if (selectedTags.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'Suggestions: ',
                                style: TextStyle(
                                  color: isDark ? Colors.white54 : Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (selectedTags.isEmpty)
                            ...['#placement', '#hackathon', '#dsa'].map(
                              (t) => GestureDetector(
                                onTap: () =>
                                    setDialogState(() => selectedTags.add(t)),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    t,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Text(
                        'Visibility',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Public'),
                            selected: !isPrivate,
                            onSelected: (selected) {
                              if (selected) {
                                setDialogState(() => isPrivate = false);
                              }
                            },
                            selectedColor: AppTheme.primary,
                            labelStyle: TextStyle(
                              color: !isPrivate
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: !isPrivate
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            backgroundColor: isDark
                                ? Colors.black45
                                : Colors.grey.shade100,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ChoiceChip(
                            label: const Text('Private'),
                            selected: isPrivate,
                            onSelected: (selected) {
                              if (selected) {
                                setDialogState(() => isPrivate = true);
                              }
                            },
                            selectedColor: AppTheme.primary,
                            labelStyle: TextStyle(
                              color: isPrivate
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: isPrivate
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            backgroundColor: isDark
                                ? Colors.black45
                                : Colors.grey.shade100,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ],
                      ),
                      if (createRoomError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          createRoomError!,
                          style: TextStyle(
                            color: isDark ? Colors.red.shade300 : Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    final trimmedName = nameCtrl.text.trim();
                    if (trimmedName.isEmpty) {
                      showDialogError('Room name is required.');
                      return;
                    }
                    if (selectedTags.isEmpty) {
                      showDialogError('Please add at least one tag.');
                      return;
                    }

                    setDialogState(() {
                      createRoomError = null;
                    });

                    try {
                      final res = await _supabaseService.createChatRoom(
                        name: trimmedName,
                        description: descCtrl.text,
                        isPrivate: isPrivate,
                        userEmail: widget.userEmail,
                        collegeId: widget.collegeId,
                        tags: selectedTags,
                      );
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                        if (mounted) {
                          _loadRooms();
                        }
                        if (res['joinCode'] != null && parentContext.mounted) {
                          final messenger = ScaffoldMessenger.of(parentContext);
                          Clipboard.setData(
                            ClipboardData(text: res['joinCode'].toString()),
                          );
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Room Created! Code copied: ${res['joinCode']}',
                              ),
                            ),
                          );
                        }
                      }
                    } catch (e, st) {
                      debugPrint('Create room failed: $e\n$st');
                      showDialogError(
                        'Failed to create room. Please try again.',
                      );
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      nameCtrl.dispose();
      descCtrl.dispose();
      tagCtrl.dispose();
    }
  }
}
