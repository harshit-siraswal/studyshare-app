import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/college.dart';
import '../models/resource.dart';
import 'backend_api_service.dart';
import 'subscription_service.dart';
import '../models/department_account.dart';

class RoomLimitException implements Exception {
  final String message;
  RoomLimitException(this.message);
  @override
  String toString() => message;
}

enum FollowStatus { notFollowing, pending, following }

class SupabaseService {
  static const int kUnlimitedDuration = -1;
  static const int kDefaultExpiryDays = 7;

  SupabaseClient get _client => Supabase.instance.client;
  final BackendApiService _api = BackendApiService();

  /// A BuildContext is required to run reCAPTCHA (invisible WebView) before privileged writes.
  /// Set this once from a top-level screen (e.g. HomeScreen) via [attachContext].
  static BuildContext? _ctx;

  void attachContext(BuildContext context) {
    _ctx = context;
  }

  String? get currentUserEmail => _client.auth.currentUser?.email;

  Future<List<String>> _resolveUserIdentifiers(String email) async {
    try {
      final user = await _client
          .from('users')
          .select('id, firebase_uid')
          .eq('email', email)
          .maybeSingle();
      if (user == null) return [];

      final ids = <String>{};
      final id = user['id'];
      if (id != null) ids.add(id.toString());
      final firebaseUid = user['firebase_uid'];
      if (firebaseUid != null) ids.add(firebaseUid.toString());

      return ids.toList();
    } catch (e) {
      debugPrint('Error resolving user identifiers: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUsersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];

    try {
      // Run both queries in parallel to fetch users by id or firebase_uid
      final results = await Future.wait([
        _client
            .from('users')
            .select(
              'id, email, display_name, profile_photo_url, username, photo_url',
            )
            .inFilter('id', ids)
            .catchError((e) {
              debugPrint('Error fetching users by id: $e');
              return [];
            }),
        _client
            .from('users')
            .select(
              'id, email, display_name, profile_photo_url, username, photo_url',
            )
            .inFilter('firebase_uid', ids)
            .catchError((e) {
              debugPrint('Error fetching users by firebase uid: $e');
              return [];
            }),
      ]);

      // Merge results and deduplicate by user id
      final Map<String, Map<String, dynamic>> deduped = {};
      for (final result in results) {
        if (result is List) {
          for (final user in result) {
            final userId = user['id'];
            if (userId != null) {
              deduped[userId] = user;
            }
          }
        }
      }

      return deduped.values.toList();
    } catch (e) {
      debugPrint('Error fetching users by ids: $e');
      return [];
    }
  }

  // ============ COLLEGES ============

  /// Get all active colleges
  Future<List<College>> getColleges() async {
    try {
      final response = await _client
          .from('colleges')
          .select()
          .eq('is_active', true)
          .order('name');

      return (response as List).map((json) => College.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching colleges: $e');
      rethrow;
    }
  }

  /// Search colleges by name
  Future<List<College>> searchColleges(String query) async {
    try {
      final response = await _client
          .from('colleges')
          .select()
          .eq('is_active', true)
          .ilike('name', '%$query%')
          .order('name')
          .limit(10);

      return (response as List).map((json) => College.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error searching colleges: $e');
      rethrow;
    }
  }

  // ============ RESOURCES ============

  /// Get resources with filters
  Future<List<Resource>> getResources({
    required String collegeId,
    String? semester,
    String? branch,
    String? subject,
    String? type,
    String? searchQuery,
    String? sortBy,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      debugPrint(
        'SupabaseService.getResources: collegeId=$collegeId, semester=$semester, branch=$branch, type=$type',
      );

      var query = _client
          .from('resources')
          .select()
          .eq('college_id', collegeId)
          .eq('status', 'approved');

      if (semester != null && semester.isNotEmpty) {
        query = query.eq('semester', semester);
      }
      if (branch != null && branch.isNotEmpty) {
        query = query.eq('branch', branch);
      }
      if (subject != null && subject.isNotEmpty) {
        query = query.eq('subject', subject);
      }
      if (type != null && type.isNotEmpty) {
        query = query.eq('type', type);
      }
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.ilike('title', '%$searchQuery%');
      }

      final orderedQuery = sortBy == 'upvotes'
          ? query
                .order('upvotes', ascending: false)
                .order('created_at', ascending: false)
          : sortBy == 'teacher'
          ? query
                .order('uploaded_by_name', ascending: true)
                .order('created_at', ascending: false)
          : query.order('created_at', ascending: false);

      final response = await orderedQuery.range(offset, offset + limit - 1);

      debugPrint(
        'SupabaseService.getResources: returned ${(response as List).length} resources',
      );

      return (response as List).map((json) => Resource.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching resources: $e');
      rethrow;
    }
  }

  /// Get resources from users the current user follows
  Future<List<Resource>> getFollowingFeed({
    required String userEmail,
    required String collegeId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final identifiers = await _resolveUserIdentifiers(userEmail);
      List<String> followingIds = [];

      for (final id in identifiers) {
        final followsResponse = await _client
            .from('follows')
            .select('following_id')
            .eq('follower_id', id)
            .eq('status', 'accepted');

        final ids = (followsResponse as List)
            .map((r) => r['following_id'] as String?)
            .whereType<String>()
            .toList();

        if (ids.isNotEmpty) {
          followingIds = ids;
          break;
        }
      }

      if (followingIds.isNotEmpty) {
        final usersResponse = await _fetchUsersByIds(followingIds);
        final followingEmails = usersResponse
            .map((r) => r['email'] as String?)
            .whereType<String>()
            .toList();

        if (followingEmails.isNotEmpty) {
          final response = await _client
              .from('resources')
              .select()
              .eq('college_id', collegeId)
              .eq('status', 'approved')
              .filter('uploaded_by_email', 'in', followingEmails)
              .order('created_at', ascending: false)
              .range(offset, offset + limit - 1);

          return (response as List)
              .map((json) => Resource.fromJson(json))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching following feed (id): $e');
    }

    // Fallback: email-based follows
    try {
      final followsResponse = await _client
          .from('follows')
          .select('following_email')
          .eq('follower_email', userEmail);

      final followingEmails = (followsResponse as List)
          .map((r) => r['following_email'] as String?)
          .whereType<String>()
          .toList();

      if (followingEmails.isEmpty) return [];

      final response = await _client
          .from('resources')
          .select()
          .eq('college_id', collegeId)
          .eq('status', 'approved')
          .filter('uploaded_by_email', 'in', followingEmails)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List).map((json) => Resource.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching following feed (email): $e');
      return [];
    }
  }

  /// Get follow status
  Future<FollowStatus> getFollowStatus(
    String followerEmail,
    String followingEmail,
  ) async {
    if (followerEmail == followingEmail) return FollowStatus.notFollowing;

    try {
      // Use Backend API
      final res = await _api.checkFollowStatus(followingEmail);
      final status = res['status'] as String?;

      if (status == 'following') return FollowStatus.following;
      if (status == 'pending') return FollowStatus.pending;
      return FollowStatus.notFollowing;
    } catch (e) {
      debugPrint('Error getting follow status: $e');
      return FollowStatus.notFollowing;
    }
  }

  /// Send follow request
  Future<void> sendFollowRequest(
    String followerEmail,
    String targetEmail,
  ) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      await _api.sendFollowRequest(targetEmail, ctx);
    } catch (e) {
      debugPrint('Error sending follow request: $e');
      rethrow;
    }
  }

  /// Cancel follow request
  Future<void> cancelFollowRequest(
    String followerEmail,
    String followingEmail,
  ) async {
    try {
      if (followerEmail == followingEmail) return;

      final status = await _api.checkFollowStatus(followingEmail);
      final isPending = status['status'] == 'pending';
      final requestId = status['requestId']?.toString();

      if (!isPending || requestId == null || requestId.isEmpty) {
        throw Exception('No pending follow request to cancel');
      }

      await _api.cancelFollowRequest(requestId);
    } catch (e) {
      debugPrint('Error cancelling follow request: $e');
      rethrow;
    }
  }

  /// Accept follow request
  Future<void> acceptFollowRequest(int requestId) async {
    try {
      final ctx = _ctx;
      // Context is optional for some generic ops but good for captures if needed,
      // primarily _api handles context internally if passed.
      await _api.acceptFollowRequest(requestId, context: ctx);

      // Backend handles notifications and DB updates now.
    } catch (e) {
      debugPrint('Error accepting follow request: $e');
      rethrow;
    }
  }

  /// Reject follow request
  Future<void> rejectFollowRequest(int requestId) async {
    try {
      final ctx = _ctx;
      await _api.rejectFollowRequest(requestId, context: ctx);
    } catch (e) {
      debugPrint('Error rejecting follow request: $e');
      rethrow;
    }
  }

  // Leave a room
  Future<void> leaveRoom(String roomId, String userEmail) async {
    try {
      await _client.from('room_members').delete().match({
        'room_id': roomId,
        'user_email': userEmail,
      });
    } catch (e) {
      debugPrint('Error leaving room: $e');
      rethrow;
    }
  }

  /// Remove a member from a room (admin action).
  Future<void> removeRoomMember({
    required String roomId,
    required String userEmail,
  }) async {
    // Delegate to leaveRoom; RLS enforces admin-only removal of other users
    await leaveRoom(roomId, userEmail);
  }
  // Join a room (Via RPC to enforce limits)
  Future<void> joinRoom(String roomId) async {
    try {
      // Use RPC 'join_room' which enforces the 5-group limit.
      // The backend API currently misses this check.
      // Also, the RPC handles member count increment (after our fix).
      final response = await _client.rpc(
        'join_room',
        params: {'room_id_input': roomId},
      );

      if (response != null && response['success'] == false) {
        throw Exception(response['error']?.toString() ?? 'Failed to join room');
      }
    } catch (e) {
      debugPrint('Error joining room: $e');
      rethrow;
    }
  }

  // Delete a room (admin only)
  Future<void> deleteRoom(String roomId) async {
    try {
      final response = await _client.rpc(
        'delete_room',
        params: {'room_id_input': roomId},
      );

      if (response != null && response['success'] == false) {
        throw response['error'] ?? 'Unknown error';
      }
    } catch (e) {
      debugPrint('Error deleting room: $e');
      rethrow;
    }
  }

  // Get user's room limits (how many joined/created, max allowed)
  Future<Map<String, dynamic>> getRoomLimits() async {
    try {
      final response = await _client.rpc('get_user_room_limits');
      return response ??
          {
            'joined_count': 0,
            'created_count': 0,
            'max_joined': 5,
            'max_created': 3,
            'can_join': true,
            'can_create': true,
          };
    } catch (e) {
      debugPrint('Error getting room limits: $e');
      // Return defaults on error
      return {
        'joined_count': 0,
        'created_count': 0,
        'max_joined': 5,
        'max_created': 3,
        'can_join': true,
        'can_create': true,
      };
    }
  }

  Future<void> unfollowUser(String followingEmail) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      await _api.unfollowUser(followingEmail, context: ctx);
    } catch (e, st) {
      debugPrint('Error unfollowing user: $e\n$st');
      // Rethrow if needed or handle UI feedback appropriately (but this is a service method)
      // Usually rethrow so UI can show error
      rethrow;
    }
  }

  // Helpers
  Future<String?> getUserId(String email) async {
    try {
      final res = await _client
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      return res?['id']?.toString();
    } catch (e) {
      debugPrint('Error fetching user id: $e');
      return null;
    }
  }

  Future<String?> getUserEmail(String id) async {
    try {
      final res = await _client
          .from('users')
          .select('email')
          .eq('id', id)
          .maybeSingle();
      return res?['email']?.toString();
    } catch (e) {
      debugPrint('Error fetching user email: $e');
      return null;
    }
  }

  /// Get user info including profile_photo_url and display_name
  Future<Map<String, dynamic>?> getUserInfo(String email) async {
    try {
      final res = await _client
          .from('users')
          .select('id, email, display_name, profile_photo_url, username, bio')
          .eq('email', email)
          .maybeSingle();
      return res;
    } catch (e) {
      debugPrint('Error fetching user info: $e');
      return null;
    }
  }

  Future<void> _createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? actorId,
    int? followRequestId,
    bool isActionable = false,
  }) async {
    // Backend handles this
  }

  // ============ NOTIFICATIONS & REQUESTS ============

  /// Get recent notifications
  Future<List<Map<String, dynamic>>> getNotifications({int limit = 50}) async {
    try {
      final response = await _client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      return [];
    }
  }

  /// Mark notification as read
  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      debugPrint('Error marking notification read: $e');
    }
  }

  /// Get pending follow requests for current user
  Future<List<Map<String, dynamic>>> getPendingFollowRequests() async {
    try {
      // Use Backend API
      final requests = await _api.getPendingRequests();

      // Map flat backend structure to nested structure expected by UI
      return requests.map((r) {
        final photoUrl = r['requesterPhotoUrl'];
        return {
          'id':
              int.tryParse(r['id']?.toString() ?? '') ??
              0, // Ensure int ID for UI
          'created_at': r['createdAt'],
          'requester': {
            'display_name': r['requesterName'],
            'username': r['requesterUsername'],
            'profile_photo_url': photoUrl,
            'photo_url': photoUrl,
            'email': r['requesterEmail'],
          },
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching follow requests: $e');
      return [];
    }
  }

  // ============ USERS & CLASSMATES ============

  /// Get users from the same college domain
  Future<List<Map<String, dynamic>>> getCollegeStudents(
    String domain, {
    String? query,
    int limit = 50,
  }) async {
    // Alias for getUsersByCollege but matching the existing method name if any
    return getUsersByCollege(domain, searchQuery: query);
  }

  /// Get users from the same college domain (for Find Classmates)
  Future<List<Map<String, dynamic>>> getUsersByCollege(
    String domain, {
    String? searchQuery,
  }) async {
    try {
      // Sanitize domain for PostgREST filter
      // Sanitize wildcards and special chars but preserve dots for valid email domains
      final safeDomain = domain
          .replaceAll(RegExp(r'[%*,]'), '')
          .replaceAll('_', r'\_'); // Escape LIKE single-char wildcard
      if (safeDomain.isEmpty) return [];
      var dbQuery = _client
          .from('users')
          .select(
            'id, email, display_name, username, profile_photo_url, college, bio',
          )
          .ilike('email', '%@$safeDomain');

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final safeQuery = searchQuery.replaceAll(RegExp(r'[%*,.]'), '');
        dbQuery = dbQuery.or(
          'display_name.ilike.%$safeQuery%,username.ilike.%$safeQuery%',
        );
      }

      final response = await dbQuery.limit(50);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting users by college: $e');
      return [];
    }
  }

  // ============ SOCIAL LISTS ============

  Future<List<Map<String, dynamic>>> getFollowers(String userEmail) async {
    try {
      if (userEmail == currentUserEmail) {
        final res = await _api.getFollowers();
        return List<Map<String, dynamic>>.from(res['followers'] ?? []);
      }

      final identifiers = await _resolveUserIdentifiers(userEmail);
      if (identifiers.isEmpty) return [];

      List<String> followerIds = [];
      for (final id in identifiers) {
        final response = await _client
            .from('follows')
            .select('follower_id')
            .eq('following_id', id)
            .eq('status', 'accepted');

        final ids = (response as List)
            .map((r) => r['follower_id'] as String?)
            .whereType<String>()
            .toList();

        if (ids.isNotEmpty) {
          followerIds = ids;
          break;
        }
      }

      if (followerIds.isEmpty) return [];

      final usersResponse = await _fetchUsersByIds(followerIds);

      return usersResponse.map((u) {
        final photoUrl = u['profile_photo_url'] ?? u['photo_url'];
        return {
          'email': u['email'],
          'display_name': u['display_name'],
          'profile_photo_url': photoUrl,
          'photo_url': photoUrl,
          'username': u['username'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error getting followers: $e');
    }

    // Fallback: email-based follows (older schema)
    try {
      List<String> followerEmails = [];

      try {
        final response = await _client
            .from('follows')
            .select('follower_email')
            .eq('following_email', userEmail)
            .eq('status', 'accepted');

        followerEmails = (response as List)
            .map((r) => r['follower_email'] as String?)
            .whereType<String>()
            .toList();
      } catch (e) {
        final response = await _client
            .from('follows')
            .select('follower_email')
            .eq('following_email', userEmail);

        followerEmails = (response as List)
            .map((r) => r['follower_email'] as String?)
            .whereType<String>()
            .toList();
      }

      if (followerEmails.isEmpty) return [];

      final usersResponse = await _client
          .from('users')
          .select('email, display_name, profile_photo_url, username, photo_url')
          .inFilter('email', followerEmails);

      return (usersResponse as List).map((u) {
        final photoUrl = u['profile_photo_url'] ?? u['photo_url'];
        return {
          'email': u['email'],
          'display_name': u['display_name'],
          'profile_photo_url': photoUrl,
          'photo_url': photoUrl,
          'username': u['username'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error getting followers (email fallback): $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFollowing(String userEmail) async {
    try {
      if (userEmail == currentUserEmail) {
        final res = await _api.getFollowing();
        return List<Map<String, dynamic>>.from(res['following'] ?? []);
      }

      final identifiers = await _resolveUserIdentifiers(userEmail);
      if (identifiers.isEmpty) return [];

      List<String> followingIds = [];
      for (final id in identifiers) {
        final response = await _client
            .from('follows')
            .select('following_id')
            .eq('follower_id', id)
            .eq('status', 'accepted');

        final ids = (response as List)
            .map((r) => r['following_id'] as String?)
            .whereType<String>()
            .toList();

        if (ids.isNotEmpty) {
          followingIds = ids;
          break;
        }
      }

      if (followingIds.isEmpty) return [];

      final usersResponse = await _fetchUsersByIds(followingIds);

      return usersResponse.map((u) {
        final photoUrl = u['profile_photo_url'] ?? u['photo_url'];
        return {
          'email': u['email'],
          'display_name': u['display_name'],
          'profile_photo_url': photoUrl,
          'photo_url': photoUrl,
          'username': u['username'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error getting following: $e');
    }

    // Fallback: email-based follows (older schema)
    try {
      List<String> followingEmails = [];

      try {
        final response = await _client
            .from('follows')
            .select('following_email')
            .eq('follower_email', userEmail)
            .eq('status', 'accepted');

        followingEmails = (response as List)
            .map((r) => r['following_email'] as String?)
            .whereType<String>()
            .toList();
      } catch (e) {
        final response = await _client
            .from('follows')
            .select('following_email')
            .eq('follower_email', userEmail);

        followingEmails = (response as List)
            .map((r) => r['following_email'] as String?)
            .whereType<String>()
            .toList();
      }

      if (followingEmails.isEmpty) return [];

      final usersResponse = await _client
          .from('users')
          .select('email, display_name, profile_photo_url, username, photo_url')
          .inFilter('email', followingEmails);

      return (usersResponse as List).map((u) {
        final photoUrl = u['profile_photo_url'] ?? u['photo_url'];
        return {
          'email': u['email'],
          'display_name': u['display_name'],
          'profile_photo_url': photoUrl,
          'photo_url': photoUrl,
          'username': u['username'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error getting following (email fallback): $e');
      return [];
    }
  }

  // ============ SAVED POSTS ============

  // ============ BOOKMARKS ============

  Future<List<Map<String, dynamic>>> getBookmarks() async {
    try {
      final res = await _api.getBookmarks();
      return List<Map<String, dynamic>>.from(res['bookmarks'] ?? []);
    } catch (e) {
      debugPrint('Error getting bookmarks: $e');
      return [];
    }
  }

  Future<void> addBookmark(String itemId, String type) async {
    final ctx = _ctx;
    if (ctx == null) throw Exception('Security context not initialized');
    await _api.addBookmark(itemId: itemId, type: type, context: ctx);
  }

  Future<void> removeBookmark(String itemId) async {
    final ctx = _ctx;
    if (ctx == null) throw Exception('Security context not initialized');
    await _api.removeBookmarkByItem(itemId: itemId, context: ctx);
  }

  /// Check if following a user (Legacy check mostly, but useful)
  Future<bool> isFollowing(String followerEmail, String followingEmail) async {
    try {
      final response = await _client.from('follows').select().match({
        'follower_email': followerEmail,
        'following_email': followingEmail,
      }).maybeSingle();
      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Get complete user stats
  Future<Map<String, dynamic>> getUserStats(String userEmail) async {
    try {
      final followers = await getFollowersCount(userEmail);
      final following = await getFollowingCount(userEmail);

      final contributions = await _client
          .from('resources')
          .count(CountOption.exact)
          .eq('uploaded_by_email', userEmail)
          .eq('status', 'approved'); // Only count approved resources?

      return {
        'followers': followers,
        'following': following,
        'contributions': contributions,
        'uploads': contributions, // Backward-compatible alias used by UI
      };
    } catch (e) {
      debugPrint('Error fetching user stats: $e');
      return {'followers': 0, 'following': 0, 'contributions': 0, 'uploads': 0};
    }
  }

  /// Get followers count
  Future<int> getFollowersCount(String userEmail) async {
    try {
      if (userEmail == currentUserEmail) {
        final res = await _api.getFollowers();
        final list = List<Map<String, dynamic>>.from(res['followers'] ?? []);
        return list.length;
      }

      final identifiers = await _resolveUserIdentifiers(userEmail);
      var maxCount = 0;

      if (identifiers.isNotEmpty) {
        for (final id in identifiers) {
          try {
            final withStatus = await _client
                .from('follows')
                .count(CountOption.exact)
                .eq('following_id', id)
                .eq('status', 'accepted');
            if (withStatus > maxCount) maxCount = withStatus;
            continue;
          } catch (_) {}

          try {
            final withoutStatus = await _client
                .from('follows')
                .count(CountOption.exact)
                .eq('following_id', id);
            if (withoutStatus > maxCount) maxCount = withoutStatus;
          } catch (_) {}
        }
      }

      try {
        final emailCount = await _client
            .from('follows')
            .count(CountOption.exact)
            .eq('following_email', userEmail.toLowerCase());
        if (emailCount > maxCount) maxCount = emailCount;
      } catch (_) {}

      return maxCount;
    } catch (e) {
      return 0;
    }
  }

  /// Get following count
  Future<int> getFollowingCount(String userEmail) async {
    try {
      if (userEmail == currentUserEmail) {
        final res = await _api.getFollowing();
        final list = List<Map<String, dynamic>>.from(res['following'] ?? []);
        return list.length;
      }

      final identifiers = await _resolveUserIdentifiers(userEmail);
      var maxCount = 0;

      if (identifiers.isNotEmpty) {
        for (final id in identifiers) {
          try {
            final withStatus = await _client
                .from('follows')
                .count(CountOption.exact)
                .eq('follower_id', id)
                .eq('status', 'accepted');
            if (withStatus > maxCount) maxCount = withStatus;
            continue;
          } catch (_) {}

          try {
            final withoutStatus = await _client
                .from('follows')
                .count(CountOption.exact)
                .eq('follower_id', id);
            if (withoutStatus > maxCount) maxCount = withoutStatus;
          } catch (_) {}
        }
      }

      try {
        final emailCount = await _client
            .from('follows')
            .count(CountOption.exact)
            .eq('follower_email', userEmail.toLowerCase());
        if (emailCount > maxCount) maxCount = emailCount;
      } catch (_) {}

      return maxCount;
    } catch (e) {
      return 0;
    }
  }

  /// Get unique values for filters
  Future<List<String>> getUniqueValues(
    String column,
    String collegeId, {
    String? branch,
  }) async {
    try {
      var query = _client
          .from('resources')
          .select(column)
          .eq('college_id', collegeId)
          .eq('status', 'approved');

      if (branch != null && branch.isNotEmpty) {
        query = query.eq('branch', branch);
      }

      final response = await query;

      final values = (response as List)
          .map((row) => row[column]?.toString())
          .where((v) => v != null && v.isNotEmpty)
          .toSet()
          .toList();

      values.sort();
      return values.cast<String>();
    } catch (e) {
      debugPrint('Error fetching unique values for $column: $e');
      return [];
    }
  }

  /// Vote on a resource
  Future<void> voteResource(
    String userEmail,
    String resourceId,
    int direction,
  ) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      // The backend expects 'upvote' or 'downvote'
      final voteType = direction == 1 ? 'upvote' : 'downvote';

      await _api.castVote(
        resourceId: resourceId,
        voteType: voteType,
        context: ctx,
      );
      // The backend handles the logic of toggling/updating and returns the new counts,
      // but here we just need to ensure the request succeeds.
    } catch (e) {
      debugPrint('Error voting on resource: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createResource({
    required String collegeId,
    required String title,
    required String type, // notes, pyq, video
    required String semester,
    required String branch,
    required String subject,
    required String uploadedByEmail,
    required String uploadedByName,
    String? filePath,
    String? videoUrl,
    String? description,
    String? chapter,
    String? topic,
  }) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      final input = {
        'collegeId': collegeId,
        'title': title.trim(),
        'type': type,
        'semester': semester,
        'branch': branch,
        'subject': subject,
        'status': 'approved',
        'source': 'student',
        'filePath': filePath, // Corrected from fileUrl
        'url': videoUrl, // Corrected from videoUrl
        'description': description?.trim(),
        'chapter': chapter,
        'topic': topic,
        'uploadedByName': uploadedByName,
        'uploadedByEmail': uploadedByEmail,
      };

      debugPrint(
        'Calling _api.createResource for college: $collegeId, type: $type',
      );

      return await _api.createResource(input, context: ctx);
    } catch (e) {
      debugPrint('Error in createResource: $e');
      throw Exception('Failed to upload resource: $e');
    }
  }

  /// Create a new chat room
  Future<Map<String, dynamic>> createChatRoom({
    required String name,
    required String description,
    required bool isPrivate,
    required String userEmail,
    required String collegeId,
    List<String>? tags,
    int? durationInDays,
  }) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      // Limits are now strictly enforced on backend.
      // We pass the desired duration (-1 for permanent).

      final data = await _api.createChatRoom(
        name: name.trim(),
        description: description.trim().isEmpty == true
            ? null
            : description.trim(),
        isPrivate: isPrivate,
        collegeId: collegeId,
        context: ctx,
        durationInDays: durationInDays,
        tags: tags,
      );
      // backend returns { message, id, joinCode? }
      return {
        'id': data['id'],
        'joinCode': data['joinCode'],
        'message': data['message'],
      };
    } catch (e) {
      if (e is RoomLimitException) {
        rethrow;
      }
      // Parse backend error message if possible
      if (e.toString().contains('Room limit reached')) {
        throw RoomLimitException(e.toString().replaceAll('Exception: ', ''));
      }
      throw Exception('Failed to create room: $e');
    }
  }

  /// Get user's votes for a room
  Future<Map<String, int>> getUserVotes(String roomId) async {
    try {
      final res = await _api.getUserVotes(roomId);
      final votes = res['votes'] as Map<String, dynamic>? ?? {};

      final Map<String, int> result = {};
      votes.forEach((key, value) {
        if (value == 'up') {
          result[key] = 1;
        } else if (value == 'down') {
          result[key] = -1;
        }
      });
      return result;
    } catch (e) {
      debugPrint('Error fetching user votes: $e');
      return {};
    }
  }

  /// Get room info
  Future<Map<String, dynamic>?> getRoomInfo(String roomId) async {
    try {
      final response = await _client
          .from('chat_rooms')
          .select()
          .eq('id', roomId)
          .single();
      return response;
    } catch (e) {
      return null;
    }
  }

  /// Check if user is room admin
  Future<bool> isRoomAdmin(String roomId, String userEmail) async {
    try {
      final response = await _client
          .from('room_members')
          .select('role')
          .eq('room_id', roomId)
          .eq('user_email', userEmail)
          .maybeSingle();

      return response != null && response['role'] == 'admin';
    } catch (e) {
      return false;
    }
  }

  /// Get members of a room with role and join metadata.
  Future<List<Map<String, dynamic>>> getRoomMembers(String roomId) async {
    try {
      final response = await _client
          .from('room_members')
          .select('*')
          .eq('room_id', roomId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching room members: $e');
      return [];
    }
  }

  Future<void> joinChatRoom(
    String code,
    String userEmail,
    String collegeId,
  ) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      await _api.joinChatRoom(code, userEmail, collegeId);
    } catch (e) {
      debugPrint('Error joining chat room: $e');
      rethrow;
    }
  }

  /// Get room messages
  Future<List<Map<String, dynamic>>> getRoomMessages(
    String roomId, {
    int limit = 50,
  }) async {
    try {
      final response = await _client
          .from('room_messages')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: true)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching messages: $e');
      return [];
    }
  }

  /// Subscribe to room messages (real-time)
  RealtimeChannel subscribeToMessages(
    String roomId,
    Function(Map<String, dynamic>) onMessage,
  ) {
    return _client
        .channel('room:$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'room_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            onMessage(payload.newRecord);
          },
        )
        .subscribe();
  }

  /// Send a message to a chat room
  Future<void> sendChatMessage({
    required String roomId,
    required String userEmail,
    required String userName,
    required String content,
    String? imageUrl,
  }) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      await _api.postChatMessage(
        roomId: roomId,
        content: content,
        imageUrl: imageUrl,
        authorName: userName,
        context: ctx,
      );
    } catch (e) {
      debugPrint('Error sending message: $e');
      rethrow;
    }
  }

  /// Get posts for a room (Reddit-style)
  Future<List<Map<String, dynamic>>> getRoomPosts(
    String roomId, {
    int limit = 50,
    String sortBy = 'recent',
  }) async {
    try {
      final String orderColumn = sortBy == 'top' ? 'upvotes' : 'created_at';

      // select with comment count from 'room_post_comments' (linked to 'room_messages' via message_id)
      // Note: The foreign key on room_post_comments.message_id points to room_messages.id
      final response = await _client
          .from('room_messages')
          .select('*, comment_count:room_post_comments(count)')
          .eq('room_id', roomId)
          .order(orderColumn, ascending: false)
          .range(0, limit - 1);

      return (response as List).map((e) {
        final data = Map<String, dynamic>.from(e);
        // Fix count format
        data['comment_count'] = _normalizeCount(data['comment_count']);
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Error fetching room posts: $e');
      return [];
    }
  }

  /// Get comments for a post
  Future<List<Map<String, dynamic>>> getPostComments(String postId) async {
    List<Map<String, dynamic>> allComments = [];

    try {
      // Attempt 1: Direct Supabase Query (room_post_comments)
      final response = await _client
          .from('room_post_comments')
          .select('*')
          .eq('message_id', postId)
          .order('created_at', ascending: true);

      allComments = List<Map<String, dynamic>>.from(response);
    } catch (directError) {
      try {
        // Attempt 2: API Fallback (Existing)
        allComments = await _api.getChatComments(postId);
      } catch (apiError) {
        debugPrint(
          'Error fetching post comments (Direct & API failed): $apiError',
        );
        return [];
      }
    }

    try {
      // Build thread structure (Client-side threading)
      final Map<String, List<Map<String, dynamic>>> commentMap = {};
      final List<Map<String, dynamic>> topLevelComments = [];

      // First pass: organize comments by parent_id
      for (var comment in allComments) {
        final parentId =
            comment['parentId'] as String? ?? comment['parent_id'] as String?;
        // Ensure replies list exists
        comment['replies'] = <Map<String, dynamic>>[];

        if (parentId == null) {
          topLevelComments.add(comment);
        } else {
          if (!commentMap.containsKey(parentId)) {
            commentMap[parentId] = [];
          }
          commentMap[parentId]!.add(comment);
        }
      }

      // Second pass: attach replies to their parents
      void attachReplies(Map<String, dynamic> comment) {
        final commentId = comment['id']?.toString();
        if (commentId != null && commentMap.containsKey(commentId)) {
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
      debugPrint('Error processing comment tree: $e');
      return [];
    }
  }

  /// Create a new post in a room
  Future<void> createPost({
    required String roomId,
    required String title,
    required String content,
    required String userEmail,
    required String userName,
    String? imageUrl,
    String? linkUrl,
  }) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');
      final fullContent = title.isNotEmpty ? '$title\n$content' : content;
      await _api.postChatMessage(
        roomId: roomId,
        content: fullContent,
        imageUrl: imageUrl,
        authorName: userName,
        context: ctx,
      );
    } catch (e) {
      debugPrint('Error creating post: $e');
      rethrow;
    }
  }

  /// Add a comment to a post
  Future<void> addPostComment({
    required String postId,
    required String content,
    required String userEmail,
    required String userName,
    String? parentId,
  }) async {
    try {
      // Website uses message_id (not post_id) via backend.
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');
      await _api.addChatComment(
        messageId: postId,
        content: content,
        authorName: userName,
        parentId: parentId,
        context: ctx,
      );
    } catch (e) {
      debugPrint('Error adding comment: $e');
      rethrow;
    }
  }

  /// Delete a post comment (owner/admin moderation).
  Future<void> deletePostComment(String commentId) async {
    final ctx = _ctx;
    if (ctx == null) throw Exception('Security context not initialized');
    try {
      await _api.deleteChatComment(commentId: commentId, context: ctx);
    } catch (e) {
      debugPrint('Error deleting post comment: $e');
      rethrow;
    }
  }
  /// Vote on a post
  Future<void> votePost(String postId, String userEmail, int direction) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      await _api.voteChatMessage(
        messageId: postId,
        direction: direction == 1 ? 'up' : 'down',
        context: ctx,
      );
    } catch (e) {
      debugPrint('Error voting on post: $e');
      rethrow;
    }
  }

  // ============ SAVED POSTS ============

  // ============ SAVED POSTS ============

  /// Save a post
  Future<void> savePost(String postId, String userEmail) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      // Assuming we need a roomId for the backend API, but the legacy method didn't take one.
      // We might need to fetch the message detailed to get the room ID or update the UI to pass it.
      // For now, let's assume postId/messageId is enough if we had an endpoint that just took messageId,
      // but toggleSavePost takes both.
      // Workaround: We find the room_id for this message first.

      final msg = await _client
          .from('room_messages')
          .select('room_id')
          .eq('id', postId)
          .single();
      final roomId = msg['room_id'];

      await _api.toggleSaveChatMessage(
        messageId: postId,
        roomId: roomId,
        context: ctx,
      );
    } catch (e) {
      debugPrint('Error saving post: $e');
      rethrow;
    }
  }

  /// Check if a post is saved
  Future<bool> isPostSaved(String postId, String userEmail) async {
    try {
      final response = await _client
          .from('saved_posts')
          .select('id')
          .eq(
            'post_id',
            postId,
          ) // Assuming 'post_id' is the column name for message ID in saved_posts
          .eq('user_email', userEmail)
          .maybeSingle();
      return response != null;
    } catch (e) {
      // Try checking if it's saved by message_id directly if legacy schema
      try {
        final response = await _client
            .from('saved_posts')
            .select('id')
            .eq('message_id', postId)
            .eq('user_email', userEmail)
            .maybeSingle();
        return response != null;
      } catch (e2) {
        return false;
      }
    }
  }

  /// Unsave a post
  Future<void> unsavePost(String postId, String userEmail) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      // Same logic as savePost - backend toggles it.
      // But we need room_id.
      final msg = await _client
          .from('room_messages')
          .select('room_id')
          .eq('id', postId)
          .single();
      final roomId = msg['room_id'];

      await _api.toggleSaveChatMessage(
        messageId: postId,
        roomId: roomId,
        context: ctx,
      );
    } catch (e) {
      debugPrint('Error unsaving post: $e');
      rethrow;
    }
  }

  /// Get all saved post IDs for a user (Batch Optimization)
  Future<Set<String>> getSavedPostIds(String userEmail) async {
    try {
      final response = await _client
          .from('saved_posts')
          .select('post_id')
          .eq('user_email', userEmail);

      return (response as List)
          .where((e) => e['post_id'] != null)
          .map((e) => e['post_id'].toString())
          .toSet();
    } catch (e) {
      debugPrint('Error fetching saved post IDs: $e');
      return {};
    }
  }

  /// Get all saved posts for a user
  Future<List<Map<String, dynamic>>> getSavedPosts(String userEmail) async {
    try {
      final response = await _client
          .from('saved_posts')
          .select(
            'message_id, room_messages(*, comment_count:room_post_comments(count))',
          )
          .eq('user_email', userEmail)
          .order('created_at', ascending: false);

      return (response as List)
          .where((row) => row['room_messages'] != null)
          .map((row) {
            final data = Map<String, dynamic>.from(row['room_messages']);
            // Fix count format
            data['comment_count'] = _normalizeCount(data['comment_count']);
            return data;
          })
          .toList();
    } catch (e) {
      debugPrint('Error fetching saved posts: $e');
      return [];
    }
  }

  // ============ SYLLABUS ============

  /// Get syllabus for a department with optional filters
  Future<List<Map<String, dynamic>>> getSyllabus({
    required String collegeId,
    required String department,
    String? semester,
    String? subject,
  }) async {
    try {
      var query = _client
          .from('syllabus')
          .select()
          .eq('college_id', collegeId)
          .eq('department', department); // This is effectively the 'branch'

      if (semester != null && semester.isNotEmpty && semester != 'All') {
        query = query.eq('semester', semester);
      }

      if (subject != null && subject.isNotEmpty && subject != 'All') {
        query = query.eq('subject', subject);
      }

      final response = await query.order('semester');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching syllabus: $e');
      return [];
    }
  }

  // ============ DEPARTMENT FOLLOWERS ============

  /// Follow a department
  Future<void> followDepartment(
    String departmentId,
    String collegeId,
    String userEmail,
  ) async {
    try {
      await _client.from('department_followers').insert({
        'department_id': departmentId,
        'college_id': collegeId,
        'user_email': userEmail,
        'followed_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error following department: $e');
      rethrow;
    }
  }

  /// Unfollow a department
  Future<void> unfollowDepartment(String departmentId, String userEmail) async {
    try {
      await _client
          .from('department_followers')
          .delete()
          .eq('department_id', departmentId)
          .eq('user_email', userEmail);
    } catch (e) {
      debugPrint('Error unfollowing department: $e');
      rethrow;
    }
  }

  /// Check if following department
  Future<bool> isFollowingDepartment(
    String departmentId,
    String userEmail,
  ) async {
    try {
      final response = await _client
          .from('department_followers')
          .select('id')
          .eq('department_id', departmentId)
          .eq('user_email', userEmail)
          .maybeSingle();
      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Get department follower count
  Future<int> getDepartmentFollowerCount(
    String departmentId,
    String collegeId,
  ) async {
    try {
      final response = await _client
          .from('department_followers')
          .count(CountOption.exact)
          .eq('department_id', departmentId)
          .eq('college_id', collegeId);
      return response;
    } catch (e) {
      debugPrint('Error getting department follower count: $e');
      return 0;
    }
  }

  /// Get followed department IDs
  Future<List<String>> getFollowedDepartmentIds(
    String collegeId,
    String userEmail,
  ) async {
    try {
      final response = await _client
          .from('department_followers')
          .select('department_id')
          .eq('college_id', collegeId)
          .eq('user_email', userEmail);
      return (response as List)
          .map((e) => e['department_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();
    } catch (e) {
      debugPrint('Error getting followed departments: $e');
      return [];
    }
  }

  // ============ NOTICE COMMENTS ============

  /// Add comment to notice
  Future<void> addNoticeComment({
    required String noticeId,
    required String content,
    required String userEmail,
    required String userName,
    String? parentId,
  }) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');
      await _api.postNoticeComment(
        noticeId: noticeId,
        content: content,
        parentId: parentId,
        context: ctx,
      );
    } catch (e) {
      debugPrint('Error adding notice comment: $e');
      rethrow;
    }
  }

  // ============ NOTICE ENTITY BOOKMARKS ============

  /// Save (Bookmark) a notice
  Future<void> saveNotice(String noticeId, String userEmail) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');
      await _api.addBookmark(itemId: noticeId, type: 'notice', context: ctx);
    } catch (e) {
      debugPrint('Error saving notice: $e');
      rethrow;
    }
  }

  /// Unsave a notice
  Future<void> unsaveNotice(String noticeId, String userEmail) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');
      await _api.removeBookmarkByItem(itemId: noticeId, context: ctx);
    } catch (e) {
      debugPrint('Error unsaving notice: $e');
      rethrow;
    }
  }

  /// Check if notice is saved
  Future<bool> isNoticeSaved(String noticeId, String userEmail) async {
    try {
      return await _api.checkBookmark(noticeId);
    } catch (e) {
      return false;
    }
  }
  // ============ CHAT (RESTORED) ============

  // ============ MISSING METHODS (STUBS / SIMPLE IMPLEMENTATIONS) ============
  // ============ USER FOLLOWS ============

  /// Get list of users the current user follows

  /// Get list of users following the current user

  /// List students for a college, based on email domain.

  // ============ EMOJI REACTIONS ============

  /// Get chat rooms for a college (with member count)
  Future<List<Map<String, dynamic>>> getChatRooms(
    String userEmail,
    String collegeId,
  ) async {
    try {
      final response = await _client
          .from('chat_rooms')
          .select('*, member_count:room_members(count)')
          .eq('college_id', collegeId)
          .order('created_at', ascending: false);

      final rooms = (response as List).map((e) {
        final data = Map<String, dynamic>.from(e);
        // Fix count format if it comes as list
        data['member_count'] = _normalizeCount(data['member_count']);
        return data;
      }).toList();

      final now = DateTime.now().toUtc();
      return rooms.where((room) {
        final isActive = room['is_active'] ?? room['isActive'];
        if (isActive == false) return false;

        final expiryRaw = room['expiry_date'] ?? room['expiryDate'];
        if (expiryRaw == null) return true;
        final expiry = DateTime.tryParse(expiryRaw.toString());
        if (expiry == null) return true;
        final expiryUtc = expiry.isUtc ? expiry : expiry.toUtc();
        return expiryUtc.isAfter(now);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching chat rooms: $e');
      return [];
    }
  }

  /// Get all reactions for a comment
  Future<Map<String, dynamic>> getCommentReactions({
    required String commentId,
    required String commentType, // 'notice' or 'post'
  }) async {
    try {
      final response = await _client
          .from('comment_reactions')
          .select()
          .eq('comment_id', commentId)
          .eq('comment_type', commentType);

      // Group by emoji
      final Map<String, List<String>> grouped = {};
      for (var r in response) {
        final emoji = r['emoji'] as String;
        final userEmail = r['user_email'] as String;
        grouped.putIfAbsent(emoji, () => []).add(userEmail);
      }

      return {'reactions': grouped, 'total': response.length};
    } catch (e) {
      debugPrint('Error fetching comment reactions: $e');
      return {'reactions': {}, 'total': 0};
    }
  }

  /// Toggle a reaction
  Future<bool> toggleReaction({
    required String commentId,
    required String commentType,
    required String userEmail,
    required String emoji,
  }) async {
    try {
      // Atomic-like toggle: Try to remove first.
      // If removed (returned true), we are done (unliked).
      // If not removed (returned false), it didn't exist, so we add it (liked).
      final removed = await removeReaction(
        commentId: commentId,
        commentType: commentType,
        userEmail: userEmail,
        emoji: emoji,
      );

      if (removed) {
        return false;
      } else {
        await addReaction(
          commentId: commentId,
          commentType: commentType,
          userEmail: userEmail,
          emoji: emoji,
        );
        return true;
      }
    } catch (e) {
      debugPrint('Error toggling reaction: $e');
      rethrow;
    }
  }

  /// Add a reaction to a comment
  Future<void> addReaction({
    required String commentId,
    required String commentType,
    required String userEmail,
    required String emoji,
  }) async {
    try {
      await _client.from('comment_reactions').upsert({
        'comment_id': commentId,
        'comment_type': commentType,
        'user_email': userEmail,
        'emoji': emoji,
      });
    } catch (e) {
      debugPrint('Error adding reaction: $e');
      rethrow;
    }
  }

  /// Remove a reaction
  Future<bool> removeReaction({
    required String commentId,
    required String commentType,
    required String userEmail,
    required String emoji,
  }) async {
    try {
      final response = await _client
          .from('comment_reactions')
          .delete()
          .eq('comment_id', commentId)
          .eq('comment_type', commentType)
          .eq('user_email', userEmail)
          .eq('emoji', emoji)
          .select();

      return response.isNotEmpty;
    } catch (e) {
      debugPrint('Error removing reaction: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getNotices({
    required String collegeId,
  }) async {
    try {
      final response = await _client
          .from('notices')
          .select()
          .eq('college_id', collegeId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting notices: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getNoticeComments(String noticeId) async {
    try {
      // Fetch flat comments
      final rawComments = await _api.getNoticeComments(noticeId);

      // Build thread structure (Client-side threading)
      final Map<String, List<Map<String, dynamic>>> commentMap = {};
      final List<Map<String, dynamic>> topLevelComments = [];

      // First pass: organize comments by parent_id
      for (var comment in rawComments) {
        final parentId = comment['parent_id']?.toString(); // Robust conversion
        // Ensure replies list exists
        comment['replies'] = <Map<String, dynamic>>[];

        if (parentId == null || parentId.isEmpty) {
          // Handle empty string same as null
          topLevelComments.add(comment);
        } else {
          if (!commentMap.containsKey(parentId)) {
            commentMap[parentId] = [];
          }
          commentMap[parentId]!.add(comment);
        }
      }

      // Second pass: attach replies to their parents
      void attachReplies(Map<String, dynamic> comment) {
        final commentId = comment['id']?.toString();
        if (commentId != null && commentMap.containsKey(commentId)) {
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
      debugPrint('Error getting notice comments: $e');
      rethrow;
    }
  }

  Future<List<String>> getUserRoomIds(String userEmail) async {
    try {
      final res = await _client
          .from('room_members')
          .select('room_id')
          .eq('user_email', userEmail);
      return (res as List).map((e) => e['room_id'] as String).toList();
    } catch (e) {
      debugPrint('Error getting joined rooms: $e');
      return [];
    }
  }

  /// Toggle bookmark for a resource - returns new bookmark state
  Future<bool> toggleBookmark(String userEmail, String resourceId) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      final isMarked = await _api.checkBookmark(resourceId);
      if (isMarked) {
        await _api.removeBookmarkByItem(itemId: resourceId, context: ctx);
        return false;
      }

      await _api.addBookmark(
        itemId: resourceId,
        type: 'resource',
        context: ctx,
      );
      return true;
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      rethrow;
    }
  }

  /// Check if a resource is bookmarked by the user
  Future<bool> isBookmarked(String userEmail, String resourceId) async {
    try {
      return await _api.checkBookmark(resourceId);
    } catch (e) {
      debugPrint('Error checking bookmark: $e');
      return false;
    }
  }

  // ============ NOTICES ============

  Future<Map<String, dynamic>?> getNotice(String id) async {
    try {
      final response = await _client
          .from('notices')
          .select()
          .eq('id', id)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error fetching notice: $e');
      return null;
    }
  }

  Future<DepartmentAccount?> getDepartmentProfile(String departmentId) async {
    try {
      // Assuming 'departments' table exists or 'users' with role/type
      // Adjust table name if needed based on schema.
      // Based on notification service, department accounts might be in 'users' or separate 'departments'.
      // If 'department_followers' links to 'department_id', likely a separate table or users.

      // Try 'users' first as many systems unify accounts
      final response = await _client
          .from('users')
          .select()
          .eq('id', departmentId)
          .maybeSingle();

      if (response != null) {
        return DepartmentAccount(
          id: response['id'],
          name: response['display_name'] ?? response['name'] ?? 'Department',
          handle: response['username'] ?? '',
          avatarLetter: (response['display_name'] ?? 'D')[0],
          color: Colors.blue, // Default color
          noticeCount: 0,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching department profile: $e');
      return null;
    }
  }

  /// Get resources uploaded by a specific user.
  /// If [approvedOnly] is true (default), only approved resources are returned.
  Future<List<Resource>> getUserResources(
    String userEmail, {
    bool approvedOnly = true,
    int limit = 50,
    int offset = 0,
  }) async {
    if (userEmail.isEmpty) return [];
    if (limit <= 0) return [];

    try {
      var query = _client
          .from('resources')
          .select()
          .eq('uploaded_by_email', userEmail);

      if (approvedOnly) {
        query = query.eq('status', 'approved');
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((item) => Resource.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching user resources: $e');
      return [];
    }
  }

  int _normalizeCount(dynamic countVal) {
    if (countVal is List && countVal.isNotEmpty) {
      final first = countVal[0];
      if (first is Map && first.containsKey('count')) {
        return (first['count'] as int?) ?? 0;
      }
      return 0;
    } else if (countVal is int) {
      return countVal;
    }
    return 0;
  }
}
