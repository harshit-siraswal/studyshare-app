import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/resource_card.dart';
import '../../models/resource.dart';
import 'following_screen.dart';
import '../../widgets/full_screen_image_viewer.dart';

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

      // 1. Parallelize independent fetches with type-safe variable awaiting
      final statsFuture = _supabaseService.getUserStats(widget.userEmail);
      final followersFuture = _supabaseService.getFollowersCount(widget.userEmail);
      final followingFuture = _supabaseService.getFollowingCount(widget.userEmail);
      final resourcesFuture = _supabaseService.getUserResources(widget.userEmail);
      final userInfoFuture = _supabaseService.getUserInfo(widget.userEmail);
      final statusFuture = currentUserEmail != null 
          ? _supabaseService.getFollowStatus(currentUserEmail, widget.userEmail)
          : Future.value(FollowStatus.notFollowing);
          
      // 2. Destructure typed results
      final stats = await statsFuture;
      final followers = await followersFuture;
      final following = await followingFuture;
      final resources = await resourcesFuture;
      final userInfo = await userInfoFuture;
      final status = await statusFuture;
      if (mounted) {
        setState(() {
          _uploadCount = stats['uploads'] ?? stats['contributions'] ?? 0;
          _followersCount = followers;
          _followingCount = following;
          _userResources = resources;
          _followStatus = status;
          final photo = userInfo?['profile_photo_url'] ?? userInfo?['photo_url'];
          _fetchedPhotoUrl = photo?.toString();
          _fetchedBio = userInfo?['bio'] as String?;
          _fetchedDisplayName = userInfo?['display_name'] as String?;
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
      final resources = await _supabaseService.getUserResources(widget.userEmail);
      if (mounted) {
        setState(() {
          _userResources = resources;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing resources: $e');
    }
  }

  String get _displayName => _fetchedDisplayName ?? widget.userName ?? widget.userEmail.split('@')[0];
  String get _avatarLetter => _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U';
  String? get _photoUrl => _fetchedPhotoUrl ?? widget.userPhotoUrl;
  String get _bio => _fetchedBio ?? 'No bio yet';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;

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
                Icon(Icons.error_outline_rounded, size: 64, color: AppTheme.error),
                const SizedBox(height: 16),
                Text(
                  'Failed to load profile',
                  style: GoogleFonts.inter(
                    fontSize: 20, 
                    fontWeight: FontWeight.bold,
                    color: textColor
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
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  Colors.transparent
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
                                  if (_photoUrl != null && _photoUrl!.isNotEmpty) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => FullScreenImageViewer(
                                          imageUrl: _photoUrl!,
                                          heroTag: 'avatar-${widget.userEmail}',
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
                                    child: _photoUrl != null && _photoUrl!.isNotEmpty
                                        ? Image.network(
                                            _photoUrl!,
                                            fit: BoxFit.cover,
                                            loadingBuilder: (context, child, loadingProgress) {
                                              if (loadingProgress == null) return child;
                                              return Center(
                                                child: CircularProgressIndicator(
                                                  value: loadingProgress.expectedTotalBytes != null
                                                      ? loadingProgress.cumulativeBytesLoaded /
                                                          loadingProgress.expectedTotalBytes!
                                                      : null,
                                                ),
                                              );
                                            },
                                            errorBuilder: (context, error, stackTrace) {
                                              return Center(
                                                child: Text(
                                                  _avatarLetter,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 32, 
                                                    fontWeight: FontWeight.bold, 
                                                    color: Colors.white
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
                                                color: Colors.white
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              // Follow Button
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: SizedBox(
                                  height: 36,
                                  child: _buildFollowButton(isDark),
                                ),
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
                            ],
                           ),
                           const SizedBox(height: 4),
                           Text(
                            _bio,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                            ),
                           ),
                           const SizedBox(height: 16),
                           
                           // Stats Row
                           Row(
                            children: [
                              _buildXStat(_followersCount.toString(), 'Followers', textColor, isDark, () {
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => FollowingScreen(userEmail: widget.userEmail, initialTab: 0),
                                ));
                              }),
                              const SizedBox(width: 16),
                              _buildXStat(_followingCount.toString(), 'Following', textColor, isDark, () {
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => FollowingScreen(userEmail: widget.userEmail, initialTab: 1),
                                ));
                              }),
                              const SizedBox(width: 16),
                              _buildXStat(_uploadCount.toString(), 'Contributions', textColor, isDark, null),
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
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), // Extra bottom padding for floating bar
                        sliver: AnimationLimiter(
                          child: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                 final resource = _userResources[index];
                                 return AnimationConfiguration.staggeredList(
                                   position: index,
                                   duration: const Duration(milliseconds: 375),
                                   child: SlideAnimation(
                                     verticalOffset: 50.0,
                                     child: FadeInAnimation(
                                       child: Padding(
                                         padding: const EdgeInsets.only(bottom: 12),
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
                              },
                              childCount: _userResources.length,
                            ),
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

    return ElevatedButton(
      onPressed: _followLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        side: (_followStatus == FollowStatus.following || _followStatus == FollowStatus.pending)
            ? BorderSide(color: isDark ? Colors.white30 : Colors.black26)
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      child: _followLoading 
        ? SizedBox(
            width: 14, 
            height: 14, 
            child: CircularProgressIndicator(strokeWidth: 2, color: textColor)
          )
        : Text(
            text,
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
          ),
    );
  }

  Widget _buildXStat(String value, String label, Color textColor, bool isDark, VoidCallback? onTap) {
    final secondaryColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Text(
              value,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(color: secondaryColor),
            ),
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
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded, color: AppTheme.textMuted.withValues(alpha: 0.5), size: 32),
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
    final currentUserEmail = _authService.userEmail;
    if (currentUserEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to follow users')));
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
        await _supabaseService.cancelFollowRequest(currentUserEmail, widget.userEmail);
      } else {
        await _supabaseService.sendFollowRequest(currentUserEmail, widget.userEmail);
        final newStatus = await _supabaseService.getFollowStatus(currentUserEmail, widget.userEmail);
        if (mounted) {
           setState(() => _followStatus = newStatus);
        }
      }
      // Success - just turn off loading
      if(mounted) setState(() => _followLoading = false);
    } catch (e) {
      // REVERT
      debugPrint('Follow action failed: $e');
      if (mounted) {
        setState(() {
           _followStatus = oldStatus;
           _followersCount = oldFollowers;
           _followLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action failed. Please try again.')));
      }
    }
  }
}
