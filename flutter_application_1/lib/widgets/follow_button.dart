import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../services/supabase_service.dart';
import '../config/theme.dart';

enum FollowStatus { notFollowing, pending, following, self }

class FollowButton extends StatefulWidget {
  final String targetEmail;
  final String? targetName;
  final VoidCallback? onFollowChanged;

  const FollowButton({
    super.key,
    required this.targetEmail,
    this.targetName,
    this.onFollowChanged,
  });

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  final BackendApiService _api = BackendApiService();
  final SupabaseService _supabase = SupabaseService();
  
  bool _isLoading = true;
  FollowStatus _status = FollowStatus.notFollowing;
  String? _requestId;
  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void didUpdateWidget(FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetEmail != widget.targetEmail) {
      _checkStatus();
    }
  }
  Future<void> _checkStatus() async {
    if (!mounted) return;
    
    // Set loading initially
    setState(() => _isLoading = true);
    
    final currentUserEmail = _supabase.currentUserEmail;
    if (currentUserEmail == widget.targetEmail) {
      if (mounted) {
        setState(() {
        _status = FollowStatus.self;
        _isLoading = false;
      });
      }
      return;
    }
    try {
      final res = await _api.checkFollowStatus(widget.targetEmail);
      if (mounted) {
        setState(() {
          final statusStr = res['status'] as String?;
          _status = _parseStatus(statusStr);
          _requestId = res['requestId']?.toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking follow status: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  FollowStatus _parseStatus(String? status) {
    switch (status) {
      case 'following': return FollowStatus.following;
      case 'pending': return FollowStatus.pending;
      case 'self': return FollowStatus.self;
      default: return FollowStatus.notFollowing;
    }
  }

  Future<void> _handlePress() async {
    setState(() => _isLoading = true);
    try {
      if (_status == FollowStatus.following) {
        // Unfollow
        await _api.unfollowUser(widget.targetEmail);
        if (mounted) setState(() => _status = FollowStatus.notFollowing);
        
      } else if (_status == FollowStatus.pending) {
        // Cancel request
        if (_requestId != null) {
          await _api.cancelFollowRequest(_requestId!);
          if (mounted) setState(() => _status = FollowStatus.notFollowing);
        } else {
          // If we don't have a requestId, we can't cancel. 
          // Maybe refresh status?
          await _checkStatus();
        }
      } else {
        // Not following -> Send Request
        final currentEmail = _supabase.currentUserEmail;
        if (currentEmail == null) {
          throw Exception('User not logged in');
        }
        await _supabase.sendFollowRequest(currentEmail, widget.targetEmail);
        if (mounted) setState(() => _status = FollowStatus.pending);
      }
      
      if (widget.onFollowChanged != null) {
        widget.onFollowChanged!();
      }
      
    } catch (e) {
      debugPrint('Error updating follow status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == FollowStatus.self) return const SizedBox.shrink();

    String text;
    Color bgColor;
    Color textColor;
    IconData? icon;

    switch (_status) {
      case FollowStatus.following:
        text = 'Following';
        bgColor = Colors.transparent;
        textColor = AppTheme.primary;
        icon = Icons.check;
        break;
      case FollowStatus.pending:
        text = 'Requested';
        bgColor = Colors.transparent;
        textColor = Colors.grey;
        icon = Icons.access_time;
        break;
      default:
        text = 'Follow';
        bgColor = AppTheme.primary;
        textColor = Colors.white;
        icon = Icons.person_add;
    }

    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _handlePress,
        style: OutlinedButton.styleFrom(
          backgroundColor: bgColor,
          side: BorderSide(
              color: _status == FollowStatus.notFollowing 
                  ? Colors.transparent 
                  : Colors.grey.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: _isLoading 
            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...[
                  Icon(icon, size: 14, color: textColor),
                  const SizedBox(width: 4),
                ],
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
