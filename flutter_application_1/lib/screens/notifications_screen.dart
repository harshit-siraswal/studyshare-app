import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_application_1/config/theme.dart';
import 'package:flutter_application_1/services/supabase_service.dart';
import 'package:flutter_application_1/widgets/user_avatar.dart';
import 'profile/user_profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final SupabaseService? supabaseService;

  const NotificationsScreen({super.key, this.supabaseService});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final SupabaseService _supabaseService;
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _followRequests = [];
  final Set<int> _processingFollowRequestIds = <int>{};

  @override
  void initState() {
    super.initState();
    _supabaseService = widget.supabaseService ?? SupabaseService();
    _fetchData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _supabaseService.attachContext(context);
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _supabaseService.getNotifications(),
        _supabaseService.getPendingFollowRequests(),
      ]);

      if (mounted) {
        setState(() {
          _notifications = results[0];
          _followRequests = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load notifications')),
        );
      }
    }
  }

  Future<void> _handleFollowRequest(int requestId, bool accept) async {
    try {
      setState(() => _processingFollowRequestIds.add(requestId));

      if (accept) {
        await _supabaseService.acceptFollowRequest(requestId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Follow request accepted')),
          );
        }
      } else {
        await _supabaseService.rejectFollowRequest(requestId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Follow request rejected')),
          );
        }
      }
      await _fetchData();
    } catch (e) {
      debugPrint('Error handling follow request: $e');
      _fetchData(); // Revert/Refresh
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _processingFollowRequestIds.remove(requestId));
      }
    }
  }

  void _openUserProfile({
    required String? email,
    required String name,
    required String? photoUrl,
  }) {
    final normalizedEmail = email?.trim() ?? '';
    if (normalizedEmail.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userEmail: normalizedEmail,
          userName: name,
          userPhotoUrl: photoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _resolveThemeStyles(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.inter(
            color: theme.textColor,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: theme.textColor),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: theme.textColor),
            onPressed: _fetchData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: (_notifications.isEmpty && _followRequests.isEmpty)
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.7,
                          child: _buildEmptyState(theme),
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      children: [
                        if (_followRequests.isNotEmpty) ...[
                          Text(
                            'Follow Requests',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._followRequests.map(
                            (req) =>
                                _buildFollowRequestItem(req, theme, isDark),
                          ),
                          const Divider(height: 32),
                        ],

                        if (_notifications.isNotEmpty) ...[
                          Text(
                            'Recent',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._notifications.map(
                            (n) => _buildNotificationItem(n, theme),
                          ),
                        ] else if (_followRequests.isNotEmpty) ...[
                          // If only requests and no other notifications
                          const SizedBox(height: 24),
                          Center(
                            child: Text(
                              'No other notifications',
                              style: GoogleFonts.inter(
                                color: theme.secondaryTextColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
    );
  }

  Widget _buildFollowRequestItem(
    Map<String, dynamic> request,
    _NotificationThemeStyles theme,
    bool isDark,
  ) {
    final requester = request['requester'];
    final requesterName = requester != null
        ? (requester['display_name'] ?? 'User')
        : 'Unknown User';
    final requesterUsername = requester != null
        ? (requester['username'] ?? '')
        : '';
    final requesterPhoto = requester?['photo_url'];
    final requestId = request['id'] as int?;
    final isProcessing =
        requestId != null && _processingFollowRequestIds.contains(requestId);

    if (requestId == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _openUserProfile(
              email: requester?['email']?.toString(),
              name: requesterName,
              photoUrl: requesterPhoto?.toString(),
            ),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  UserAvatar(
                    photoUrl: requesterPhoto,
                    radius: 20,
                    displayName: requesterName,
                    onTap: () => _openUserProfile(
                      email: requester?['email']?.toString(),
                      name: requesterName,
                      photoUrl: requesterPhoto?.toString(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(
                              color: theme.textColor,
                              fontSize: 14,
                            ),
                            children: [
                              TextSpan(
                                text: requesterName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: ' requested to follow you'),
                            ],
                          ),
                        ),
                        if (requesterUsername.isNotEmpty)
                          Text(
                            '@$requesterUsername',
                            style: GoogleFonts.inter(
                              color: theme.secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          timeago.format(
                            DateTime.tryParse(
                                  request['created_at']?.toString() ?? '',
                                ) ??
                                DateTime.now(),
                          ),
                          style: GoogleFonts.inter(
                            color: theme.secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isProcessing
                      ? null
                      : () => _handleFollowRequest(requestId, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(
                      color: theme.secondaryTextColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    isProcessing ? 'Working...' : 'Delete',
                    style: GoogleFonts.inter(
                      color: theme.textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () => _handleFollowRequest(requestId, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          'Confirm',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(
    Map<String, dynamic> notification,
    _NotificationThemeStyles theme,
  ) {
    final type = notification['type'];
    final isRead = notification['is_read'] ?? false;

    IconData icon;
    Color iconColor;
    Color iconBg;

    // Customize icon based on type
    switch (type) {
      case 'follow_accepted':
        icon = Icons.check_circle_rounded;
        iconColor = Colors.green;
        iconBg = Colors.green.withValues(alpha: 0.1);
        break;
      case 'department_notice':
        icon = Icons.campaign_rounded;
        iconColor = Colors.orange;
        iconBg = Colors.orange.withValues(alpha: 0.1);
        break;
      case 'admin_broadcast':
        icon = Icons.info_rounded;
        iconColor = Colors.blue;
        iconBg = Colors.blue.withValues(alpha: 0.1);
        break;
      case 'resource_approved':
        icon = Icons.verified_rounded;
        iconColor = AppTheme.primary;
        iconBg = AppTheme.primary.withValues(alpha: 0.1);
        break;
      default:
        icon = Icons.notifications_rounded;
        iconColor = theme.secondaryTextColor;
        iconBg = theme.secondaryTextColor.withValues(alpha: 0.1);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isRead
            ? Colors.transparent
            : theme.secondaryTextColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(
          notification['title'] ?? 'Notification',
          style: GoogleFonts.inter(
            color: theme.textColor,
            fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              notification['message'] ?? '',
              style: GoogleFonts.inter(
                color: theme.secondaryTextColor,
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              timeago.format(
                DateTime.tryParse(
                      notification['created_at']?.toString() ?? '',
                    ) ??
                    DateTime.now(),
              ),
              style: GoogleFonts.inter(
                color: theme.secondaryTextColor.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
        onTap: () {
          if (!isRead && notification['id'] != null) {
            final notificationId = notification['id'].toString();
            // Optimistic update
            setState(() {
              notification['is_read'] = true;
            });
            _supabaseService.markNotificationRead(notificationId).catchError((
              e,
            ) {
              debugPrint('Failed to mark notification as read: $e');
              // Revert on error
              if (mounted) {
                setState(() {
                  notification['is_read'] = false;
                });
              }
            });
          }
        },
      ),
    );
  }

  Widget _buildEmptyState(_NotificationThemeStyles theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 64,
            color: theme.iconColor,
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: theme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  _NotificationThemeStyles _resolveThemeStyles(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _NotificationThemeStyles(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      textColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
      secondaryTextColor: isDark
          ? AppTheme.darkTextSecondary
          : AppTheme.lightTextSecondary,
      iconColor: isDark
          ? AppTheme.darkTextSecondary
          : AppTheme.lightTextSecondary,
    );
  }
}

class _NotificationThemeStyles {
  final Color backgroundColor;
  final Color textColor;
  final Color secondaryTextColor;
  final Color iconColor;

  const _NotificationThemeStyles({
    required this.backgroundColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.iconColor,
  });
}
