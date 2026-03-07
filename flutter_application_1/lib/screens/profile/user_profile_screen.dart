import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../services/backend_api_service.dart';
import '../../widgets/resource_card.dart';
import '../../models/resource.dart';
import '../../models/user.dart';
import 'following_screen.dart';
import '../../widgets/full_screen_image_viewer.dart';
import '../../widgets/user_badge.dart';
import 'edit_profile_screen.dart';
import '../../utils/admin_access.dart';

class UserProfileScreen extends StatefulWidget {
  final String userEmail;
  final String? userName;
  final String? userPhotoUrl;

  const UserProfileScreen({
    super.key,
    required this.userEmail,
    this.userName,
    this.userPhotoUrl,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();
  final BackendApiService _backendApiService = BackendApiService();

  bool _isLoading = true;
  String? _errorMessage;
  int _uploadCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  FollowStatus _followStatus = FollowStatus.notFollowing;
  bool _followLoading = false;
  List<Resource> _userResources = [];
  String? _fetchedPhotoUrl;
  String? _fetchedBio;
  String? _fetchedDisplayName;
  String _viewerRole = AppRoles.readOnly;
  String? _viewerCollegeId;
  String? _profileCollegeId;
  bool _banLoading = false;
  bool _isBanned = false;
  bool _viewerCanBanUsers = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUserEmail = _authService.userEmail;

      final statsFuture = _supabaseService.getUserStats(widget.userEmail);
      final resourcesFuture = _supabaseService.getUserResources(
        widget.userEmail,
      );
      final userInfoFuture = _supabaseService.getUserInfo(widget.userEmail);
      final currentProfileFuture = _supabaseService.getCurrentUserProfile(
        maxAttempts: 1,
      );
      final statusFuture = currentUserEmail != null
          ? _supabaseService.getFollowStatus(currentUserEmail, widget.userEmail)
          : Future.value(FollowStatus.notFollowing);

      final results = await Future.wait<dynamic>([
        statsFuture,
        resourcesFuture,
        userInfoFuture,
        currentProfileFuture,
        statusFuture,
      ]);

      final stats =
          (results[0] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final resources = (results[1] as List?)?.cast<Resource>() ?? <Resource>[];
      final userInfo = results[2] as Map<String, dynamic>?;
      final currentProfile =
          (results[3] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final status = results[4] as FollowStatus;

      final followers = (stats['followers'] as num?)?.toInt() ?? 0;
      final following = (stats['following'] as num?)?.toInt() ?? 0;
      final uploads =
          ((stats['uploads'] ?? stats['contributions']) as num?)?.toInt() ?? 0;

      final viewerCollegeId = currentProfile['college_id']?.toString().trim();
      final profileCollegeId =
          userInfo?['college_id']?.toString().trim() ??
          userInfo?['collegeId']?.toString().trim();
      final viewerRole = resolveEffectiveProfileRole(currentProfile);
      final viewerCanBanUsers = canBanUsersProfile(currentProfile);
      final isBanned = _resolveBanStatus(userInfo);
      if (mounted) {
        setState(() {
          _uploadCount = uploads;
          _followersCount = followers;
          _followingCount = following;
          _userResources = resources;
          _followStatus = status;
          final photo =
              userInfo?['profile_photo_url'] ?? userInfo?['photo_url'];
          _fetchedPhotoUrl = photo?.toString();
          _fetchedBio = userInfo?['bio']?.toString();
          _fetchedDisplayName = userInfo?['display_name']?.toString();
          _viewerRole = viewerRole;
          _viewerCanBanUsers = viewerCanBanUsers;
          _viewerCollegeId = viewerCollegeId;
          _profileCollegeId = profileCollegeId;
          _isBanned = isBanned;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Unable to load profile. Please try again.";
        });
      }
    }
  }

  Future<void> _refreshResourcesOnly() async {
    try {
      final resources = await _supabaseService.getUserResources(
        widget.userEmail,
      );
      if (mounted) {
        setState(() {
          _userResources = resources;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing resources: $e');
    }
  }

  String get _displayName =>
      _fetchedDisplayName ?? widget.userName ?? widget.userEmail.split('@')[0];
  String get _avatarLetter =>
      _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U';
  String? get _photoUrl => _fetchedPhotoUrl ?? widget.userPhotoUrl;
  String get _bio => _fetchedBio ?? 'No bio yet';
  bool get _isSelfProfile => _authService.userEmail == widget.userEmail;
  bool get _isTeacherOrAdminViewer =>
      _viewerRole == AppRoles.teacher || _viewerRole == AppRoles.admin;
  bool get _canBanViewedUser =>
      !_isSelfProfile &&
      !_isBanned &&
      _isTeacherOrAdminViewer &&
      _viewerCanBanUsers;

  bool _resolveBanStatus(Map<String, dynamic>? userInfo) {
    if (userInfo == null) return false;
    final candidates = <dynamic>[
      userInfo['is_banned'],
      userInfo['isBanned'],
      userInfo['banned'],
      userInfo['ban_status'],
    ];
    const bannedStatuses = <String>{
      'banned',
      'blocked',
      'suspended',
      'disabled',
      'deactivated',
      'terminated',
      'revoked',
      'restricted',
    };
    for (final rawValue in candidates) {
      if (rawValue == null) continue;
      if (rawValue is bool) {
        if (rawValue) return true;
        continue;
      }
      if (rawValue is num) {
        if (rawValue != 0) return true;
        continue;
      }
      final value = rawValue.toString().trim().toLowerCase();
      if (value.isEmpty) continue;
      if (value == 'true' || value == '1' || value == 'yes') {
        return true;
      }
      if (value == 'false' || value == '0' || value == 'no') {
        continue;
      }
      if (bannedStatuses.contains(value)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final textColor = isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 64,
                  color: AppTheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load profile',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadUserProfile,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black,
                    Colors.black,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.05, 0.85, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: SafeArea(
                bottom: false, // Allow content to go behind bottom bar
                child: CustomScrollView(
                  slivers: [
                    // Profile Header Section
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Avatar
                                InkWell(
                                  borderRadius: BorderRadius.circular(40),
                                  onTap: () {
                                    if (_photoUrl != null &&
                                        _photoUrl!.isNotEmpty) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              FullScreenImageViewer(
                                                imageUrl: _photoUrl!,
                                                heroTag:
                                                    'avatar-${widget.userEmail}',
                                              ),
                                        ),
                                      );
                                    }
                                  },
                                  child: Hero(
                                    tag: 'avatar-${widget.userEmail}',
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child:
                                          _photoUrl != null &&
                                              _photoUrl!.isNotEmpty
                                          ? Image.network(
                                              _photoUrl!,
                                              fit: BoxFit.cover,
                                              loadingBuilder: (context, child, loadingProgress) {
                                                if (loadingProgress == null) {
                                                  return child;
                                                }
                                                return Center(
                                                  child: CircularProgressIndicator(
                                                    value:
                                                        loadingProgress
                                                                .expectedTotalBytes !=
                                                            null
                                                        ? loadingProgress
                                                                  .cumulativeBytesLoaded /
                                                              loadingProgress
                                                                  .expectedTotalBytes!
                                                        : null,
                                                  ),
                                                );
                                              },
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                    return Center(
                                                      child: Text(
                                                        _avatarLetter,
                                                        style:
                                                            GoogleFonts.inter(
                                                              fontSize: 32,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                            )
                                          : Center(
                                              child: Text(
                                                _avatarLetter,
                                                style: GoogleFonts.inter(
                                                  fontSize: 32,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                // Follow + moderation actions
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: _buildProfileActions(isDark),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Name & Bio
                            Row(
                              children: [
                                Text(
                                  _displayName,
                                  style: GoogleFonts.inter(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                UserBadge(email: widget.userEmail, size: 18),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _bio,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Stats Row
                            Row(
                              children: [
                                _buildXStat(
                                  _followersCount.toString(),
                                  'Followers',
                                  textColor,
                                  isDark,
                                  () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => FollowingScreen(
                                          userEmail: widget.userEmail,
                                          initialTab: 0,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 16),
                                _buildXStat(
                                  _followingCount.toString(),
                                  'Following',
                                  textColor,
                                  isDark,
                                  () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => FollowingScreen(
                                          userEmail: widget.userEmail,
                                          initialTab: 1,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 16),
                                _buildXStat(
                                  _uploadCount.toString(),
                                  'Contributions',
                                  textColor,
                                  isDark,
                                  null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            const Divider(height: 1),
                            const SizedBox(height: 16),
                            Text(
                              "Contributions",
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),

                    // Content Grid
                    _userResources.isEmpty
                        ? SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: _buildEmptyState(cardColor, isDark),
                            ),
                          )
                        : SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              140,
                            ), // Extra bottom padding for floating bar
                            sliver: AnimationLimiter(
                              child: SliverList(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final resource = _userResources[index];
                                  return AnimationConfiguration.staggeredList(
                                    position: index,
                                    duration: const Duration(milliseconds: 375),
                                    child: SlideAnimation(
                                      verticalOffset: 50.0,
                                      child: FadeInAnimation(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: ResourceCard(
                                            resource: resource,
                                            userEmail: widget.userEmail,
                                            onVoteChanged: () {
                                              // Optimistic / Local update instead of full reload
                                              // We can't easily know the new vote count from here without passing it back,
                                              // but usually the Card handles the immediate UI cache.
                                              // If we want to reflect it in THIS list without reload, we would need the new state.
                                              // Assuming the ResourceCard handles its own display state, we might just need
                                              // to update our local data model if we want to persist it across scrolls.

                                              // Re-fetching just resources would be lighter than full profile
                                              // But ideally we just update the specific item if we had the ID and new values.
                                              // For now, let's just fetch resources to be safe but not the whole profile stats
                                              _refreshResourcesOnly();
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }, childCount: _userResources.length),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFollowButton(bool isDark) {
    String text;
    Color bgColor;
    Color textColor;
    VoidCallback? onTap;

    final isSelfProfile = _isSelfProfile;

    if (isSelfProfile) {
      text = 'Edit Profile';
      bgColor = isDark ? Colors.white12 : Colors.grey.shade200;
      textColor = isDark ? Colors.white : Colors.black;
      onTap = () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditProfileScreen(
              initialName: _fetchedDisplayName ?? widget.userName ?? '',
              initialPhotoUrl: _fetchedPhotoUrl ?? widget.userPhotoUrl,
              initialBio: _fetchedBio ?? '',
              role: _viewerRole,
            ),
          ),
        );
      };
    } else {
      if (_isBanned) {
        text = 'Banned';
        bgColor = Colors.transparent;
        textColor = isDark ? Colors.redAccent.shade100 : Colors.red.shade700;
        onTap = null;
      } else {
        switch (_followStatus) {
          case FollowStatus.following:
            text = 'Following';
            bgColor = Colors.transparent;
            textColor = isDark ? Colors.white : Colors.black;
            onTap = _toggleFollow;
            break;
          case FollowStatus.pending:
            text = 'Requested';
            bgColor = Colors.transparent;
            textColor = isDark ? Colors.white70 : Colors.black87;
            onTap = _toggleFollow;
            break;
          case FollowStatus.notFollowing:
            text = 'Follow';
            bgColor = isDark ? Colors.white : Colors.black;
            textColor = isDark ? Colors.black : Colors.white;
            onTap = _toggleFollow;
            break;
        }
      }
    }

    return ElevatedButton(
      onPressed: _followLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        side:
            (!isSelfProfile &&
                (_followStatus == FollowStatus.following ||
                    _followStatus == FollowStatus.pending))
            ? BorderSide(color: isDark ? Colors.white30 : Colors.black26)
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      child: _followLoading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: textColor,
              ),
            )
          : Text(
              text,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
    );
  }

  Widget _buildProfileActions(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(height: 36, child: _buildFollowButton(isDark)),
        if (_canBanViewedUser) ...[
          const SizedBox(height: 8),
          SizedBox(height: 36, child: _buildBanButton(isDark)),
        ],
      ],
    );
  }

  Widget _buildBanButton(bool isDark) {
    final borderColor = isDark ? Colors.redAccent.shade200 : Colors.redAccent;
    final textColor = isDark ? Colors.redAccent.shade100 : Colors.red.shade700;
    return OutlinedButton(
      onPressed: _banLoading ? null : _handleBanUser,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: _banLoading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: textColor,
              ),
            )
          : Text(
              'Ban User',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: textColor,
              ),
            ),
    );
  }

  Future<void> _handleBanUser() async {
    if (!_canBanViewedUser) return;

    final reasonController = TextEditingController();
    final reason = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
          title: Text(
            'Ban user?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will block ${widget.userEmail} from using the app.',
                style: GoogleFonts.inter(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(reasonController.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text('Ban'),
            ),
          ],
        );
      },
    );
    reasonController.dispose();

    if (reason == null) return;

    setState(() => _banLoading = true);
    try {
      final response = await _backendApiService.banUserAsAdmin(
        email: widget.userEmail,
        reason: reason.isEmpty ? null : reason,
        collegeId: (_viewerCollegeId?.isNotEmpty ?? false)
            ? _viewerCollegeId
            : (_profileCollegeId?.isNotEmpty ?? false)
            ? _profileCollegeId
            : null,
      );
      if (!mounted) return;
      final message =
          response['message']?.toString() ??
          '${widget.userEmail} has been banned';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(() => _isBanned = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to ban user: '
            '${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _banLoading = false);
      }
    }
  }

  Widget _buildXStat(
    String value,
    String label,
    Color textColor,
    bool isDark,
    VoidCallback? onTap,
  ) {
    final secondaryColor = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.inter(color: secondaryColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color cardColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_rounded,
            color: AppTheme.textMuted.withValues(alpha: 0.5),
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            "No uploads yet",
            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFollow() async {
    if (_isBanned) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('This account is banned.')));
      return;
    }

    final currentUserEmail = _authService.userEmail;
    if (currentUserEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to follow users')),
      );
      return;
    }

    // 1. Calculate optimistic state
    final oldStatus = _followStatus;
    final oldFollowers = _followersCount;

    final isFollowing = oldStatus == FollowStatus.following;
    final isPending = oldStatus == FollowStatus.pending;

    // OPTIMISTIC UPDATE
    setState(() {
      _followLoading = true;
      if (isFollowing) {
        _followStatus = FollowStatus.notFollowing;
        _followersCount = (_followersCount - 1).clamp(0, 999999);
      } else if (isPending) {
        _followStatus = FollowStatus.notFollowing;
      } else {
        _followStatus = FollowStatus.pending;
      }
    });

    try {
      if (isFollowing) {
        await _supabaseService.unfollowUser(widget.userEmail);
      } else if (isPending) {
        await _supabaseService.cancelFollowRequest(
          currentUserEmail,
          widget.userEmail,
        );
      } else {
        await _supabaseService.sendFollowRequest(
          currentUserEmail,
          widget.userEmail,
        );
        final newStatus = await _supabaseService.getFollowStatus(
          currentUserEmail,
          widget.userEmail,
        );
        if (mounted) {
          setState(() {
            final wasFollowingBeforeAction =
                oldStatus == FollowStatus.following;
            _followStatus = newStatus;
            if (!wasFollowingBeforeAction &&
                newStatus == FollowStatus.following) {
              _followersCount += 1;
            }
          });
        }
      }
      // Success - just turn off loading
      if (mounted) setState(() => _followLoading = false);
    } catch (e) {
      // REVERT
      debugPrint('Follow action failed: $e');
      if (mounted) {
        setState(() {
          _followStatus = oldStatus;
          _followersCount = oldFollowers;
          _followLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action failed. Please try again.')),
        );
      }
    }
  }
}
