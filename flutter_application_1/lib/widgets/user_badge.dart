import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    try {
      final userResponse = await Supabase.instance.client
          .from('users')
          .select('role, subscription_end_date')
          .eq('email', widget.email)
          .maybeSingle();
      
      if (mounted && userResponse != null) {
        final role = userResponse['role'];
        if (role == 'COLLEGE_USER' || role == 'MODERATOR' || role == 'ADMIN') {
          _isVerified = true;
          // verified users inherently get premium features but we prefer showing 'verified' only.
        } else {
          // Check explicit premium status
          if (userResponse['subscription_end_date'] != null) {
            final premiumUntil = DateTime.parse(userResponse['subscription_end_date'].toString());
            if (premiumUntil.toUtc().isAfter(DateTime.now().toUtc())) {
              _isPremium = true;
            }
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

    // Do NOT write premium if user already implies verified sticker
    if (_isVerified) {
      return Icon(Icons.verified, color: AppTheme.primary, size: widget.size + 2);
    }

    if (_isPremium) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'PRO',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: widget.size - 4 > 8 ? widget.size - 4 : 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
