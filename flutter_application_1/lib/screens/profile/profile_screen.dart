import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../providers/theme_provider.dart';
import '../../models/resource.dart';
import '../../widgets/resource_card.dart';
import '../../utils/contribution_badge.dart';
import '../../utils/profile_photo_utils.dart';
import 'bookmarks_screen.dart';
import 'following_screen.dart';
import 'edit_profile_screen.dart';
import '../../widgets/paywall_dialog.dart';
import '../../services/subscription_service.dart';
import '../../services/download_service.dart';
import 'settings_screen.dart';
import 'explore_students_screen.dart';
import 'ai_token_usage_screen.dart';
import 'my_posts_screen.dart';
import 'badge_stickers_screen.dart';
import '../../models/user.dart';
import '../../widgets/animated_counter.dart';
import '../../data/academic_subjects_data.dart';
import '../../utils/ai_token_budget_utils.dart';
import '../../utils/admin_access.dart';

class ProfileScreen extends StatefulWidget {
  final String collegeName;
  final String collegeDomain;
  final VoidCallback onLogout;
  final VoidCallback onChangeCollege;
  final ThemeProvider themeProvider;

  const ProfileScreen({
    super.key,

    required this.collegeName,
    required this.collegeDomain,
    required this.onLogout,
    required this.onChangeCollege,
    required this.themeProvider,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  final SubscriptionService _subscriptionService = SubscriptionService();

  bool _profileLoading = true;
  String? _profilePhotoUrl;
  String? _profileDisplayName;
  String? _profileBio;
  String? _profileSemester;
  String? _profileBranch;
  String? _profileSubject;
  String _profileRole = AppRoles.readOnly;
  int _aiTokenBudget = 0;
  int _aiTokenUsed = 0;
  int _aiTokenRemaining = 0;
  int _aiTokenBaseBudget = 40160;
  int _aiTokenBudgetMultiplier = 1;
  int _aiTokenPremiumMultiplier = 10;
  int _aiTokenCycleDays = 30;
  DateTime? _aiTokenCycleStartedAt;
  DateTime? _aiTokenCycleEndsAt;
  static const int _tokensPerCredit = 2000;
  static const double _bottomNavBarAllowance = 124;
  Future<bool>? _isPremiumFuture;
  Future<List<Resource>>? _contributionsFuture;

  // Real stats
  int _uploadCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  ContributionBadge _contributionBadge = ContributionBadgeCatalog.resolve(0);

  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _myPostsSectionKey = GlobalKey(
    debugLabel: 'my_posts_section',
  );
  String _searchQuery = '';

  @override
  void dispose() {
    SupabaseService.aiTokenRefreshNotifier.removeListener(
      _handleAiTokenRefresh,
    );
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SupabaseService.aiTokenRefreshNotifier.addListener(_handleAiTokenRefresh);
    _refreshPremiumFuture();
    _loadStats();
    _loadProfile();
  }

  void _handleAiTokenRefresh() {
    if (!mounted) return;
    _loadProfile(forceRefresh: true);
  }

  void _refreshPremiumFuture() {
    _isPremiumFuture = _subscriptionService.isPremium();
  }

  void _refreshContributionsFuture() {
    final email = _userEmail;
    if (email.isEmpty) {
      _contributionsFuture = Future.value(const <Resource>[]);
      return;
    }
    _contributionsFuture = _supabaseService.getUserResources(
      email,
      approvedOnly: false,
    );
  }

  Future<void> _loadProfile({bool forceRefresh = false}) async {
    try {
      if (forceRefresh) {
        _supabaseService.invalidateCurrentUserProfileCache();
      }
      final profile = await _supabaseService.getCurrentUserProfile(
        maxAttempts: forceRefresh ? 2 : 1,
        forceRefresh: forceRefresh,
      );
      final tokenSnapshot =
          await AiTokenBudgetSnapshot.fromProfileWithLocalPremium(profile);
      final supportsSubjectField = isTeacherOrAdminProfile(profile);
      if (!mounted) return;
      setState(() {
        _profileDisplayName = profile['display_name']?.toString();
        _profilePhotoUrl = resolveProfilePhotoUrl(profile);
        _profileBio = profile['bio']?.toString();
        _profileSemester = profile['semester']?.toString();
        _profileBranch = profile['branch']?.toString();
        _profileSubject = supportsSubjectField
            ? profile['subject']?.toString()
            : null;
        final usedFromApi = _toSafeInt(profile['ai_token_used']);
        final remainingFromApi = _toSafeInt(profile['ai_token_remaining']);
        final resolvedBudget = tokenSnapshot.currentBudget;
        final resolvedUsed = usedFromApi.clamp(0, resolvedBudget);
        final resolvedRemaining = remainingFromApi > 0
            ? remainingFromApi.clamp(0, resolvedBudget)
            : (resolvedBudget - resolvedUsed).clamp(0, resolvedBudget);

        _aiTokenBudget = resolvedBudget;
        _aiTokenUsed = resolvedUsed;
        _aiTokenRemaining = resolvedRemaining;
        _aiTokenBaseBudget = tokenSnapshot.baseBudget;
        _aiTokenBudgetMultiplier = tokenSnapshot.budgetMultiplier;
        _aiTokenPremiumMultiplier = tokenSnapshot.premiumMultiplier;
        _aiTokenCycleDays = math.max(
          1,
          _toSafeInt(profile['ai_token_cycle_days']) > 0
              ? _toSafeInt(profile['ai_token_cycle_days'])
              : 30,
        );
        _aiTokenCycleStartedAt = DateTime.tryParse(
          profile['ai_token_cycle_started_at']?.toString() ?? '',
        );
        _aiTokenCycleEndsAt = DateTime.tryParse(
          profile['ai_token_cycle_ends_at']?.toString() ?? '',
        );
        _profileRole = resolveEffectiveProfileRole(profile);
        if (_contributionsFuture == null || forceRefresh) {
          _refreshContributionsFuture();
        }
        if (forceRefresh) {
          _refreshPremiumFuture();
        }
        _profileLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _loadStats() async {
    if (_authService.userEmail == null) {
      return;
    }
    try {
      final userEmail = _authService.userEmail!;
      final stats = await _supabaseService.getUserStats(userEmail);
      final contributions = _toSafeInt(
        stats['uploads'] ?? stats['contributions'] ?? 0,
      );
      final followingCount = _toSafeInt(stats['following']);
      final followersCount = _toSafeInt(stats['followers']);
      if (mounted) {
        setState(() {
          _uploadCount = contributions;
          _followersCount = followersCount;
          _followingCount = followingCount;
          _contributionBadge = ContributionBadgeCatalog.resolve(_uploadCount);
        });
      }
    } catch (e) {
      debugPrint('Failed to refresh profile stats: $e');
    }
  }

  String get _userEmail {
    final authEmail = (_authService.userEmail ?? '').trim();
    if (authEmail.isNotEmpty) return authEmail;
    return (_supabaseService.currentUserEmail ?? '').trim();
  }

  String get _displayName =>
      _profileDisplayName ?? _authService.displayName ?? 'User';
  String? get _photoUrl => _profilePhotoUrl ?? _authService.photoUrl;

  int _toSafeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatTokenWithCommas(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      buffer.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

  String _formatCreditCompact(int tokenValue) {
    if (tokenValue <= 0) return '0';
    final credits = tokenValue / _tokensPerCredit;
    return math.max(1, credits.round()).toString();
  }

  String _profileBranchLabel() {
    final branch = _profileBranch?.trim() ?? '';
    if (branch.isEmpty) return '';
    return getBranchShortLabel(branch);
  }

  Future<void> _handleLogout() async {
    try {
      await _authService.signOut();
      if (mounted) {
        widget.onLogout();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sign out: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteContribution(Resource resource) async {
    final userEmail = _userEmail;
    if (userEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to identify your account.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Contribution?'),
        content: Text(
          'This will permanently delete "${resource.title}" from your contributions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _supabaseService.deleteOwnedResource(
        resource: resource,
        ownerEmail: userEmail,
      );
      try {
        await DownloadService().deleteResource(
          resource.id,
          ownerEmail: userEmail,
        );
      } catch (cleanupError) {
        debugPrint(
          'Local contribution cleanup failed for ${resource.id}: '
          '$cleanupError',
        );
      }
      _supabaseService.invalidateResourceListCache();
      if (!mounted) return;
      setState(() => _refreshContributionsFuture());
      await _loadStats();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contribution deleted successfully.')),
      );
    } catch (e, stackTrace) {
      debugPrint('Failed to delete contribution: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete contribution. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine if we are in dark mode based on system/theme provider
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.getTextColor(context);
    final subTextColor = AppTheme.getTextColor(context, isPrimary: false);
    final bottomPadding =
        MediaQuery.of(context).padding.bottom + _bottomNavBarAllowance;
    assert(() {
      _buildContributionBadgeCard;
      return true;
    }());

    return Scaffold(
      backgroundColor: isDark ? Colors.black : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: null,
        title: Text(
          'My Profile',
          style: GoogleFonts.inter(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExploreStudentsScreen(userEmail: _userEmail),
                ),
              );
            },
            icon: Icon(Icons.people_outline_rounded, color: textColor),
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: textColor),
            onPressed: () async {
              // Open Settings Screen
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    onLogout: _handleLogout,
                    userEmail: _userEmail,
                    displayName: _profileDisplayName,
                    photoUrl: _profilePhotoUrl,
                    bio: _profileBio,
                    themeProvider: widget.themeProvider,
                  ),
                ),
              );
              // Refresh profile on return in case edits occurred
              if (mounted) _loadProfile(forceRefresh: true);
            },
          ),
        ],
      ),
      body: _profileLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadProfile(forceRefresh: true);
                await _loadStats();
                if (!mounted) return;
                setState(() {
                  _refreshPremiumFuture();
                  _refreshContributionsFuture();
                });
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildProfileHeader(textColor, subTextColor),
                    const SizedBox(height: 24),
                    _buildStatsRow(textColor, subTextColor),
                    const SizedBox(height: 16),
                    _buildBadgeStickerRow(textColor, subTextColor, isDark),
                    const SizedBox(height: 24),
                    _buildAiTokenUsageCard(textColor, subTextColor, isDark),
                    const SizedBox(height: 24),
                    FutureBuilder<bool>(
                      future: _isPremiumFuture ??= _subscriptionService
                          .isPremium(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError || !snapshot.hasData) {
                          return const SizedBox.shrink();
                        }
                        final isPremium = snapshot.data ?? false;
                        return isPremium
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: _buildUpgradeCard(),
                              );
                      },
                    ),
                    // Search & Filter
                    _buildSearchBar(isDark),
                    const SizedBox(height: 16),
                    // Offline Toggle (Only if Premium, or disabled if Free)
                    _buildOfflineToggle(textColor),
                    const SizedBox(height: 16),

                    // My Posts Link
                    _buildMyPostsLink(textColor),
                    const SizedBox(height: 16),

                    // Contributions Header
                    Align(
                      key: _myPostsSectionKey,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Contributions',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildContributionsList(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProfileHeader(Color textColor, Color subTextColor) {
    return FutureBuilder<bool>(
      future: _isPremiumFuture ??= _subscriptionService.isPremium(),
      builder: (context, snapshot) {
        final isPremium = snapshot.data ?? false;

        return Column(
          children: [
            Stack(
              children: [
                // Premium Glow/Ring
                if (isPremium)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFFD700,
                            ).withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),

                Container(
                  width: 104, // Slightly larger for border
                  height: 104,
                  padding: const EdgeInsets.all(3), // Space for the ring
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isPremium
                        ? const LinearGradient(
                            colors: [
                              Color(0xFFFFD700),
                              Color(0xFFFFA500),
                              Color(0xFFFFD700),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isPremium ? null : Colors.transparent,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isPremium
                            ? Colors.white
                            : textColor.withValues(alpha: 0.1),
                        width: isPremium ? 2 : 1,
                      ),
                      color: textColor.withValues(alpha: 0.05),
                    ),
                    child: ClipOval(
                      child: _photoUrl != null
                          ? Image.network(
                              _photoUrl!,
                              cacheWidth: 400,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Text(
                                    getInitials(_displayName),
                                    style: GoogleFonts.inter(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w600,
                                      color: textColor,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Text(
                                getInitials(_displayName),
                                style: GoogleFonts.inter(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),

                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () async {
                      final updated = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(
                            initialName: _displayName,
                            initialPhotoUrl: _photoUrl,
                            initialBio: _profileBio,
                            initialSemester: _profileSemester,
                            initialBranch: _profileBranch,
                            initialSubject: _profileSubject,
                            role: _profileRole,
                          ),
                        ),
                      );
                      if (updated != null && mounted) {
                        await _loadProfile(forceRefresh: true);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.edit,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(-20 * (1 - value), 0),
                  child: Opacity(opacity: value, child: child),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _displayName,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  if (isPremium) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified,
                      color: Color(0xFFFFD700),
                      size: 20,
                    ),
                  ],
                  const SizedBox(width: 8),
                  Tooltip(
                    message:
                        '${_contributionBadge.label}: ${_contributionBadge.description}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _contributionBadge.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _contributionBadge.color.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _contributionBadge.icon,
                            size: 14,
                            color: _contributionBadge.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _contributionBadge.label,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _contributionBadge.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(opacity: value, child: child),
                );
              },
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  Text(
                    '@${_profileDisplayName?.replaceAll(" ", "").toLowerCase() ?? "user"}',
                    style: GoogleFonts.inter(fontSize: 14, color: subTextColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _authService.userEmail ?? '', // Show Email
                    style: GoogleFonts.inter(fontSize: 13, color: subTextColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.collegeName,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 14, color: subTextColor),
                  ),
                  const SizedBox(height: 8),
                  if ((_profileSemester != null &&
                          _profileSemester!.isNotEmpty) ||
                      (_profileBranch != null && _profileBranch!.isNotEmpty))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            [
                              if (_profileBranch != null &&
                                  _profileBranch!.isNotEmpty)
                                _profileBranchLabel(),
                              if (_profileSemester != null &&
                                  _profileSemester!.isNotEmpty)
                                'Sem $_profileSemester',
                            ].join(' • '),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_profileBio != null && _profileBio!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _profileBio!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatsRow(Color textColor, Color subTextColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatItem(
          'Contributions',
          _uploadCount.toString(),
          textColor,
          subTextColor,
          () {
            // Already on profile showing contributions, maybe scroll down?
          },
        ),
        _buildStatItem(
          'Followers',
          _followersCount.toString(),
          textColor,
          subTextColor,
          () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    FollowingScreen(userEmail: _userEmail, initialTab: 0),
              ),
            );
            if (mounted) _loadStats();
          },
        ),
        _buildStatItem(
          'Following',
          _followingCount.toString(),
          textColor,
          subTextColor,
          () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    FollowingScreen(userEmail: _userEmail, initialTab: 1),
              ),
            );
            if (mounted) _loadStats();
          },
        ),
      ],
    );
  }

  Widget _buildBadgeStickerRow(
    Color textColor,
    Color subTextColor,
    bool isDark,
  ) {
    final tiers = ContributionBadgeCatalog.tiers;
    final currentIndex = tiers.indexWhere(
      (tier) => tier.id == _contributionBadge.id,
    );
    final previewBadges = <ContributionBadge>[
      if (currentIndex > 0) tiers[currentIndex - 1],
      _contributionBadge,
      if (currentIndex + 1 < tiers.length) tiers[currentIndex + 1],
    ];

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BadgeStickersScreen(
              contributionCount: _uploadCount,
              currentBadge: _contributionBadge,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Badge Stickers',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_contributionBadge.label} • $_uploadCount contributions',
                    style: GoogleFonts.inter(fontSize: 12, color: subTextColor),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                for (final badge in previewBadges)
                  Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: badge.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: badge.color.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(badge.icon, size: 16, color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: subTextColor),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color textColor,
    Color subTextColor,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedCounter(
            count: int.tryParse(value) ?? 0,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: subTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiTokenUsageCard(
    Color textColor,
    Color subTextColor,
    bool isDark,
  ) {
    final budget = _aiTokenBudget;
    final used = budget > 0 ? _aiTokenUsed.clamp(0, budget) : _aiTokenUsed;
    final remaining = budget > 0
        ? _aiTokenRemaining.clamp(0, budget)
        : _aiTokenRemaining;
    final progress = budget > 0 ? (used / budget).clamp(0.0, 1.0) : 0.0;
    final exhausted = budget > 0 && remaining <= 0;

    return GestureDetector(
      onTap: _openAiTokenUsageScreen,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          border: Border.all(
            color: exhausted
                ? AppTheme.error.withValues(alpha: 0.35)
                : AppTheme.primary.withValues(alpha: 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.token_rounded,
                  size: 18,
                  color: exhausted ? AppTheme.error : AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly AI Credits',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      if (_aiTokenCycleEndsAt != null)
                        Text(
                          'Resets on ${_aiTokenCycleEndsAt!.day}/${_aiTokenCycleEndsAt!.month}/${_aiTokenCycleEndsAt!.year}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: subTextColor,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: exhausted
                        ? AppTheme.error.withValues(alpha: 0.14)
                        : AppTheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    exhausted
                        ? 'Exhausted'
                        : '${_formatCreditCompact(remaining)} credits left',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: exhausted ? AppTheme.error : AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.info_outline_rounded, size: 16, color: subTextColor),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation<Color>(
                  exhausted ? AppTheme.error : AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildAiTokenMetric(
                  'Remaining',
                  _formatCreditCompact(remaining),
                  textColor,
                  subTextColor,
                ),
                _buildAiTokenMetric(
                  'Used',
                  _formatCreditCompact(used),
                  textColor,
                  subTextColor,
                ),
                _buildAiTokenMetric(
                  'Total',
                  _formatCreditCompact(budget > 0 ? budget : 40160),
                  textColor,
                  subTextColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '1 credit = ${_formatTokenWithCommas(_tokensPerCredit)} '
              'billable tokens (input + weighted output).',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: subTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAiTokenUsageScreen() async {
    final didRefresh = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AiTokenUsageScreen(
          budget: _aiTokenBudget,
          used: _aiTokenUsed,
          remaining: _aiTokenRemaining,
          baseBudget: _aiTokenBaseBudget,
          budgetMultiplier: _aiTokenBudgetMultiplier,
          premiumMultiplier: _aiTokenPremiumMultiplier,
          cycleDays: _aiTokenCycleDays,
          cycleStartedAt: _aiTokenCycleStartedAt,
          cycleEndsAt: _aiTokenCycleEndsAt,
        ),
      ),
    );
    if (didRefresh == true && mounted) {
      await _loadProfile(forceRefresh: true);
      await _loadStats();
    }
  }

  Widget _buildAiTokenMetric(
    String label,
    String value,
    Color textColor,
    Color subTextColor,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: subTextColor,
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildContributionBadgeCard(
    Color textColor,
    Color subTextColor,
    bool isDark,
  ) {
    final next = _contributionBadge.nextThreshold;
    final progress = ContributionBadgeCatalog.progressToNext(_uploadCount);
    final remaining = next == null ? 0 : (next - _uploadCount).clamp(0, 9999);

    return GestureDetector(
      onTap: () => _showBadgesBottomSheet(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              _contributionBadge.color.withValues(alpha: isDark ? 0.15 : 0.08),
              _contributionBadge.color.withValues(alpha: isDark ? 0.05 : 0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: _contributionBadge.color.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _contributionBadge.color.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _contributionBadge.color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _contributionBadge.icon,
                    color: _contributionBadge.color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_contributionBadge.label} Badge',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: AppTheme.getMutedColor(context),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _contributionBadge.description,
              style: GoogleFonts.inter(fontSize: 13, color: subTextColor),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: _contributionBadge.color.withValues(
                  alpha: 0.12,
                ),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _contributionBadge.color,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$_uploadCount contributions',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _contributionBadge.color,
                  ),
                ),
                Text(
                  next == null
                      ? 'Top tier reached!'
                      : '$remaining more to next',
                  style: GoogleFonts.inter(fontSize: 12, color: subTextColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showBadgesBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetCtx) {
        final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
        final textColor = AppTheme.getTextColor(sheetCtx);
        final subTextColor = AppTheme.getTextColor(sheetCtx, isPrimary: false);
        return Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.75,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF14171A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withValues(alpha: 0.2),
                            AppTheme.primary.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        color: AppTheme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Badges',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Earn badges by sharing resources',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: subTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.upload_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_uploadCount',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: ContributionBadgeCatalog.tiers.length,
                  itemBuilder: (context, index) {
                    final badge = ContributionBadgeCatalog.tiers[index];
                    final isUnlocked = _uploadCount >= badge.minContributions;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: isUnlocked
                            ? LinearGradient(
                                colors: [
                                  badge.color.withValues(
                                    alpha: isDark ? 0.15 : 0.08,
                                  ),
                                  badge.color.withValues(
                                    alpha: isDark ? 0.05 : 0.02,
                                  ),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: !isUnlocked
                            ? (isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.grey.shade50)
                            : null,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isUnlocked
                              ? badge.color.withValues(alpha: 0.3)
                              : (isDark
                                    ? Colors.white12
                                    : Colors.grey.shade200),
                          width: isUnlocked ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: isUnlocked
                                  ? badge.color
                                  : (isDark
                                        ? Colors.white12
                                        : Colors.grey.shade200),
                              shape: BoxShape.circle,
                              boxShadow: isUnlocked
                                  ? [
                                      BoxShadow(
                                        color: badge.color.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              isUnlocked
                                  ? badge.icon
                                  : Icons.lock_outline_rounded,
                              color: isUnlocked
                                  ? Colors.white
                                  : (isDark ? Colors.white54 : Colors.black45),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        badge.label,
                                        style: GoogleFonts.inter(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: isUnlocked
                                              ? badge.color
                                              : subTextColor,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                    if (badge.isPremiumReward && !isUnlocked)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFFFD700),
                                              Color(0xFFFFA000),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0xFFFFD700,
                                              ).withValues(alpha: 0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.star_rounded,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'PREMIUM REWARD',
                                              style: GoogleFonts.inter(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  badge.description,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: subTextColor,
                                    height: 1.4,
                                  ),
                                ),
                                if (!isUnlocked) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white10
                                          : Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.lock_clock,
                                          size: 14,
                                          color: subTextColor.withValues(
                                            alpha: 0.7,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Requires ${badge.minContributions} uploads',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: subTextColor.withValues(
                                              alpha: 0.8,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUpgradeCard() {
    final freeVisibleTokens = visibleAiTokensFromRaw(
      _aiTokenBaseBudget > 0
          ? _aiTokenBaseBudget * _aiTokenBudgetMultiplier
          : _aiTokenBudget,
    );
    final premiumVisibleTokens =
        freeVisibleTokens * math.max(1, _aiTokenPremiumMultiplier);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFFBEB), Color(0xFFFFF1C2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF5C542)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFB45309),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upgrade Now',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Offline downloads, premium badge, and bigger AI limits.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildUpgradeTokenStat(
                    label: 'Free',
                    value: '$freeVisibleTokens AI tokens',
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: Colors.black.withValues(alpha: 0.08),
                ),
                Expanded(
                  child: _buildUpgradeTokenStat(
                    label: 'Premium',
                    value: '$premiumVisibleTokens AI tokens',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => PaywallDialog(
                  onSuccess: () {
                    _loadProfile(forceRefresh: true);
                    _loadStats();
                    if (mounted) {
                      setState(() => _refreshPremiumFuture());
                    }
                  },
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            ),
            child: const Text('See Plans'),
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeTokenStat({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF92400E),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return TextField(
      controller: _searchController,
      onChanged: (val) {
        setState(() {
          _searchQuery = val.toLowerCase();
        });
      },
      style: GoogleFonts.inter(color: AppTheme.getTextColor(context)),
      decoration: InputDecoration(
        hintText: 'Search contributions...',
        hintStyle: GoogleFonts.inter(color: AppTheme.getMutedColor(context)),
        prefixIcon: Icon(Icons.search, color: AppTheme.getMutedColor(context)),
        filled: true,
        fillColor: AppTheme.getCardColor(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
      ),
    );
  }

  Widget _buildOfflineToggle(Color textColor) {
    return Row(
      children: [
        Text(
          'Premium',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BookmarksScreen()),
            );
          },
          child: Row(
            children: [
              Text(
                'My Bookmarks', // Updated from Save Offline to Bookmarks shortcut as per user request for functional profile
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: AppTheme.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContributionsList() {
    return FutureBuilder<List<Resource>>(
      future: _contributionsFuture ??= _supabaseService.getUserResources(
        _userEmail,
        approvedOnly: false,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading contributions: ${snapshot.error}'),
          );
        }

        var resources = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          resources = resources
              .where((r) => r.title.toLowerCase().contains(_searchQuery))
              .toList();
        }

        if (resources.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No contributions yet. Start sharing knowledge!',
                style: GoogleFonts.inter(color: Colors.grey),
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: resources.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final resource = resources[index];
            return ResourceCard(
              resource: resource,
              userEmail: _userEmail,
              showStatusBadge: true,
              onDelete: () => _deleteContribution(resource),
              onVoteChanged: () {
                // Optionally refresh stats or local state if needed
                setState(() {});
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMyPostsLink(Color textColor) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final email = _userEmail;
          if (email.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please sign in to view your posts.'),
              ),
            );
            return;
          }

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MyPostsScreen(
                userEmail: email,
                collegeDomain: widget.collegeDomain,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(
          8,
        ), // Add some radius for better visual
        child: Semantics(
          button: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 4,
            ), // Ensure hit target size
            child: Row(
              children: [
                Icon(Icons.dynamic_feed_outlined, color: textColor, size: 24),
                const SizedBox(width: 12),
                Text(
                  'My Posts',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppTheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String getInitials(String name) {
    if (name.isEmpty) return 'U';
    return name
        .trim()
        .split(' ')
        .map((e) => e[0])
        .take(2)
        .join('')
        .toUpperCase();
  }
}
