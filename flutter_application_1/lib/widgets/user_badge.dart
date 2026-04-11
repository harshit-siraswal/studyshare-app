import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/backend_api_service.dart';
import '../services/supabase_service.dart';

class _BadgeSnapshot {
  const _BadgeSnapshot({
    required this.isVerified,
    required this.isPremium,
    required this.cachedAt,
  });

  final bool isVerified;
  final bool isPremium;
  final DateTime cachedAt;
}

class UserBadge extends StatefulWidget {
  final String email;
  final double size;
  const UserBadge({super.key, required this.email, this.size = 14});

  @override
  State<UserBadge> createState() => _UserBadgeState();
}

class _UserBadgeState extends State<UserBadge> {
  static const Duration _badgeCacheTtl = Duration(minutes: 10);
  static final Map<String, _BadgeSnapshot> _badgeCache =
      <String, _BadgeSnapshot>{};

  final SupabaseService _supabaseService = SupabaseService();
  final BackendApiService _backendApiService = BackendApiService();

  bool _isLoading = true;
  bool _isVerified = false;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  @override
  void didUpdateWidget(UserBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email != widget.email) {
      setState(() {
        _isLoading = true;
        _isVerified = false;
        _isPremium = false;
      });
      _loadBadges();
    }
  }

  Future<void> _loadBadges() async {
    final email = widget.email.trim().toLowerCase();
    if (email.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isVerified = false;
          _isPremium = false;
        });
      }
      return;
    }

    final cached = _badgeCache[email];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) <= _badgeCacheTtl) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isVerified = cached.isVerified;
          _isPremium = cached.isPremium;
        });
      }
      return;
    }

    try {
      Map<String, dynamic>? userResponse;
      final currentEmail = (_supabaseService.currentUserEmail ?? '')
          .trim()
          .toLowerCase();
      if (currentEmail == email) {
        final profile = await _supabaseService.getCurrentUserProfile(
          maxAttempts: 1,
        );
        if (profile.isNotEmpty) {
          userResponse = <String, dynamic>{...profile, 'email': email};
        }
      } else {
        try {
          final payload = await _backendApiService.getPublicProfile(email: email);
          final profilePayload = payload['profile'];
          if (profilePayload is Map) {
            userResponse = Map<String, dynamic>.from(profilePayload);
          } else {
            userResponse = Map<String, dynamic>.from(payload);
          }
        } catch (e) {
          debugPrint('UserBadge backend public profile lookup failed: $e');
        }

        userResponse ??= await _supabaseService.getUserInfo(email);
      }

      var verified = false;
      var premium = false;

      if (mounted && userResponse != null) {
        final role = userResponse['role']?.toString().trim().toUpperCase();
        if (role == 'COLLEGE_USER' ||
            role == 'MODERATOR' ||
            role == 'ADMIN' ||
            role == 'TEACHER') {
          verified = true;
        }

        final tier = userResponse['subscription_tier']
            ?.toString()
            .toLowerCase();
        final premiumUntilRaw =
            userResponse['subscription_end_date'] ?? userResponse['premium_until'];
        if ((tier == 'pro' || tier == 'max') &&
            premiumUntilRaw != null) {
          final premiumUntil = DateTime.parse(
            premiumUntilRaw.toString(),
          );
          if (premiumUntil.toUtc().isAfter(DateTime.now().toUtc())) {
            premium = true;
          }
        }

        _badgeCache[email] = _BadgeSnapshot(
          isVerified: verified,
          isPremium: premium,
          cachedAt: DateTime.now(),
        );

        setState(() {
          _isVerified = verified;
          _isPremium = premium;
        });
      }
    } catch (e) {
      debugPrint('Error loading badge: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();

    if (_isPremium) {
      return Icon(
        Icons.verified_rounded,
        color: AppTheme.premium,
        size: widget.size + 2,
      );
    }

    if (_isVerified) {
      return Icon(
        Icons.verified_rounded,
        color: AppTheme.primary,
        size: widget.size + 2,
      );
    }

    return const SizedBox.shrink();
  }
}
