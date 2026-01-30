import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../services/backend_api_service.dart';

/// Screen to view another user's profile.
/// Opened when you tap on a user from comments, posts, or explore users.
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
  Map<String, dynamic>? _userProfile;
  int _uploadCount = 0;
  int _roomsJoined = 0;
  bool _isFollowing = false;
  bool _followLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      // Try to get user stats
      final stats = await _supabaseService.getUserStats(widget.userEmail);
      
      // Check if current user follows this user (placeholder - implement if needed)
      // final following = await _supabaseService.isFollowing(currentUserEmail, widget.userEmail);
      
      if (mounted) {
        setState(() {
          _uploadCount = stats['uploads'] ?? 0;
          _roomsJoined = stats['rooms'] ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String get _displayName => widget.userName ?? widget.userEmail.split('@')[0];
  String get _avatarLetter => _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U';
  String get _collegeDomain {
    final parts = widget.userEmail.split('@');
    return parts.length > 1 ? parts[1] : '';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final mutedColor = AppTheme.textMuted;

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // Cover Image / Header
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: isDark ? const Color(0xFF1E293B) : AppTheme.primary,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Gradient background with pattern
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primary,
                          AppTheme.primary.withOpacity(0.7),
                          const Color(0xFF6366F1),
                        ],
                      ),
                    ),
                  ),
                  // Pattern overlay
                  Opacity(
                    opacity: 0.1,
                    child: Image.network(
                      'https://images.unsplash.com/photo-1557682250-33bd709cbe85?w=800',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -50),
              child: Column(
                children: [
                  // Profile Picture
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bgColor,
                    ),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppTheme.primary, const Color(0xFF6366F1)],
                        ),
                        border: Border.all(color: bgColor, width: 3),
                        image: widget.userPhotoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(widget.userPhotoUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: widget.userPhotoUrl == null
                          ? Center(
                              child: Text(
                                _avatarLetter,
                                style: GoogleFonts.inter(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Name
                  Text(
                    _displayName,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // College Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_rounded, size: 14, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          _collegeDomain,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Stats Row - Circular indicators like Ladder app
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCircularStat(
                          value: _uploadCount.toString(),
                          label: 'Uploads',
                          color: const Color(0xFF10B981),
                          isDark: isDark,
                        ),
                        _buildCircularStat(
                          value: _roomsJoined.toString(),
                          label: 'Rooms',
                          color: const Color(0xFF6366F1),
                          isDark: isDark,
                        ),
                        _buildCircularStat(
                          value: '0',
                          label: 'Followers',
                          color: const Color(0xFFF59E0B),
                          isDark: isDark,
                        ),
                        _buildCircularStat(
                          value: '0',
                          label: 'Following',
                          color: const Color(0xFFEC4899),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Action Buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        // Follow Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _followLoading ? null : _toggleFollow,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isFollowing 
                                  ? (isDark ? const Color(0xFF334155) : Colors.grey.shade200)
                                  : AppTheme.primary,
                              foregroundColor: _isFollowing 
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            icon: Icon(
                              _isFollowing ? Icons.person_remove_rounded : Icons.person_add_rounded,
                              size: 20,
                            ),
                            label: Text(
                              _isFollowing ? 'Unfollow' : 'Follow',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Message Button
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Direct messaging coming soon!')),
                              );
                            },
                            icon: Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Tabs Section
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        if (!isDark)
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                          ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _buildTab(Icons.grid_view_rounded, 'Posts', true, isDark),
                        _buildTab(Icons.bookmark_outline_rounded, 'Saved', false, isDark),
                        _buildTab(Icons.emoji_events_outlined, 'Badges', false, isDark),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Content Area (Placeholder)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 48,
                          color: mutedColor.withOpacity(0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No public posts yet',
                          style: GoogleFonts.inter(
                            color: mutedColor,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularStat({
    required String value,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
          ),
          child: Center(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildTab(IconData icon, String label, bool isSelected, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: isSelected
              ? Border(
                  bottom: BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primary : AppTheme.textMuted,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppTheme.primary : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    setState(() => _followLoading = true);
    
    // Simulate follow action
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (mounted) {
      setState(() {
        _isFollowing = !_isFollowing;
        _followLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFollowing ? 'Following ${widget.userName ?? 'user'}' : 'Unfollowed'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
