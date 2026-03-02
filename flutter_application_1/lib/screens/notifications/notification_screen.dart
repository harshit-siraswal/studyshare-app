import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../models/notification_model.dart';
import '../../services/backend_api_service.dart';
import '../../services/supabase_service.dart';
import '../profile/user_profile_screen.dart';
import '../viewer/pdf_viewer_screen.dart';
import '../notices/notice_detail_screen.dart';
import '../../models/department_account.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;
  final List<String> _tabs = ['All', 'Follows', 'Activity'];
  final BackendApiService _api = BackendApiService();
  final SupabaseService _supabaseService = SupabaseService();

  bool _isLoading = false;
  String? _error;
  List<NotificationModel> _notifications = [];
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  final int _limit = 20;

  List<NotificationModel> get _filteredNotifications {
    if (_tabController.index == 1) {
      return _notifications.where((n) => n.type == 'follow_request').toList();
    } else if (_tabController.index == 2) {
      return _notifications.where((n) => n.type != 'follow_request').toList();
    }
    return _notifications;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _scrollController.addListener(_onScroll);
    _loadNotifications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadNotifications(loadMore: true);
      }
    }
  }

  Future<void> _loadNotifications({bool loadMore = false}) async {
    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
        _offset = 0; // Reset offset on pull-to-refresh
      });
    }

    try {
      final currentOffset = loadMore ? _offset : 0;

      final rawList = await _api.getNotifications(
        limit: _limit,
        offset: currentOffset,
      );
      final newItems = rawList
          .map((e) => NotificationModel.fromJson(e))
          .toList();

      setState(() {
        if (loadMore) {
          _notifications.addAll(newItems);
        } else {
          _notifications = newItems;
        }

        _offset += newItems.length;
        _hasMore = newItems.length >= _limit;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (loadMore) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Failed to load more: $e')));
          } else {
            _error = e.toString();
          }
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _api.markAllNotificationsRead(contextForRecaptcha: context);
      setState(() {
        for (var i = 0; i < _notifications.length; i++) {
          if (!_notifications[i].isRead) {
            _notifications[i] = _notifications[i].copyWith(isRead: true);
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark all as read: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final textColor = isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final secondaryTextColor = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        title: Text(
          'Notifications',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          if (_notifications.any((n) => !n.isRead))
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                'Mark all read',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            onTap: (_) => setState(() {}),
            indicatorColor: AppTheme.primary,
            indicatorWeight: 3,
            labelColor: AppTheme.primary,
            unselectedLabelColor: secondaryTextColor,
            labelStyle: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            unselectedLabelStyle: GoogleFonts.inter(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
      ),
      body: _isLoading && _notifications.isEmpty
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
          ? Center(
              child: Text(
                'Error loading notifications',
                style: GoogleFonts.inter(color: AppTheme.error),
              ),
            )
          : _filteredNotifications.isEmpty
          ? _buildEmptyState(isDark)
          : RefreshIndicator(
              onRefresh: () => _loadNotifications(loadMore: false),
              color: AppTheme.primary,
              child: ListView.builder(
                controller: _scrollController,
                itemCount:
                    _filteredNotifications.length + (_isLoadingMore ? 1 : 0),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) {
                  if (index == _filteredNotifications.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primary,
                        ),
                      ),
                    );
                  }
                  final n = _filteredNotifications[index];
                  return _buildNotificationCard(
                    n,
                    isDark,
                    textColor,
                    secondaryTextColor,
                  );
                },
              ),
            ),
    );
  }

  Widget _buildNotificationCard(
    NotificationModel n,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final highlightColor = isDark
        ? AppTheme.primary.withValues(alpha: 0.08)
        : AppTheme.primary.withValues(alpha: 0.05);

    final tileColor = n.isRead ? cardColor : highlightColor;

    return Dismissible(
      key: Key('notification_${n.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade400,
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
      ),
      onDismissed: (_) async {
        // Optimistic remove
        final index = _notifications.indexOf(n);
        setState(() {
          _notifications.removeAt(index);
        });

        try {
          await _api.deleteNotification(n.id, contextForRecaptcha: context);
        } catch (e) {
          // Revert on failure
          if (mounted) {
            setState(() {
              _notifications.insert(index, n);
            });
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
          }
        }
      },
      child: GestureDetector(
        onTap: () => _handleTap(n),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(14),
            border: n.isRead
                ? null
                : Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    width: 1,
                  ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar or Icon
              _buildLeadingAvatar(n, isDark),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (n.actorName != null) ...[
                          Text(
                            n.actorName!,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _getActionText(n.type),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: secondaryColor,
                          ),
                        ),
                        const Spacer(),
                        if (!n.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.message,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: secondaryColor,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeago.format(n.createdAt),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: secondaryColor.withValues(alpha: 0.7),
                      ),
                    ),
                    // Follow request actions
                    if (n.type == 'follow_request' &&
                        n.followRequestId != null &&
                        !n.actionTaken) ...[
                      const SizedBox(height: 12),
                      _buildFollowActions(n),
                    ],
                    if (n.actionTaken && n.type == 'follow_request')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Request processed',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: secondaryColor,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getActionText(String type) {
    switch (type) {
      case 'follow_request':
        return 'wants to follow you';
      case 'follow_accepted':
        return 'accepted your request';
      case 'follow_rejected':
        return 'declined your request';
      case 'resource_posted':
        return 'posted a new resource';
      case 'admin_broadcast':
        return 'sent an announcement';
      case 'department_notice':
        return 'posted a notice';
      default:
        return '';
    }
  }

  String? _resolveActorEmail(NotificationModel n) {
    final raw = n.actorId;
    if (raw != null && raw.contains('@')) return raw;

    final data = n.data;
    if (data == null) return null;

    final candidates = [
      data['actor_email'],
      data['actorEmail'],
      data['user_email'],
      data['userEmail'],
      data['email'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.contains('@')) return candidate;
    }

    return null;
  }

  Future<void> _handleTap(NotificationModel n) async {
    await _markRead(n);

    if (!mounted) return;

    // 1. Follow Request Navigation
    if (n.type == 'follow_request' || n.type == 'follow_accepted') {
      final actorEmail = _resolveActorEmail(n);
      if (actorEmail != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              userEmail: actorEmail,
              userName: n.actorName,
              userPhotoUrl: n.actorAvatar,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open profile for this notification.'),
          ),
        );
      }
      return;
    }

    // 2. Resource Posted Navigation
    // actionUrl contains the file URL
    if ((n.type == 'resource_posted' || n.type == 'resource_approved') &&
        n.actionUrl != null) {
      // Check if it's a PDF or we can infer title
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            pdfUrl: n.actionUrl!,
            title: n.title, // Or n.message
            // resourceId could be in data if available
            resourceId: n.data?['resourceId'],
          ),
        ),
      );
      return;
    }

    // 3. Department Notice Navigation
    // actionUrl looks like /notices?id=...
    if (n.type == 'department_notice' && n.actionUrl != null) {
      try {
        final uri = Uri.parse(n.actionUrl!);
        final noticeId = uri.queryParameters['id']; // OR n.data?['noticeId']
        final targetId = noticeId ?? n.data?['noticeId'];

        if (targetId != null) {
          // Show loading
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Loading notice...'),
              duration: Duration(seconds: 1),
            ),
          );

          // Fetch Notice
          final noticeMap = await _supabaseService.getNotice(
            targetId.toString(),
          );
          if (noticeMap == null) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Notice not found')));
            }
            return;
          }

          // Fetch Department/User Account
          // noticeMap should have 'department_id' or 'author_id'
          final authorId =
              noticeMap['department_id'] ?? noticeMap['author_id'] ?? n.actorId;
          DepartmentAccount? account;

          if (authorId != null) {
            account = await _supabaseService.getDepartmentProfile(authorId);
          }

          account ??= DepartmentAccount(
            id: authorId ?? 'unknown',
            name: n.actorName ?? 'Department',
            handle: '',
            avatarLetter: (n.actorName?.isNotEmpty == true)
                ? n.actorName![0]
                : 'D',
            color: Colors.blue,
          );
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NoticeDetailScreen(
                  notice: noticeMap,
                  account: account!,
                  collegeId: noticeMap['college_id']?.toString() ?? '',
                ),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error navigating to notice: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open notice')),
          );
        }
      }
      return;
    }
  }

  Future<void> _markRead(NotificationModel n) async {
    if (n.isRead) return;

    setState(() {
      final index = _notifications.indexWhere((element) => element.id == n.id);
      if (index != -1) {
        _notifications[index] = n.copyWith(isRead: true);
      }
    });

    try {
      await _api.markNotificationRead(n.id, contextForRecaptcha: context);
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
      // Optionally revert optimistic update or show error
      if (mounted) {
        setState(() {
          final index = _notifications.indexWhere(
            (element) => element.id == n.id,
          );
          if (index != -1) {
            _notifications[index] = n.copyWith(isRead: false);
          }
        });
      }
    }
  }

  Widget _buildLeadingAvatar(NotificationModel n, bool isDark) {
    // If we have an avatar URL, show user avatar with badge
    if (n.actorAvatar != null && n.actorAvatar!.isNotEmpty) {
      return Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey[300],
            child: ClipOval(
              child: Image.network(
                n.actorAvatar!,
                fit: BoxFit.cover,
                width: 48,
                height: 48,
                errorBuilder: (context, error, stackTrace) => Text(
                  n.actorName?.isNotEmpty == true
                      ? n.actorName![0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkBackground : Colors.white,
                shape: BoxShape.circle,
              ),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: _getTypeColor(n.type),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getTypeIcon(n.type),
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // No avatar - show icon only
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _getTypeColor(n.type).withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(_getTypeIcon(n.type), color: _getTypeColor(n.type), size: 22),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'follow_request':
        return Icons.person_add_rounded;
      case 'follow_accepted':
        return Icons.check_circle_rounded;
      case 'follow_rejected':
        return Icons.cancel_rounded;
      case 'resource_posted':
        return Icons.library_books_rounded;
      case 'admin_broadcast':
        return Icons.campaign_rounded;
      case 'department_notice':
        return Icons.local_activity_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'follow_request':
        return const Color(0xFF8B5CF6); // Violet
      case 'follow_accepted':
        return const Color(0xFF10B981); // Green
      case 'follow_rejected':
        return const Color(0xFFEF4444); // Red
      case 'resource_posted':
        return AppTheme.primary;
      case 'admin_broadcast':
        return const Color(0xFFEF4444); // Red
      case 'department_notice':
        return const Color(0xFFF59E0B); // Amber
      default:
        return Colors.grey;
    }
  }

  Widget _buildFollowActions(NotificationModel n) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _handleFollowAction(n, false),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Decline',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _handleFollowAction(n, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: Text(
              'Accept',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleFollowAction(NotificationModel n, bool accept) async {
    if (n.followRequestId == null) return;
    try {
      // Optimistic Update
      setState(() {
        final index = _notifications.indexWhere(
          (element) => element.id == n.id,
        );
        if (index != -1) {
          _notifications[index] = n.copyWith(actionTaken: true);
        }
      });

      final requestId = int.tryParse(n.followRequestId!);
      if (requestId == null) {
        throw FormatException(
          'Invalid follow request ID: ${n.followRequestId}',
        );
      }

      if (accept) {
        await _api.acceptFollowRequest(requestId);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Request accepted')));
        }
      } else {
        await _api.rejectFollowRequest(requestId);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Request declined')));
        }
      }
    } catch (e) {
      if (mounted) {
        _loadNotifications();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    }
  }

  Widget _buildEmptyState(bool isDark) {
    final tabName = _tabs[_tabController.index].toLowerCase();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              _tabController.index == 1
                  ? Icons.person_add_rounded
                  : Icons.notifications_none_rounded,
              size: 52,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No $tabName notifications',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tabController.index == 1
                ? 'Follow requests will appear here'
                : _tabController.index == 2
                ? 'Your activity will appear here'
                : 'Your notifications will appear here',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
