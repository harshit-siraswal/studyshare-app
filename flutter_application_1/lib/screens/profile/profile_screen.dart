import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../services/backend_api_service.dart';
import '../../providers/theme_provider.dart';
import '../../models/resource.dart';
import '../../widgets/resource_card.dart';
import '../study/bookmarks_screen.dart';
import 'following_screen.dart';
import 'edit_profile_screen.dart';
import '../../widgets/paywall_dialog.dart';
import '../../services/subscription_service.dart';
import 'settings_screen.dart';
import 'explore_students_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String collegeId;
  final String collegeName;
  final String collegeDomain;
  final VoidCallback onLogout;
  final VoidCallback onChangeCollege;
  final ThemeProvider themeProvider;

  const ProfileScreen({
    super.key,
    required this.collegeId,
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
  final BackendApiService _api = BackendApiService();
  final SubscriptionService _subscriptionService = SubscriptionService();

  bool _isLoggingOut = false;
  bool _profileLoading = true;
  String? _profilePhotoUrl;
  String? _profileDisplayName;
  String? _profileBio;
  
  // Real stats
  int _uploadCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  bool _statsLoading = true;
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _api.getProfile();
      final profile = (data['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      if (!mounted) return;
      setState(() {
        _profileDisplayName = profile['display_name']?.toString();
        _profilePhotoUrl = profile['profile_photo_url']?.toString();
        _profileBio = profile['bio']?.toString();
        _profileLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _loadStats() async {
    if (_authService.userEmail == null) return;
    try {
      final stats = await _supabaseService.getUserStats(_authService.userEmail!);
      final followingCount = await _supabaseService.getFollowingCount(_authService.userEmail!);
      final followersCount = await _supabaseService.getFollowersCount(_authService.userEmail!);
      if (mounted) {
        setState(() {
          _uploadCount = stats['uploads'] ?? 0;
          _followersCount = followersCount;
          _followingCount = followingCount;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  String get _userEmail => _authService.userEmail ?? 'guest@example.com';
  String get _displayName => _profileDisplayName ?? _authService.displayName ?? 'User';
  String? get _photoUrl => _profilePhotoUrl ?? _authService.photoUrl;
  
  

  Future<void> _handleLogout() async {
    setState(() => _isLoggingOut = true);
    
    try {
      await _authService.signOut();
      if (mounted) {
        widget.onLogout();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoggingOut = false);
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
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
               if (mounted) _loadProfile();
            },
          ),
        ],
      ),
      body: _profileLoading 
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () async {
              await _loadProfile();
              await _loadStats();
              setState(() {});
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
                   
                   // Explore Students Button
                   Padding(
                     padding: const EdgeInsets.symmetric(horizontal: 16),
                     child: OutlinedButton.icon(
                       onPressed: () {
                         Navigator.push(
                           context,
                           MaterialPageRoute(
                             builder: (_) => ExploreStudentsScreen(collegeId: widget.collegeId),
                           ),
                         );
                       },
                       icon: Icon(Icons.people_outline, color: textColor),
                       label: Text('Find Classmates', style: GoogleFonts.inter(color: textColor)),
                       style: OutlinedButton.styleFrom(
                         padding: const EdgeInsets.symmetric(vertical: 12),
                         side: BorderSide(color: subTextColor.withValues(alpha: 0.3)),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                         minimumSize: const Size(double.infinity, 48),
                       ),
                     ),
                   ),
                   const SizedBox(height: 24),
                   // Premium Badge / Status
                   FutureBuilder<bool>(
                     future: SubscriptionService().isPremium(),
                     builder: (context, snapshot) {
                       final isPremium = snapshot.data ?? false;
                       return isPremium 
                          ? _buildPremiumBadge() 
                          : _buildUpgradeCard();
                     },
                   ),
                   const SizedBox(height: 24),
                   // Search & Filter
                   _buildSearchBar(isDark),
                   const SizedBox(height: 16),
                   // Offline Toggle (Only if Premium, or disabled if Free)
                   _buildOfflineToggle(textColor),
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
      future: _subscriptionService.isPremium(),
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
                            color: const Color(0xFFFFD700).withValues(alpha: 0.5),
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
                            colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFFD700)],
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
                          color: isPremium ? Colors.white : textColor.withValues(alpha: 0.1), 
                          width: isPremium ? 2 : 1
                        ),
                        color: textColor.withValues(alpha: 0.05),
                      ),
                      child: ClipOval(
                        child: _photoUrl != null
                          ? Image.network(
                              _photoUrl!,
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
                          ),
                        ),
                      );
                      if (updated != null && mounted) {
                        await _loadProfile();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                      ),
                      child: const Icon(Icons.edit, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
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
                   const Icon(Icons.verified, color: Color(0xFFFFD700), size: 20),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '@${_profileDisplayName?.replaceAll(" ", "").toLowerCase() ?? "user"}',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: subTextColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _authService.userEmail ?? '', // Show Email
              style: GoogleFonts.inter(
                fontSize: 13,
                color: subTextColor,
              ),
            ),
            const SizedBox(height: 4),
             Text(
              widget.collegeName,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: subTextColor,
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
        );
      }
    );
  }

  Widget _buildStatsRow(Color textColor, Color subTextColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatItem('Contributions', _uploadCount.toString(), textColor, subTextColor, () {
          // Already on profile showing contributions, maybe scroll down?
        }),
        _buildStatItem('Followers', _followersCount.toString(), textColor, subTextColor, () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FollowingScreen(userEmail: _userEmail),
            ),
          );
          if (mounted) _loadStats();
        }),
        _buildStatItem('Following', _followingCount.toString(), textColor, subTextColor, () async {
           await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FollowingScreen(userEmail: _userEmail),
            ),
          );
          if (mounted) _loadStats();
        }),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color textColor, Color subTextColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            value,
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
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.black54,
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
                     // Refresh to show premium badge/ring if successful
                     setState(() {});
                   },
                 ),
               );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
      decoration: InputDecoration(
        hintText: 'Search contributions...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
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
              MaterialPageRoute(
                builder: (_) => BookmarksScreen(
                  userEmail: _userEmail,
                  collegeId: widget.collegeId,
                ),
              ),
            );
          },
          child: Row(
            children: [
              Text(
                'My Bookmarks', // Updated from Save Offline to Bookmarks shortcut as per user request for functional profile
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppTheme.primary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContributionsList() {
    return FutureBuilder<List<Resource>>(
      future: _supabaseService.getUserResources(_userEmail),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Error loading contributions: ${snapshot.error}'));
        }
        
        var resources = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          resources = resources.where((r) => r.title.toLowerCase().contains(_searchQuery)).toList();
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
          separatorBuilder: (_, __) => const SizedBox(height: 12),
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

  String getInitials(String name) {
    if (name.isEmpty) return 'U';
    return name.trim().split(' ').map((e) => e[0]).take(2).join('').toUpperCase();
  }
}
