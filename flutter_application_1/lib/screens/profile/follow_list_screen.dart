import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/backend_api_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/follow_button.dart';
import '../../config/theme.dart';
import 'user_profile_screen.dart';

class FollowListScreen extends StatefulWidget {
  final String initialTab; // 'followers' or 'following'
  final String userEmail;

  const FollowListScreen({
    super.key,
    this.initialTab = 'followers',
    required this.userEmail,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> with SingleTickerProviderStateMixin {
  final BackendApiService _api = BackendApiService();
  late TabController _tabController;
  
  List<dynamic> _followers = [];
  List<dynamic> _following = [];
  bool _isLoading = true;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == 'following' ? 1 : 0,
    );
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final results = await Future.wait([
        _api.getFollowers(),
        _api.getFollowing(),
      ]);
      
      final followersRes = results[0];
      final followingRes = results[1];
      
      if (mounted) {
        setState(() {
          _followers = followersRes['followers'] ?? [];
          _following = followingRes['following'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching follow lists: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load network. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(_auth.currentUserEmail == widget.userEmail ? 'My Network' : 'Network', 
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Followers'),
            Tab(text: 'Following'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_followers, 'No followers yet'),
                    _buildList(_following, 'Not following anyone yet'),
                  ],
                ),
    );
  }

  Widget _buildList(List<dynamic> users, String emptyMsg) {
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(emptyMsg, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final email = user['email'] as String?;
        if (email == null) return const SizedBox.shrink();
        final photoUrl = user['profile_photo_url'] ?? user['photo_url'];
        
        return ListTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfileScreen(
                  userEmail: email,
                  userName: user['display_name'],
                  userPhotoUrl: photoUrl,
                ),
              ),
            );
          },
          leading: UserAvatar(
            displayName: user['display_name'] ?? 'User',
            photoUrl: photoUrl,
          ),
          title: Text(user['display_name'] ?? 'Unknown'),
          subtitle: Text('@${user['username'] ?? 'user'}'),
          trailing: FollowButton(
            targetEmail: email,
            targetName: user['display_name'],
            onFollowChanged: _fetchData, // Refresh list on change
          ),
        );
      },
    );
  }
}

final SupabaseService _auth = SupabaseService();
