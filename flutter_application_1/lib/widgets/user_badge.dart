import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../services/supabase_service.dart';

class UserBadge extends StatefulWidget {
  final String email;
  final double size;
  const UserBadge({super.key, required this.email, this.size = 14});

  @override
  State<UserBadge> createState() => _UserBadgeState();
}

class _UserBadgeState extends State<UserBadge> {
  static bool? _usersTableHasRoleColumn;
  final SupabaseService _supabaseService = SupabaseService();

  bool _isLoading = true;
  bool _isVerified = false;
  bool _isPremium = false;

  bool _isMissingRoleColumnError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('column') &&
        message.contains('users.role') &&
        message.contains('does not exist');
  }

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

    try {
      Map<String, dynamic>? userResponse;
      final currentEmail = (_supabaseService.currentUserEmail ?? '')
          .trim()
          .toLowerCase();
      if (!_supabaseService.hasConfiguredSupabaseAnonKey) {
        if (currentEmail == email) {
          final profile = await _supabaseService.getCurrentUserProfile(
            maxAttempts: 1,
          );
          if (profile.isNotEmpty) {
            userResponse = <String, dynamic>{...profile, 'email': email};
          }
        }
      } else if (_usersTableHasRoleColumn == false) {
        userResponse = await Supabase.instance.client
            .from('users_safe')
            .select('subscription_tier, subscription_end_date')
            .eq('email', email)
            .maybeSingle();
      } else {
        try {
          userResponse = await Supabase.instance.client
              .from('users_safe')
              .select('role, subscription_tier, subscription_end_date')
              .eq('email', email)
              .maybeSingle();
          _usersTableHasRoleColumn = true;
        } catch (e) {
          if (_isMissingRoleColumnError(e)) {
            _usersTableHasRoleColumn = false;
            userResponse = await Supabase.instance.client
                .from('users_safe')
                .select('subscription_tier, subscription_end_date')
                .eq('email', email)
                .maybeSingle();
          } else {
            rethrow;
          }
        }
      }

      if (mounted && userResponse != null) {
        final role = userResponse['role']?.toString().trim().toUpperCase();
        if (role == 'COLLEGE_USER' ||
            role == 'MODERATOR' ||
            role == 'ADMIN' ||
            role == 'TEACHER') {
          _isVerified = true;
        }

        final tier = userResponse['subscription_tier']
            ?.toString()
            .toLowerCase();
        if ((tier == 'pro' || tier == 'max') &&
            userResponse['subscription_end_date'] != null) {
          final premiumUntil = DateTime.parse(
            userResponse['subscription_end_date'].toString(),
          );
          if (premiumUntil.toUtc().isAfter(DateTime.now().toUtc())) {
            _isPremium = true;
          }
        }
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
