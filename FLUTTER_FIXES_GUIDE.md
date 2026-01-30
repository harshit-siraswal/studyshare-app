# Flutter App Fixes - Detailed Step-by-Step Guide

## Overview
This guide covers fixes for:
1. **App crashing on sign-in** (Google & Email)
2. **Comments not showing as threads** + Reply functionality
3. **Bottom navigation bar hiding content** on phones with bottom bar
4. **Settings buttons functionality** (Email notifications greyed out)
5. **Notice detail layout improvements** + Photo/Video support

---

## Issue 1: App Crashing on Sign-In

### Problem Analysis
The app crashes immediately after Google or email sign-in. This is likely due to:
- Missing error handling in `_saveUserToDatabase()` method
- Navigation happening before user data is saved
- Missing null checks after authentication

### Files to Modify
1. `lib/services/auth_service.dart`
2. `lib/screens/auth/login_screen.dart`
3. `lib/main.dart` (check auth state listener)

### Step-by-Step Fix

#### Step 1.1: Add Error Handling to Auth Service
**File:** `lib/services/auth_service.dart`

**Find the `_saveUserToDatabase` method** (around line 220-260). If it doesn't exist, add it:

```dart
/// Save user to Supabase database
Future<void> _saveUserToDatabase(firebase_auth.User user) async {
  try {
    final email = user.email;
    if (email == null) {
      debugPrint('User email is null, skipping database save');
      return;
    }

    // Check if user already exists
    final existingUser = await _supabase
        .from('users')
        .select('id')
        .eq('email', email)
        .maybeSingle();

    if (existingUser == null) {
      // Create new user record
      await _supabase.from('users').insert({
        'email': email,
        'display_name': user.displayName ?? email.split('@')[0],
        'photo_url': user.photoURL,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint('User saved to database: $email');
    } else {
      // Update existing user
      await _supabase
          .from('users')
          .update({
            'display_name': user.displayName ?? email.split('@')[0],
            'photo_url': user.photoURL,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('email', email);
      debugPrint('User updated in database: $email');
    }
  } catch (e) {
    debugPrint('Error saving user to database: $e');
    // Don't throw - allow sign-in to proceed even if DB save fails
  }
}
```

**Update `signInWithGoogle()` method** (around line 41-83):

```dart
Future<firebase_auth.UserCredential?> signInWithGoogle() async {
  try {
    if (kIsWeb) {
      final provider = firebase_auth.GoogleAuthProvider();
      provider.addScope('email');
      provider.addScope('profile');
      
      final userCredential = await _auth.signInWithPopup(provider);
      
      if (userCredential.user != null) {
        await _saveUserToDatabase(userCredential.user!);
      }
      
      return userCredential;
    }
    
    if (_googleSignIn == null) return null;
    
    final GoogleSignInAccount? googleUser = await _googleSignIn!.signIn();
    if (googleUser == null) return null;
    
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    
    final credential = firebase_auth.GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    
    final userCredential = await _auth.signInWithCredential(credential);
    
    if (userCredential.user != null) {
      // Save to database without blocking navigation
      _saveUserToDatabase(userCredential.user!).catchError((e) {
        debugPrint('Background save error: $e');
      });
    }
    
    return userCredential;
  } catch (e) {
    debugPrint('Error signing in with Google: $e');
    rethrow;
  }
}
```

**Update `signInWithEmail()` method** (around line 86-97):

```dart
Future<firebase_auth.UserCredential> signInWithEmail(String email, String password) async {
  try {
    final userCredential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    
    // Save/update user in database (non-blocking)
    if (userCredential.user != null) {
      _saveUserToDatabase(userCredential.user!).catchError((e) {
        debugPrint('Background save error: $e');
      });
    }
    
    return userCredential;
  } catch (e) {
    debugPrint('Error signing in with email: $e');
    rethrow;
  }
}
```

**Update `createAccountWithEmail()` method** (around line 100-123):

```dart
Future<firebase_auth.UserCredential> createAccountWithEmail({
  required String email,
  required String password,
  required String displayName,
}) async {
  try {
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    
    await userCredential.user?.updateDisplayName(displayName);
    await userCredential.user?.sendEmailVerification();
    
    if (userCredential.user != null) {
      // Save to database (non-blocking)
      _saveUserToDatabase(userCredential.user!).catchError((e) {
        debugPrint('Background save error: $e');
      });
    }
    
    return userCredential;
  } catch (e) {
    debugPrint('Error creating account: $e');
    rethrow;
  }
}
```

#### Step 1.2: Add Try-Catch in Login Screen
**File:** `lib/screens/auth/login_screen.dart`

**Update `_signInWithGoogle()` method** (around line 51-64):

```dart
Future<void> _signInWithGoogle() async {
  setState(() => _isLoading = true);
  try {
    final result = await _authService.signInWithGoogle();
    if (result == null) {
      if (mounted) {
        _showError('Google sign-in was cancelled');
      }
      return;
    }
    // Navigation handled by StreamBuilder in main.dart
    // Wait a moment for auth state to update
    await Future.delayed(const Duration(milliseconds: 500));
  } catch (e) {
    if (mounted) {
      _showError(_authService.getErrorMessage(e));
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
```

**Update `_submitForm()` method** (around line 66-89):

```dart
Future<void> _submitForm() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => _isLoading = true);
  try {
    if (_isLogin) {
      await _authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
      // Wait for auth state to update
      await Future.delayed(const Duration(milliseconds: 500));
    } else {
      await _authService.createAccountWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
      );
      if (mounted) {
        setState(() => _showEmailVerification = true);
      }
    }
  } catch (e) {
    if (mounted) {
      _showError(_authService.getErrorMessage(e));
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
```

#### Step 1.3: Verify Main.dart Auth Listener
**File:** `lib/main.dart`

**Check the StreamBuilder** that listens to `authStateChanges` (around line 155-224). Ensure it has proper error handling:

```dart
StreamBuilder<firebase_auth.User?>(
  stream: _authService.authStateChanges,
  builder: (context, snapshot) {
    // Show loading while checking auth state
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    // Handle errors
    if (snapshot.hasError) {
      return Scaffold(
        body: Center(
          child: Text('Error: ${snapshot.error}'),
        ),
      );
    }
    
    final user = snapshot.data;
    
    // If user is signed in, check ban status before navigating
    if (user != null) {
      // Check ban status asynchronously
      return FutureBuilder<Map<String, dynamic>?>(
        future: _authService.checkBanStatus(user.email ?? '', collegeId),
        builder: (context, banSnapshot) {
          if (banSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          
          final banStatus = banSnapshot.data ?? {'isBanned': false};
          
          if (banStatus['isBanned'] == true) {
            return _buildBanScreen(banStatus['reason'] ?? 'You have been banned.');
          }
          
          // User is signed in and not banned - show home screen
          return HomeScreen(...);
        },
      );
    }
    
    // User is not signed in - show login screen
    return LoginScreen(...);
  },
)
```

---

## Issue 2: Comments Not Showing as Threads + Reply Functionality

### Problem Analysis
- Comments are displayed flat (no parent-child relationship)
- No reply button on comments
- Database supports `parent_id` but UI doesn't use it

### Files to Modify
1. `lib/services/supabase_service.dart` - Update `getNoticeComments()` to fetch with parent relationships
2. `lib/screens/notices/notice_detail_screen.dart` - Add threaded display + reply functionality

### Step-by-Step Fix

#### Step 2.1: Update Comment Fetching to Support Threads
**File:** `lib/services/supabase_service.dart`

**Replace `getNoticeComments()` method** (around line 397-410):

```dart
/// Get comments for a notice with thread structure
Future<List<Map<String, dynamic>>> getNoticeComments(String noticeId) async {
  try {
    // Fetch all comments for this notice
    final response = await _client
        .from('notice_comments')
        .select('*')
        .eq('notice_id', noticeId)
        .order('created_at', ascending: true);
    
    final allComments = List<Map<String, dynamic>>.from(response);
    
    // Build thread structure
    final Map<String, List<Map<String, dynamic>>> commentMap = {};
    final List<Map<String, dynamic>> topLevelComments = [];
    
    // First pass: organize comments by parent_id
    for (var comment in allComments) {
      final parentId = comment['parent_id'] as String?;
      if (parentId == null) {
        // Top-level comment
        comment['replies'] = [];
        topLevelComments.add(comment);
      } else {
        // Reply comment
        if (!commentMap.containsKey(parentId)) {
          commentMap[parentId] = [];
        }
        commentMap[parentId]!.add(comment);
      }
    }
    
    // Second pass: attach replies to their parents
    void attachReplies(Map<String, dynamic> comment) {
      final commentId = comment['id'] as String;
      if (commentMap.containsKey(commentId)) {
        comment['replies'] = commentMap[commentId]!;
        // Recursively attach replies to replies
        for (var reply in comment['replies']) {
          attachReplies(reply);
        }
      }
    }
    
    for (var comment in topLevelComments) {
      attachReplies(comment);
    }
    
    return topLevelComments;
  } catch (e) {
    print('Error fetching notice comments: $e');
    return [];
  }
}
```

#### Step 2.2: Update Notice Detail Screen for Threaded Comments
**File:** `lib/screens/notices/notice_detail_screen.dart`

**Add state variable for replying** (around line 29-33):

```dart
List<Map<String, dynamic>> _comments = [];
bool _isLoading = true;
bool _isPosting = false;
bool _isSaved = false;
String? _replyingToCommentId; // Add this
String? _replyingToUserName;   // Add this
```

**Update `_postComment()` method** (around line 85-118):

```dart
Future<void> _postComment() async {
  final text = _commentController.text.trim();
  if (text.isEmpty) return;

  final email = _authService.userEmail;
  if (email == null) return;

  setState(() => _isPosting = true);

  try {
    await _supabaseService.addNoticeComment(
      noticeId: widget.notice['id'],
      content: text,
      userEmail: email,
      userName: _authService.displayName ?? email.split('@')[0],
      parentId: _replyingToCommentId, // Add parent_id if replying
    );

    _commentController.clear();
    setState(() {
      _replyingToCommentId = null;
      _replyingToUserName = null;
    });
    await _loadComments();
    
    // Scroll to bottom
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
  } finally {
    if (mounted) setState(() => _isPosting = false);
  }
}
```

**Replace `_buildCommentItem()` method** (around line 323-374):

```dart
Widget _buildCommentItem(Map<String, dynamic> c, bool isDark, Color textColor, Color secondaryColor, {int depth = 0}) {
  final replies = c['replies'] as List<Map<String, dynamic>>? ?? [];
  final hasReplies = replies.isNotEmpty;
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(left: depth * 24.0, bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard.withOpacity(0.5) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: depth > 0 ? Border(
              left: BorderSide(
                color: AppTheme.primary.withOpacity(0.3),
                width: 2,
              ),
            ) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primary.withOpacity(0.2),
                    child: Text(
                      (c['user_name'] ?? 'U')[0].toUpperCase(),
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              c['user_name'] ?? 'User',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTimeAgo(c['created_at']),
                              style: GoogleFonts.inter(fontSize: 12, color: secondaryColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          c['content'] ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Reply button
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _replyingToCommentId = c['id'] as String?;
                    _replyingToUserName = c['user_name'] as String?;
                  });
                  _commentController.text = '@${_replyingToUserName ?? 'User'} ';
                  // Focus on comment input
                  FocusScope.of(context).requestFocus(FocusNode());
                },
                icon: Icon(Icons.reply_rounded, size: 16, color: AppTheme.primary),
                label: Text(
                  'Reply',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
      // Recursively display replies
      if (hasReplies)
        ...replies.map((reply) => _buildCommentItem(
          reply,
          isDark,
          textColor,
          secondaryColor,
          depth: depth + 1,
        )),
    ],
  );
}
```

**Update the comments list rendering** (around line 268-269):

```dart
else
  ..._comments.map((c) => _buildCommentItem(c, isDark, textColor, secondaryColor)),
```

**Update comment input section** (around line 276-317) to show reply indicator:

```dart
// Comment Input
Container(
  padding: EdgeInsets.only(
    left: 16,
    right: 16,
    top: 12,
    bottom: MediaQuery.of(context).viewInsets.bottom + 12
  ),
  decoration: BoxDecoration(
    color: isDark ? AppTheme.darkSurface : Colors.white,
    border: Border(top: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
  ),
  child: Column(
    children: [
      // Reply indicator
      if (_replyingToCommentId != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.reply_rounded, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Replying to ${_replyingToUserName ?? 'User'}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: AppTheme.primary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _replyingToCommentId = null;
                    _replyingToUserName = null;
                  });
                  _commentController.clear();
                },
              ),
            ],
          ),
        ),
      Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkBackground : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _commentController,
                style: GoogleFonts.inter(color: textColor),
                decoration: InputDecoration(
                  hintText: _replyingToCommentId != null 
                    ? 'Write a reply...' 
                    : 'Add a comment...',
                  hintStyle: GoogleFonts.inter(color: secondaryColor),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isPosting ? null : _postComment,
            icon: _isPosting 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.send_rounded, color: AppTheme.primary),
          ),
        ],
      ),
    ],
  ),
),
```

---

## Issue 3: Bottom Navigation Bar Hiding Content

### Problem Analysis
On phones with bottom navigation gestures (Android), content gets hidden behind the system navigation bar. Need to add proper padding using `SafeArea` or `MediaQuery.paddingOf(context)`.

### Files to Modify
1. `lib/screens/home/home_screen.dart` - Wrap content in SafeArea
2. All screen files that use bottom navigation

### Step-by-Step Fix

#### Step 3.1: Fix Home Screen Layout
**File:** `lib/screens/home/home_screen.dart`

**Update `build()` method** (around line 128-140):

```dart
@override
Widget build(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  
  return Scaffold(
    backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
    body: SafeArea(
      bottom: false, // Don't add bottom padding here, handle it in content
      child: Stack(
        children: [
          // Main content with padding for bottom nav
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 60, // 60 = bottom nav height
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _getScreen(_currentIndex),
            ),
          ),
          
          // Study Timer Sidebar Button
          Positioned(
            left: 0,
            top: MediaQuery.of(context).size.height * 0.35,
            child: GestureDetector(
              onTap: _toggleTimer,
              child: AnimatedContainer(
                // ... existing timer button code ...
              ),
            ),
          ),
        ],
      ),
    ),
    floatingActionButton: _buildFAB(isDark),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    bottomNavigationBar: _buildBottomNav(isDark),
  );
}
```

**Update `_buildBottomNav()` method** (around line 252-296):

```dart
Widget _buildBottomNav(bool isDark) {
  return Container(
    decoration: BoxDecoration(
      color: isDark ? AppTheme.darkSurface : Colors.white,
      border: Border(
        top: BorderSide(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 0.5,
        ),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Container(
        height: 60,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom > 0 
            ? MediaQuery.of(context).padding.bottom 
            : 0,
        ),
        child: Row(
          children: [
            // Left side - 2 tabs
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
                  _buildNavItem(1, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chats'),
                ],
              ),
            ),
            // Center gap for FAB
            const SizedBox(width: 64),
            // Right side - 2 tabs
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(2, Icons.campaign_outlined, Icons.campaign_rounded, 'Notices'),
                  _buildNavItem(3, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

#### Step 3.2: Fix Individual Screen Content Padding
**Files to update:**
- `lib/screens/study/study_screen.dart`
- `lib/screens/chatroom/chatroom_screen.dart`
- `lib/screens/notices/notices_screen.dart`
- `lib/screens/profile/profile_screen.dart`

**Pattern for each screen:**

Wrap the main content in a `Padding` widget that accounts for bottom navigation:

```dart
@override
Widget build(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  
  return Scaffold(
    backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
    body: SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 60, // Bottom nav height
        ),
        child: // Your existing content here
      ),
    ),
  );
}
```

**Example for Study Screen** (`lib/screens/study/study_screen.dart`):

```dart
@override
Widget build(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  
  return Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 60,
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(),
            
            // Tab Bar
            _buildTabBar(isDark),
            
            // Rest of your content...
          ],
        ),
      ),
    ),
  );
}
```

---

## Issue 4: Settings Buttons Functionality

### Problem Analysis
- Settings buttons need to be functional
- Email notifications should be greyed out (not implemented yet)
- Other settings (Push Notifications, Private Profile, Hide Activity) need state management

### Files to Modify
1. `lib/screens/profile/profile_screen.dart` - Update `_SettingsScreen` class

### Step-by-Step Fix

#### Step 4.1: Add State Management for Settings
**File:** `lib/screens/profile/profile_screen.dart`

**Convert `_SettingsScreen` to StatefulWidget** (around line 920):

```dart
// Settings Screen
class _SettingsScreen extends StatefulWidget {
  final ThemeProvider themeProvider;

  const _SettingsScreen({required this.themeProvider});

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  // Settings state
  bool _pushNotificationsEnabled = true;
  bool _emailNotificationsEnabled = false; // Not implemented
  bool _privateProfileEnabled = false;
  bool _hideActivityEnabled = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        title: Text(
          'Settings ⚙️',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: isDark ? Colors.white : const Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('Appearance', [
            _buildSettingTile(
              icon: Icons.dark_mode_outlined,
              title: 'Dark Mode',
              trailing: Switch(
                value: widget.themeProvider.isDarkMode,
                onChanged: (_) => widget.themeProvider.toggleTheme(),
                activeColor: AppTheme.primary,
              ),
              isDark: isDark,
            ),
          ], isDark),
          const SizedBox(height: 16),
          
          _buildSection('Notifications', [
            _buildSettingTile(
              icon: Icons.notifications_outlined,
              title: 'Push Notifications',
              trailing: Switch(
                value: _pushNotificationsEnabled,
                onChanged: (value) {
                  setState(() => _pushNotificationsEnabled = value);
                  // TODO: Implement push notification toggle
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value ? 'Push notifications enabled' : 'Push notifications disabled'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                activeColor: AppTheme.primary,
              ),
              isDark: isDark,
            ),
            _buildSettingTile(
              icon: Icons.email_outlined,
              title: 'Email Notifications',
              subtitle: 'Coming soon',
              trailing: Switch(
                value: _emailNotificationsEnabled,
                onChanged: null, // Disabled - greyed out
                activeColor: AppTheme.primary,
              ),
              isDark: isDark,
              enabled: false, // Add enabled parameter
            ),
          ], isDark),
          const SizedBox(height: 16),
          
          _buildSection('Privacy', [
            _buildSettingTile(
              icon: Icons.lock_outline,
              title: 'Private Profile',
              trailing: Switch(
                value: _privateProfileEnabled,
                onChanged: (value) {
                  setState(() => _privateProfileEnabled = value);
                  // TODO: Implement private profile toggle
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value ? 'Profile set to private' : 'Profile set to public'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                activeColor: AppTheme.primary,
              ),
              isDark: isDark,
            ),
            _buildSettingTile(
              icon: Icons.visibility_off_outlined,
              title: 'Hide Activity',
              trailing: Switch(
                value: _hideActivityEnabled,
                onChanged: (value) {
                  setState(() => _hideActivityEnabled = value);
                  // TODO: Implement hide activity toggle
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value ? 'Activity hidden' : 'Activity visible'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                activeColor: AppTheme.primary,
              ),
              isDark: isDark,
            ),
          ], isDark),
          const SizedBox(height: 16),
          
          _buildSection('About', [
            _buildSettingTile(
              icon: Icons.info_outline,
              title: 'App Version',
              subtitle: '1.0.0',
              isDark: isDark,
            ),
            _buildSettingTile(
              icon: Icons.description_outlined,
              title: 'Terms of Service',
              isDark: isDark,
              onTap: () {
                // TODO: Navigate to Terms of Service screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Terms of Service - Coming soon')),
                );
              },
            ),
            _buildSettingTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              isDark: isDark,
              onTap: () {
                // TODO: Navigate to Privacy Policy screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Privacy Policy - Coming soon')),
                );
              },
            ),
          ], isDark),
        ],
      ),
    );
  }
}
```

**Update `_buildSettingTile()` method** to support `enabled` parameter (around line 1019):

```dart
Widget _buildSettingTile({
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? trailing,
  required bool isDark,
  VoidCallback? onTap,
  bool enabled = true, // Add this parameter
}) {
  final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
  final mutedColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
  
  return ListTile(
    leading: Icon(
      icon,
      color: enabled 
        ? (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)
        : mutedColor.withOpacity(0.5),
    ),
    title: Text(
      title,
      style: GoogleFonts.inter(
        color: enabled ? textColor : mutedColor.withOpacity(0.5),
        fontWeight: FontWeight.w500,
      ),
    ),
    subtitle: subtitle != null
      ? Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: mutedColor,
          ),
        )
      : null,
    trailing: trailing != null
      ? Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: trailing,
        )
      : null,
    onTap: enabled ? onTap : null,
    enabled: enabled,
  );
}
```

---

## Issue 5: Notice Detail Layout Improvements + Photo/Video Support

### Problem Analysis
- Notice detail screen needs better layout/design
- Support for photos and videos in notices
- Media should be displayed in a gallery/carousel format

### Files to Modify
1. `lib/screens/notices/notice_detail_screen.dart` - Improve layout and add media support
2. `lib/services/supabase_service.dart` - Add methods to fetch notice media (if needed)
3. Database schema - Ensure `notices` table has `media_urls` or `attachments` column

### Step-by-Step Fix

#### Step 5.1: Add Media Display to Notice Detail Screen
**File:** `lib/screens/notices/notice_detail_screen.dart`

**Add dependencies** (if not already present):
- `photo_view` package for image viewing
- `video_player` package for video playback

**Update `pubspec.yaml`**:
```yaml
dependencies:
  photo_view: ^0.14.0
  video_player: ^2.8.0
  cached_network_image: ^3.3.0
```

**Add state variables** (around line 29-33):

```dart
List<Map<String, dynamic>> _comments = [];
bool _isLoading = true;
bool _isPosting = false;
bool _isSaved = false;
String? _replyingToCommentId;
String? _replyingToUserName;
List<String> _mediaUrls = []; // Add this
```

**Update `initState()`** (around line 35-39):

```dart
@override
void initState() {
  super.initState();
  _loadComments();
  _checkSavedStatus();
  _loadMediaUrls(); // Add this
}

Future<void> _loadMediaUrls() async {
  // Extract media URLs from notice data
  // Assuming notice has 'media_urls' field as JSON array or comma-separated string
  final mediaData = widget.notice['media_urls'];
  if (mediaData != null) {
    if (mediaData is List) {
      setState(() => _mediaUrls = List<String>.from(mediaData));
    } else if (mediaData is String) {
      setState(() => _mediaUrls = mediaData.split(',').where((url) => url.trim().isNotEmpty).toList());
    }
  }
}
```

**Update `build()` method** - Improve layout (around line 170-239):

```dart
body: Column(
  children: [
    Expanded(
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          // Notice Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: widget.account.color,
                  child: Text(
                    widget.account.avatarLetter,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.account.name,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.verified_rounded, size: 16, color: AppTheme.primary),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTimeAgo(createdAt),
                        style: GoogleFonts.inter(fontSize: 12, color: secondaryColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // Title
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: textColor,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          
          // Media Gallery (Photos/Videos)
          if (_mediaUrls.isNotEmpty) ...[
            _buildMediaGallery(isDark),
            const SizedBox(height: 16),
          ],
          
          // Content
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              content,
              style: GoogleFonts.inter(
                fontSize: 16,
                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                height: 1.6,
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          Divider(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          const SizedBox(height: 16),
          
          // Comments Section Header
          Row(
            children: [
              Text(
                'Comments',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_comments.length}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Comments List
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No comments yet. Be the first to reply!',
                  style: GoogleFonts.inter(color: secondaryColor),
                ),
              ),
            )
          else
            ..._comments.map((c) => _buildCommentItem(c, isDark, textColor, secondaryColor)),
            
          const SizedBox(height: 20),
        ],
      ),
    ),
    
    // Comment Input (keep existing code)
    // ...
  ],
),
```

**Add `_buildMediaGallery()` method** (add after `_buildCommentItem()`):

```dart
Widget _buildMediaGallery(bool isDark) {
  return Container(
    height: 300,
    child: PageView.builder(
      itemCount: _mediaUrls.length,
      itemBuilder: (context, index) {
        final url = _mediaUrls[index];
        final isVideo = url.toLowerCase().endsWith('.mp4') || 
                       url.toLowerCase().endsWith('.mov') ||
                       url.toLowerCase().contains('video');
        
        return GestureDetector(
          onTap: () {
            // Open full-screen media viewer
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => _MediaViewerScreen(
                  mediaUrls: _mediaUrls,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? AppTheme.darkCard : Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: isVideo
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Video thumbnail placeholder
                      Container(
                        color: Colors.black,
                        child: Center(
                          child: Icon(
                            Icons.play_circle_filled,
                            size: 64,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ),
                      // Video indicator
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_arrow, size: 16, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                'Video',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.broken_image, size: 48),
                      );
                    },
                  ),
            ),
          ),
        );
      },
    ),
  );
}
```

**Add Media Viewer Screen** (add at end of file):

```dart
// Full-screen media viewer
class _MediaViewerScreen extends StatelessWidget {
  final List<String> mediaUrls;
  final int initialIndex;

  const _MediaViewerScreen({
    required this.mediaUrls,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: mediaUrls.length,
        itemBuilder: (context, index) {
          final url = mediaUrls[index];
          final isVideo = url.toLowerCase().endsWith('.mp4') || 
                         url.toLowerCase().endsWith('.mov') ||
                         url.toLowerCase().contains('video');
          
          return isVideo
            ? Center(
                child: Text(
                  'Video playback\n(Implement video_player widget)',
                  style: GoogleFonts.inter(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              )
            : PhotoView(
                imageProvider: NetworkImage(url),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              );
        },
      ),
    );
  }
}
```

**Add import statements** (at top of file):

```dart
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
```

---

## Summary Checklist

### Issue 1: Sign-In Crash
- [ ] Add `_saveUserToDatabase()` method with error handling
- [ ] Update `signInWithGoogle()` to handle errors
- [ ] Update `signInWithEmail()` to handle errors
- [ ] Update `createAccountWithEmail()` to handle errors
- [ ] Add try-catch in `login_screen.dart`
- [ ] Verify `main.dart` auth listener has error handling

### Issue 2: Comment Threads
- [ ] Update `getNoticeComments()` to build thread structure
- [ ] Add `_replyingToCommentId` and `_replyingToUserName` state
- [ ] Update `_postComment()` to accept `parentId`
- [ ] Rewrite `_buildCommentItem()` with recursive replies
- [ ] Add reply button to each comment
- [ ] Add reply indicator in comment input
- [ ] Test nested replies (replies to replies)

### Issue 3: Bottom Navigation Padding
- [ ] Update `home_screen.dart` with SafeArea and padding
- [ ] Update `study_screen.dart` with bottom padding
- [ ] Update `chatroom_screen.dart` with bottom padding
- [ ] Update `notices_screen.dart` with bottom padding
- [ ] Update `profile_screen.dart` with bottom padding
- [ ] Test on device with bottom navigation gestures

### Issue 4: Settings Functionality
- [ ] Convert `_SettingsScreen` to StatefulWidget
- [ ] Add state variables for each setting
- [ ] Update `_buildSettingTile()` with `enabled` parameter
- [ ] Grey out Email Notifications switch
- [ ] Add functionality to Push Notifications toggle
- [ ] Add functionality to Privacy settings
- [ ] Add placeholder actions for Terms/Privacy

### Issue 5: Notice Layout + Media
- [ ] Add `photo_view` and `cached_network_image` packages
- [ ] Add `_mediaUrls` state variable
- [ ] Add `_loadMediaUrls()` method
- [ ] Improve notice header card design
- [ ] Add `_buildMediaGallery()` method
- [ ] Add `_MediaViewerScreen` for full-screen viewing
- [ ] Update notice content card styling
- [ ] Test with sample images/videos

---

## Testing Steps

1. **Sign-In Testing:**
   - Test Google sign-in
   - Test email sign-in
   - Test email sign-up
   - Verify no crashes occur
   - Check user data is saved to database

2. **Comment Threading:**
   - Post a top-level comment
   - Reply to a comment
   - Reply to a reply (nested)
   - Verify thread structure displays correctly
   - Test reply cancellation

3. **Bottom Navigation:**
   - Test on phone with bottom navigation gestures
   - Verify content is not hidden
   - Test scrolling on all screens
   - Verify bottom nav is always visible

4. **Settings:**
   - Toggle each setting
   - Verify Email Notifications is greyed out
   - Check snackbar messages appear
   - Test navigation to Terms/Privacy (placeholders)

5. **Notice Media:**
   - Create notice with images
   - Create notice with videos
   - Test media gallery scrolling
   - Test full-screen viewer
   - Verify layout improvements

---

## Notes

- All changes should maintain existing functionality
- Test thoroughly on both Android and iOS if possible
- Consider adding loading states for media
- Database schema may need updates for media URLs storage
- Consider implementing video player for video playback
- Settings state should be persisted (use SharedPreferences or Supabase)
