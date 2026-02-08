import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/follow_button.dart';
import '../../config/theme.dart';
import '../profile/user_profile_screen.dart';

class ExploreScreen extends StatefulWidget {
  final String collegeDomain;

  const ExploreScreen({super.key, required this.collegeDomain});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final SupabaseService _supabase = SupabaseService();
  final AuthService _auth = AuthService();
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _errorMessage;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      final users = await _supabase.getUsersByCollege(
        widget.collegeDomain, 
        searchQuery: _searchQuery
      );
      
      // Filter out current user
      final currentEmail = _auth.userEmail;
      final filtered = users.where((u) => u['email'] != currentEmail).toList();
      
      if (mounted) {
        setState(() {
          _users = filtered;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Error fetching users: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load classmates. Pull to retry.';
        });
      }
    }
  }  
  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    setState(() => _searchQuery = query);
    
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text('Find Classmates', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text('No classmates found', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                                const SizedBox(height: 16),
                                Text(_errorMessage!, style: const TextStyle(color: Colors.grey)),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _fetchUsers,
                                  child: const Text('Retry'),
                                )
                              ],
                            ),
                          )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            color: isDark ? Colors.grey[900] : Colors.white,                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      if (user['email'] != null) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => UserProfileScreen(
                                              userEmail: user['email'],
                                              userName: user['display_name'],
                                              userPhotoUrl: user['profile_photo_url'],
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: UserAvatar(
                                      displayName: user['display_name'] ?? 'User',
                                      photoUrl: user['profile_photo_url'],
                                      radius: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user['display_name'] ?? 'Unknown User',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (user['bio'] != null)
                                          Text(
                                            user['bio'],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7) ?? Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                        Text(
                                          '@${user['username'] ?? 'user'}',
                                          style: TextStyle(
                                            color: AppTheme.primary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (user['email'] != null)
                                    FollowButton(
                                      targetEmail: user['email'],
                                      targetName: user['display_name'],
                                    ),
                                ],
                              ),                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
