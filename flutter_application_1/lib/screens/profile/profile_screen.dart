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
import 'bookmarks_screen.dart';
import 'following_screen.dart';
import 'edit_profile_screen.dart';
import '../../widgets/paywall_dialog.dart';
import '../../services/subscription_service.dart';
import 'settings_screen.dart';
import 'explore_students_screen.dart';
import 'saved_posts_screen.dart';
import '../../models/user.dart';
import '../../widgets/animated_counter.dart';

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
  String? _profileAdminKey;
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
  Future<bool>? _isPremiumFuture;
  Future<List<Resource>>? _contributionsFuture;

  // Real stats
  int _uploadCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  ContributionBadge _contributionBadge = ContributionBadgeCatalog.resolve(0);

  final TextEditingController _searchController = TextEditingController();
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
    _contributionsFuture = _supabaseService.getUserResources(email);
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
      if (!mounted) return;
      setState(() {
        _profileDisplayName = profile['display_name']?.toString();
        _profilePhotoUrl = profile['profile_photo_url']?.toString();
        _profileBio = profile['bio']?.toString();
        _profileSemester = profile['semester']?.toString();
        _profileBranch = profile['branch']?.toString();
        _profileSubject = profile['subject']?.toString();
        _profileAdminKey = profile['admin_key']?.toString();
        final budgetFromApi = _toSafeInt(profile['ai_token_budget']);
        final usedFromApi = _toSafeInt(profile['ai_token_used']);
        final remainingFromApi = _toSafeInt(profile['ai_token_remaining']);
        final baseBudgetFromApi = _toSafeInt(profile['ai_token_base_budget']);
        final premiumMultiplierFromApi = math.max(
          1,
          _toSafeInt(profile['ai_token_premium_multiplier']),
        );
        final currentMultiplier = math.max(
          1,
          _toSafeInt(profile['ai_token_budget_multiplier']),
        );
        final tier = profile['subscription_tier']?.toString().toLowerCase();
        final subscriptionEnd = DateTime.tryParse(
          profile['subscription_end_date']?.toString() ?? '',
        );
        final isPremiumActive =
            (tier == 'pro' || tier == 'max') &&
            subscriptionEnd != null &&
            subscriptionEnd.toUtc().isAfter(DateTime.now().toUtc());
        final safeBaseBudget = baseBudgetFromApi > 0
            ? baseBudgetFromApi
            : (budgetFromApi > 0 && currentMultiplier > 1
                  ? (budgetFromApi / currentMultiplier).round()
                  : (budgetFromApi > 0 ? budgetFromApi : 40160));
        final resolvedMultiplier = currentMultiplier > 1
            ? currentMultiplier
            : (isPremiumActive ? premiumMultiplierFromApi : 1);
        final derivedBudget = math.max(1, safeBaseBudget * resolvedMultiplier);
        final resolvedBudget = budgetFromApi > 0
            ? math.max(budgetFromApi, derivedBudget)
            : derivedBudget;
        final resolvedUsed = usedFromApi.clamp(0, resolvedBudget);
        final derivedRemaining = (resolvedBudget - resolvedUsed).clamp(
          0,
          resolvedBudget,
        );
        final resolvedRemaining =
            (remainingFromApi <= 0 ||
                remainingFromApi > resolvedBudget ||
                resolvedBudget > budgetFromApi)
            ? derivedRemaining
            : remainingFromApi.clamp(0, resolvedBudget);

        _aiTokenBudget = resolvedBudget;
        _aiTokenUsed = resolvedUsed;
        _aiTokenRemaining = resolvedRemaining;
        _aiTokenBaseBudget = safeBaseBudget > 0 ? safeBaseBudget : 40160;
        _aiTokenBudgetMultiplier = resolvedMultiplier;
        _aiTokenPremiumMultiplier = premiumMultiplierFromApi;
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
        final roleRaw = profile['role']?.toString().trim().toUpperCase() ?? '';
        final hasAdminKey =
            _profileAdminKey != null && _profileAdminKey!.trim().isNotEmpty;
        if (roleRaw == AppRoles.admin ||
            roleRaw == AppRoles.teacher ||
            roleRaw == AppRoles.moderator ||
            roleRaw == AppRoles.collegeUser ||
            roleRaw == AppRoles.readOnly) {
          if (hasAdminKey &&
              roleRaw != AppRoles.admin &&
              roleRaw != AppRoles.teacher) {
            _profileRole = AppRoles.teacher;
          } else {
            _profileRole = roleRaw;
          }
        } else if (hasAdminKey) {
          _profileRole = AppRoles.teacher;
        } else if (roleRaw == 'STUDENT') {
          _profileRole = AppRoles.collegeUser;
        } else {
          _profileRole = AppRoles.readOnly;
        }
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

  String _formatTokenCompact3(int value) {
    final abs = value.abs();
    if (abs < 1000) return value.toString();

    double scaled = value.toDouble();
    String suffix = '';
    if (abs >= 1000000000) {
      scaled = value / 1000000000;
      suffix = 'B';
    } else if (abs >= 1000000) {
      scaled = value / 1000000;
      suffix = 'M';
    } else {
      scaled = value / 1000;
      suffix = 'K';
    }

    final absScaled = scaled.abs();
    final decimals = absScaled >= 100 ? 0 : (absScaled >= 10 ? 1 : 2);
    final compact = scaled
        .toStringAsFixed(decimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    return '$compact$suffix';
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

  String _formatTokenDetailed(int value) {
    return '${_formatTokenCompact3(value)} (${_formatTokenWithCommas(value)})';
  }

  String _formatCreditCompact(int tokenValue) {
    if (tokenValue <= 0) return '0';
    final credits = tokenValue / _tokensPerCredit;
    return math.max(1, credits.round()).toString();
  }

  String _formatCreditDetailed(int tokenValue) {
    return '${_formatCreditCompact(tokenValue)} credits '
        '(${_formatTokenWithCommas(tokenValue)} tokens)';
  }

  String _formatCreditRange(int minTokens, int maxTokens) {
    return '${_formatCreditCompact(minTokens)} - '
        '${_formatCreditCompact(maxTokens)} credits';
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

  @override
  Widget build(BuildContext context) {
    // Determine if we are in dark mode based on system/theme provider
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.getTextColor(context);
    final subTextColor = AppTheme.getTextColor(context, isPrimary: false);

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
                  builder: (_) => ExploreStudentsScreen(
                    collegeDomain: widget.collegeDomain,
                    userEmail: _userEmail,
                  ),
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildProfileHeader(textColor, subTextColor),
                    const SizedBox(height: 24),
                    _buildStatsRow(textColor, subTextColor),
                    const SizedBox(height: 24),
                    _buildAiTokenUsageCard(textColor, subTextColor, isDark),
                    const SizedBox(height: 24),
                    _buildContributionBadgeCard(
                      textColor,
                      subTextColor,
                      isDark,
                    ),
                    const SizedBox(height: 24),
                    // Premium Badge / Status
                    FutureBuilder<bool>(
                      future: _isPremiumFuture ??= _subscriptionService
                          .isPremium(),
                      builder: (context, snapshot) {
                        final isPremium = snapshot.data ?? false;
                        final isVerified =
                            _authService.currentUser?.emailVerified ?? false;
                        return isPremium && isVerified
                            ? _buildPremiumBadge()
                            : !isPremium
                            ? _buildUpgradeCard()
                            : const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(height: 24),
                    // Search & Filter
                    _buildSearchBar(isDark),
                    const SizedBox(height: 16),
                    // Offline Toggle (Only if Premium, or disabled if Free)
                    _buildOfflineToggle(textColor),
                    const SizedBox(height: 16),

                    // Saved Posts Link
                    _buildSavedPostsLink(textColor),
                    const SizedBox(height: 16),

                    // Contributions Header
                    Align(
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
                    const SizedBox(height: 40),
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
                            initialAdminKey: _profileAdminKey,
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
                                _profileBranch,
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
      onTap: () => _showAiTokenConsumptionDetailsSheet(
        textColor: textColor,
        subTextColor: subTextColor,
        isDark: isDark,
      ),
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

  String _formatCycleDate(DateTime? value) {
    if (value == null) return 'N/A';
    final local = value.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  Widget _buildTokenDetailRow(
    String label,
    String value,
    Color labelColor,
    Color valueColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAiTokenConsumptionDetailsSheet({
    required Color textColor,
    required Color subTextColor,
    required bool isDark,
  }) async {
    final budget = _aiTokenBudget > 0 ? _aiTokenBudget : 40160;
    final used = _aiTokenUsed.clamp(0, budget);
    final remaining = _aiTokenRemaining.clamp(0, budget);
    final cycleLabel =
        '${_aiTokenCycleDays > 0 ? _aiTokenCycleDays : 30} day cycle';
    final usagePercent = budget > 0
        ? ((used / budget) * 100).toStringAsFixed(1)
        : '0.0';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.query_stats_rounded,
                        color: AppTheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI Credits & Token Usage',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTokenDetailRow(
                    'Total monthly credits',
                    _formatCreditDetailed(budget),
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Used in current cycle',
                    '${_formatCreditDetailed(used)} ($usagePercent%)',
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Remaining credits',
                    _formatCreditDetailed(remaining),
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Token to credit ratio',
                    '1 credit = ${_formatTokenWithCommas(_tokensPerCredit)} tokens',
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Base budget',
                    _formatTokenDetailed(_aiTokenBaseBudget),
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Current multiplier',
                    '${_aiTokenBudgetMultiplier}x',
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Premium multiplier',
                    '${_aiTokenPremiumMultiplier}x',
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Cycle',
                    cycleLabel,
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Cycle started',
                    _formatCycleDate(_aiTokenCycleStartedAt),
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Cycle ends',
                    _formatCycleDate(_aiTokenCycleEndsAt),
                    subTextColor,
                    textColor,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Estimated cost per task:',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildTokenDetailRow(
                    'AI Chat reply',
                    '${_formatCreditRange(300, 1200)} '
                        '(~${_formatTokenCompact3(300)}-${_formatTokenCompact3(1200)} tokens)',
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Generate summary',
                    '${_formatCreditRange(1400, 3200)} '
                        '(~${_formatTokenCompact3(1400)}-${_formatTokenCompact3(3200)} tokens)',
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Generate flashcards',
                    '${_formatCreditRange(1800, 4200)} '
                        '(~${_formatTokenCompact3(1800)}-${_formatTokenCompact3(4200)} tokens)',
                    subTextColor,
                    textColor,
                  ),
                  _buildTokenDetailRow(
                    'Generate quiz',
                    '${_formatCreditRange(2200, 5200)} '
                        '(~${_formatTokenCompact3(2200)}-${_formatTokenCompact3(5200)} tokens)',
                    subTextColor,
                    textColor,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'How consumption is calculated:',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Billable usage = input tokens + weighted output tokens. '
                    'Task numbers are estimates and vary with note size and '
                    'response length. Your quota resets when the cycle ends.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: subTextColor,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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

  Widget _buildPremiumBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
      ),
      child: Text(
        'PREMIUM MEMBER',
        style: GoogleFonts.inter(
          color: const Color(0xFFD4AF37),
          fontWeight: FontWeight.bold,
          fontSize: 14,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD54F)),
      ),
      child: Column(
        children: [
          Text(
            'Unlock Pro Features!',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Analytics & Offline Downloads',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.black54),
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
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text('Upgrade Now'),
          ),
        ],
      ),
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
              userEmail: _authService.userEmail!,
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

  Widget _buildSavedPostsLink(Color textColor) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SavedPostsScreen(userEmail: _userEmail),
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
                Icon(Icons.bookmark_border_rounded, color: textColor, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Saved Posts',
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
