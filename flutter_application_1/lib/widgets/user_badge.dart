import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';

class UserBadge extends StatefulWidget {
  final String email;
  final double size;
  const UserBadge({super.key, required this.email, this.size = 14});

  @override
  State<UserBadge> createState() => _UserBadgeState();
}

class _UserBadgeState extends State<UserBadge> {
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

    try {
        final userResponse = await Supabase.instance.client
          .from('users')
          .select('role, subscription_tier, subscription_end_date')
          .eq('email', email)
          .maybeSingle();

      if (mounted && userResponse != null) {
        final role = userResponse['role'];
        if (role == 'COLLEGE_USER' || role == 'MODERATOR' || role == 'ADMIN') {
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
