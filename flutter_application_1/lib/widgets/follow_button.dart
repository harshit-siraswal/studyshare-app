import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../services/supabase_service.dart';
import '../config/theme.dart';

enum FollowStatus { notFollowing, pending, following, self }

class FollowButton extends StatefulWidget {
  final String targetEmail;
  final String? targetName;
  final VoidCallback? onFollowChanged;
  final ValueChanged<FollowStatus>? onStatusChanged;

  const FollowButton({
    super.key,
    required this.targetEmail,
    this.targetName,
    this.onFollowChanged,
    this.onStatusChanged,
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

  Future<void> _checkStatus({bool showLoading = true}) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() => _isLoading = true);
    }

    final currentUserEmail = _supabase.currentUserEmail?.trim().toLowerCase();
    final targetEmail = widget.targetEmail.trim().toLowerCase();
    if (currentUserEmail == targetEmail) {
      if (mounted) {
        setState(() {
          _status = FollowStatus.self;
          _requestId = null;
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
          _requestId =
              res['requestId']?.toString() ?? res['request_id']?.toString();
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
      case 'following':
      case 'accepted':
        return FollowStatus.following;
      case 'pending':
      case 'requested':
        return FollowStatus.pending;
      case 'self':
        return FollowStatus.self;
      default:
        return FollowStatus.notFollowing;
    }
  }

  String _errorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'Something went wrong. Please try again.';
    }
    return message;
  }

  Future<void> _handlePress() async {
    setState(() => _isLoading = true);
    try {
      if (_status == FollowStatus.following) {
        await _api.unfollowUser(widget.targetEmail, context: context);
        if (mounted) {
          setState(() {
            _status = FollowStatus.notFollowing;
            _requestId = null;
          });
        }
      } else if (_status == FollowStatus.pending) {
        if (_requestId != null && _requestId!.trim().isNotEmpty) {
          await _api.cancelFollowRequest(
            int.parse(_requestId!),
            context: context,
          );
          if (mounted) {
            setState(() {
              _status = FollowStatus.notFollowing;
              _requestId = null;
            });
          }
        } else {
          await _checkStatus();
          return;
        }
      } else {
        final currentEmail = _supabase.currentUserEmail?.trim();
        if (currentEmail == null || currentEmail.isEmpty) {
          throw Exception('User not logged in');
        }
        final result = await _api.sendFollowRequest(
          widget.targetEmail,
          context: context,
        );
        if (mounted) {
          setState(() {
            _status = FollowStatus.pending;
            _requestId = result['requestId']?.toString() ??
                result['request_id']?.toString() ??
                _requestId;
          });
        }
      }

      widget.onFollowChanged?.call();
      widget.onStatusChanged?.call(_status);
    } catch (e) {
      debugPrint('Error updating follow status: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(e))));
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

    final targetLabel = widget.targetName ?? widget.targetEmail;

    return Tooltip(
      message: '$text $targetLabel',
      child: SizedBox(
        height: 32,
        child: OutlinedButton(
          onPressed: _isLoading ? null : _handlePress,
          style: OutlinedButton.styleFrom(
            backgroundColor: bgColor,
            side: BorderSide(
              color: _status == FollowStatus.notFollowing
                  ? Colors.transparent
                  : Colors.grey.withValues(alpha: 0.5),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: textColor),
                    const SizedBox(width: 4),
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
      ),
    );
  }
}
