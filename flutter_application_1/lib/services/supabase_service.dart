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

enum FollowStatus {
  notFollowing,
  pending,
  following,
}

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;
  final BackendApiService _api = BackendApiService();

  /// A BuildContext is required to run reCAPTCHA (invisible WebView) before privileged writes.
  /// Set this once from a top-level screen (e.g. HomeScreen) via [attachContext].
  static BuildContext? _ctx;

  void attachContext(BuildContext context) {
    _ctx = context;
  }

  String? get currentUserEmail => _client.auth.currentUser?.email;

  // ============ COLLEGES ============
  
  /// Get all active colleges
  Future<List<College>> getColleges() async {
    try {
      final response = await _client
          .from('colleges')
          .select()
          .eq('is_active', true)
          .order('name');
      
      return (response as List)
          .map((json) => College.fromJson(json))
          .toList();
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
      
      return (response as List)
          .map((json) => College.fromJson(json))
          .toList();
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
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      debugPrint('SupabaseService.getResources: collegeId=$collegeId, semester=$semester, branch=$branch, type=$type');
      
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
      
      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      
      debugPrint('SupabaseService.getResources: returned ${(response as List).length} resources');
      
      return (response as List)
          .map((json) => Resource.fromJson(json))
          .toList();
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
      // First get list of users this user follows
      final followsResponse = await _client
          .from('follows')
          .select('following_email')
          .eq('follower_email', userEmail);
      
      final followingEmails = (followsResponse as List)
          .map((r) => r['following_email'] as String)
          .toList();
      
      if (followingEmails.isEmpty) return [];
      
      // Then get resources uploaded by those users
      final response = await _client
          .from('resources')
          .select()
          .eq('college_id', collegeId)
          .eq('status', 'approved')
          .inFilter('uploaded_by_email', followingEmails)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      
      return (response as List)
          .map((json) => Resource.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching following feed: $e');
      return [];
    }
  }

  /// Get follow status
  Future<FollowStatus> getFollowStatus(String followerEmail, String followingEmail) async {
    if (followerEmail == followingEmail) return FollowStatus.notFollowing;

    try {
      // Check if already following
      final following = await _client
          .from('follows')
          .select()
          .match({'follower_email': followerEmail, 'following_email': followingEmail})
          .maybeSingle();
      
      if (following != null) return FollowStatus.following;

      // Check for pending request - use 'users' table lookup if needed for IDs
      // But currently we use emails in app.
      // The backend 'follow_requests' table uses IDs (VARCHAR 128)
      // We need to fetch User IDs first.
      
      final followerId = await getUserId(followerEmail);
      final targetId = await getUserId(followingEmail);

      if (followerId == null || targetId == null) return FollowStatus.notFollowing;

      final request = await _client
          .from('follow_requests')
          .select('status')
          .match({'requester_id': followerId, 'target_id': targetId, 'status': 'pending'})
          .maybeSingle();

      if (request != null) return FollowStatus.pending;

      return FollowStatus.notFollowing;
    } catch (e) {
      debugPrint('Error getting follow status: $e');
      return FollowStatus.notFollowing;
    }
  }

  /// Send follow request
  Future<void> sendFollowRequest(String followerEmail, String followingEmail) async {
    try {
      final followerId = await getUserId(followerEmail);
      final targetId = await getUserId(followingEmail);

      if (followerId == null || targetId == null) throw Exception('User ID not found');

      // Create request
      final request = await _client
          .from('follow_requests')
          .insert({
            'requester_id': followerId,
            'target_id': targetId,
            'status': 'pending'
          })
          .select()
          .single();

      // Create notification for target user
      await _createNotification(
        userId: targetId,
        type: 'follow_request',
        title: 'New Follow Request',
        message: 'Someone wants to follow you', // Ideally fetch name
        actorId: followerId,
        followRequestId: request['id'] as int,
        isActionable: true,
      );

    } catch (e) {
      debugPrint('Error sending follow request: $e');
      rethrow;
    }
  }

  /// Cancel follow request
  Future<void> cancelFollowRequest(String followerEmail, String followingEmail) async {
    try {
      final followerId = await getUserId(followerEmail);
      final targetId = await getUserId(followingEmail);

      if (followerId == null || targetId == null) return;

      await _client
          .from('follow_requests')
          .delete()
          .match({'requester_id': followerId, 'target_id': targetId, 'status': 'pending'});
          
      // Cleanup notification manually if RLS allows or rely on backend cron.
      // Ideally delete notification associated with this request
    } catch (e) {
      debugPrint('Error cancelling follow request: $e');
      rethrow;
    }
  }

  /// Accept follow request
  Future<void> acceptFollowRequest(int requestId) async {
    try {
      // Fetch request details first
      final request = await _client
          .from('follow_requests')
          .select()
          .eq('id', requestId)
          .single();
      
      final requesterId = request['requester_id'];
      final targetId = request['target_id'];

      // Get emails
      final requesterEmail = await getUserEmail(requesterId);
      final targetEmail = await getUserEmail(targetId);

      if (requesterEmail == null || targetEmail == null) return;

      // 1. Update request status
      await _client
          .from('follow_requests')
          .update({'status': 'accepted'})
          .eq('id', requestId);

      // 2. Add to follows table
      await _client
          .from('follows')
          .insert({'follower_email': requesterEmail, 'following_email': targetEmail});

      // 3. Create Accepted Notification for requester
      await _createNotification(
        userId: requesterId,
        type: 'follow_accepted',
        title: 'Request Accepted',
        message: 'You are now following this user',
        actorId: targetId,
      );

    } catch (e) {
      debugPrint('Error accepting follow request: $e');
      rethrow;
    }
  }

  /// Reject follow request
  Future<void> rejectFollowRequest(int requestId) async {
    try {
      await _client
          .from('follow_requests')
          .update({'status': 'rejected'})
          .eq('id', requestId);
      
      // Optionally delete the request record entirely or keep as history
    } catch (e) {
      debugPrint('Error rejecting follow request: $e');
      rethrow;
    }
  }

  // Leave a room
  Future<void> leaveRoom(String roomId, String userEmail) async {
    try {
      await _client
          .from('room_members')
          .delete()
          .match({'room_id': roomId, 'user_email': userEmail});
    } catch (e) {
      debugPrint('Error leaving room: $e');
      throw e;
    }
  }

  // Join a room (RPC)
  Future<void> joinRoom(String roomId) async {
    try {
      final response = await _client.rpc('join_room', params: {
        'room_id_input': roomId, // Note: param name must match SQL function arg
      });
      
      // Check response if needed, but RPC usually throws on error if we don't catch inside SQL
      // Our SQL returns a JSONB object, so we can check 'success'
      if (response != null && response['success'] == false) {
         throw response['error'] ?? 'Unknown error';
      }
    } catch (e) {
      debugPrint('Error joining room: $e');
      throw e;
    }
  }

  // Delete a room (admin only)
  Future<void> deleteRoom(String roomId) async {
    try {
      final response = await _client.rpc('delete_room', params: {
        'room_id_input': roomId,
      });
      
      if (response != null && response['success'] == false) {
         throw response['error'] ?? 'Unknown error';
      }
    } catch (e) {
      debugPrint('Error deleting room: $e');
      throw e;
    }
  }

  // Get user's room limits (how many joined/created, max allowed)
  Future<Map<String, dynamic>> getRoomLimits() async {
    try {
      final response = await _client.rpc('get_user_room_limits');
      return response ?? {
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

  Future<void> unfollowUser(String followerEmail, String followingEmail) async {
    try {
      await _client
          .from('follows')
          .delete()
          .match({'follower_email': followerEmail, 'following_email': followingEmail});
    } catch (e) {
      debugPrint('Error unfollowing user: $e');
      rethrow;
    }
  }

  // Helpers
  Future<String?> getUserId(String email) async {
    final res = await _client.from('users').select('id').eq('email', email).maybeSingle();
    return res?['id'] as String?;
  }

  Future<String?> getUserEmail(String id) async {
    final res = await _client.from('users').select('email').eq('id', id).maybeSingle();
    return res?['email'] as String?;
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
    await _client.from('notifications').insert({
      'user_id': userId,
      'type': type,
      'title': title,
      'message': message,
      'actor_id': actorId,
      'follow_request_id': followRequestId,
      'is_actionable': isActionable,
      'is_read': false, // Explicit
    });
  }

  /// Check if following a user (Legacy check mostly, but useful)
  Future<bool> isFollowing(String followerEmail, String followingEmail) async {
      try {
        final response = await _client
            .from('follows')
            .select()
            .match({'follower_email': followerEmail, 'following_email': followingEmail})
            .maybeSingle();
        return response != null;
      } catch (e) {
        return false;
      }
  }

  /// Get followers count
  Future<int> getFollowersCount(String userEmail) async {
    try {
      final response = await _client
          .from('follows') // Still using follows table
          .count(CountOption.exact)
          .eq('following_email', userEmail);
      return response;
    } catch (e) {
      return 0;
    }
  }

  /// Get following count
  Future<int> getFollowingCount(String userEmail) async {
    try {
      final response = await _client
          .from('follows')
          .count(CountOption.exact)
          .eq('follower_email', userEmail);
      return response;
    } catch (e) {
      return 0;
    }
  }

  /// Get unique values for filters
  Future<List<String>> getUniqueValues(String column, String collegeId, {String? branch}) async {
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
  Future<void> voteResource(String userEmail, String resourceId, int direction) async {
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
        'url': videoUrl,      // Corrected from videoUrl
        'description': description?.trim(),
        'chapter': chapter,
        'topic': topic,
        'uploadedByName': uploadedByName,
        'uploadedByEmail': uploadedByEmail,
      };

      debugPrint('Calling _api.createResource for college: $collegeId, type: $type');
      
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
        description: description.trim().isEmpty == true ? null : description.trim(),
        isPrivate: isPrivate,
        collegeId: collegeId,
        context: ctx,
        durationInDays: durationInDays,
        tags: tags,
      );
      // backend returns { message, id, joinCode? }
      return {'id': data['id'], 'joinCode': data['joinCode'], 'message': data['message']};
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
        if (value == 'up') result[key] = 1;
        else if (value == 'down') result[key] = -1;
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






  Future<void> joinChatRoom(String code, String userEmail, String collegeId) async {
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
  Future<List<Map<String, dynamic>>> getRoomMessages(String roomId, {int limit = 50}) async {
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
  RealtimeChannel subscribeToMessages(String roomId, Function(Map<String, dynamic>) onMessage) {
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
  Future<List<Map<String, dynamic>>> getRoomPosts(String roomId, {int limit = 50, String sortBy = 'recent'}) async {
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
        final countVal = data['comment_count'];
        if (countVal is List && countVal.isNotEmpty) {
           data['comment_count'] = countVal[0]['count'];
        } else if (countVal is int) {
           data['comment_count'] = countVal;
        } else {
           data['comment_count'] = 0;
        }
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
        debugPrint('Error fetching post comments (Direct & API failed): $apiError');
        return [];
      }
    }

    try {
      // Build thread structure (Client-side threading)
      final Map<String, List<Map<String, dynamic>>> commentMap = {};
      final List<Map<String, dynamic>> topLevelComments = [];
      
      // First pass: organize comments by parent_id
      for (var comment in allComments) {
        final parentId = comment['parentId'] as String? ?? comment['parent_id'] as String?;
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
      
      final msg = await _client.from('room_messages').select('room_id').eq('id', postId).single();
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

  /// Unsave a post
  Future<void> unsavePost(String postId, String userEmail) async {
     try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      // Same logic as savePost - backend toggles it. 
      // But we need room_id.
      final msg = await _client.from('room_messages').select('room_id').eq('id', postId).single();
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

  /// Check if post is saved
  Future<bool> isPostSaved(String postId, String userEmail) async {
    try {
      final response = await _client
          .from('saved_posts')
          .select('id')
          .eq('message_id', postId)
          .eq('user_email', userEmail)
          .maybeSingle();
      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Get all saved post IDs for a user (Batch Optimization)
  Future<Set<String>> getSavedPostIds(String userEmail) async {
    try {
      final response = await _client
          .from('saved_posts')
          .select('message_id')
          .eq('user_email', userEmail);
      
      return (response as List).map((e) => e['message_id'].toString()).toSet();
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
          .select('message_id, room_messages(*, comment_count:room_post_comments(count))')
          .eq('user_email', userEmail)
          .order('created_at', ascending: false);
      
      return (response as List)
          .where((row) => row['room_messages'] != null)
          .map((row) {
             final data = Map<String, dynamic>.from(row['room_messages']);
             // Fix count format
             final countVal = data['comment_count'];
             if (countVal is List && countVal.isNotEmpty) {
                data['comment_count'] = countVal[0]['count'];
             } else if (countVal is int) {
                data['comment_count'] = countVal;
             } else {
                data['comment_count'] = 0;
             }
             return data;
          })
          .toList();
    } catch (e) {
      debugPrint('Error fetching saved posts: $e');
      return [];
    }
  }


  // ============ SYLLABUS ============

  /// Get syllabus for a department
  Future<List<Map<String, dynamic>>> getSyllabus({
    required String collegeId,
    required String department,
    String? semester,
  }) async {
    try {
      late final List<dynamic> response;
      
      if (semester != null && semester.isNotEmpty) {
        response = await _client
            .from('syllabus')
            .select()
            .eq('college_id', collegeId)
            .eq('department', department)
            .eq('semester', semester)
            .order('semester');
      } else {
        response = await _client
            .from('syllabus')
            .select()
            .eq('college_id', collegeId)
            .eq('department', department)
            .order('semester');
      }
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching syllabus: $e');
      return [];
    }
  }

  // ============ DEPARTMENT FOLLOWERS ============

  /// Follow a department
  Future<void> followDepartment(String departmentId, String collegeId, String userEmail) async {
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
      await _client.from('department_followers')
          .delete()
          .eq('department_id', departmentId)
          .eq('user_email', userEmail);
    } catch (e) {
      debugPrint('Error unfollowing department: $e');
      rethrow;
    }
  }

  /// Check if following department
  Future<bool> isFollowingDepartment(String departmentId, String userEmail) async {
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
  Future<int> getDepartmentFollowerCount(String departmentId, String collegeId) async {
    try {
      final response = await _client
          .from('department_followers')
          .count(CountOption.exact)
          .eq('department_id', departmentId)
          .eq('college_id', collegeId);
      return response;
    } catch (e) {
      return 0;
    }
  }

  /// Get followed department IDs
  Future<List<String>> getFollowedDepartmentIds(String collegeId, String userEmail) async {
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
  
  /// Get list of users fetching/following
  /// Get list of users the current user follows
  Future<List<Map<String, dynamic>>> getFollowing(String userEmail) async {
    try {
      // First get the user's firebase_uid from their email
      final currentUser = await _client
          .from('users')
          .select('firebase_uid')
          .eq('email', userEmail)
          .single();
      
      final String currentUserId = currentUser['firebase_uid'];
      
      // Get follows where this user is the follower (status = accepted)
      final follows = await _client
          .from('follows')
          .select('following_id')
          .eq('follower_id', currentUserId)
          .eq('status', 'accepted');
      
      final followingIds = (follows as List).map((e) => e['following_id'] as String).toList();
      
      if (followingIds.isEmpty) return [];

      // Get user details for these firebase_uids
      final users = await _client
          .from('users')
          .select('email, display_name, photo_url, college_id')
          .filter('firebase_uid', 'in', followingIds);
          
      return List<Map<String, dynamic>>.from(users);
    } catch (e) {
      debugPrint('Error fetching following: $e');
      return [];
    }
  }

  /// Get list of users following the current user
  Future<List<Map<String, dynamic>>> getFollowers(String userEmail) async {
    try {
      // First get the user's firebase_uid from their email
      final currentUser = await _client
          .from('users')
          .select('firebase_uid')
          .eq('email', userEmail)
          .single();
      
      final String currentUserId = currentUser['firebase_uid'];
      
      // Get follows where this user is being followed (status = accepted)
      final follows = await _client
          .from('follows')
          .select('follower_id')
          .eq('following_id', currentUserId)
          .eq('status', 'accepted');
      
      final followerIds = (follows as List).map((e) => e['follower_id'] as String).toList();
      
      if (followerIds.isEmpty) return [];

      // Get user details for these firebase_uids
      final users = await _client
          .from('users')
          .select('email, display_name, photo_url, college_id')
          .filter('firebase_uid', 'in', followerIds);
          
      return List<Map<String, dynamic>>.from(users);
    } catch (e) {
      debugPrint('Error fetching followers: $e');
      return [];
    }
  }



  /// List students for a college, based on email domain.
  ///
  /// Used by the "Explore Students" screen.
  /// It returns users whose email ends with the college's domain.
  /// collegeIdOrDomain can be either a college UUID id or the domain string directly
  Future<List<Map<String, dynamic>>> getCollegeStudents(String collegeIdOrDomain) async {
    try {
      String? domain;
      
      // Check if input looks like a UUID (college id) or a domain
      final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(collegeIdOrDomain);
      
      if (isUuid) {
        // Fetch college domain by ID
        final college = await _client
            .from('colleges')
            .select('domain')
            .eq('id', collegeIdOrDomain)
            .maybeSingle();
        domain = college?['domain'] as String?;
      } else {
        // Input is already a domain (e.g., "kiet.edu")
        domain = collegeIdOrDomain;
      }

      if (domain == null || domain.isEmpty) {
        debugPrint('No domain found for: $collegeIdOrDomain');
        return [];
      }

      // Get current user email to exclude them
      final currentUserEmail = _client.auth.currentUser?.email;

      final response = await _client
          .from('users')
          .select('email, display_name, photo_url')
          .ilike('email', '%@$domain')
          .order('created_at', ascending: false)
          .limit(50);

      // Filter out current user
      final users = List<Map<String, dynamic>>.from(response);
      if (currentUserEmail != null) {
        users.removeWhere((u) => u['email'] == currentUserEmail);
      }
      
      return users;
    } catch (e) {
      debugPrint('Error fetching college students: $e');
      return [];
    }
  }

  // ============ EMOJI REACTIONS ============


  // ============ REACTIONS ============

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
      
      return {
        'reactions': grouped,
        'total': response.length,
      };
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
      final exists = await _client
          .from('comment_reactions')
          .select('id')
          .eq('comment_id', commentId)
          .eq('comment_type', commentType)
          .eq('user_email', userEmail)
          .eq('emoji', emoji)
          .maybeSingle() != null;

      if (exists) {
        await removeReaction(commentId: commentId, userEmail: userEmail, emoji: emoji);
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

  /// Remove a reaction from a comment
  Future<void> removeReaction({
    required String commentId,
    required String userEmail,
    required String emoji,
  }) async {
    try {
      await _client
          .from('comment_reactions')
          .delete()
          .eq('comment_id', commentId)
          .eq('user_email', userEmail)
          .eq('emoji', emoji);
    } catch (e) {
      debugPrint('Error removing reaction: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getNotices({required String collegeId}) async {
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
        
        if (parentId == null || parentId.isEmpty) { // Handle empty string same as null
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


  Future<List<Resource>> getBookmarks(String userEmail, String collegeId) async {
    try {
      final response = await _api.getBookmarks();
      final List<dynamic> bookmarks = response['bookmarks'] ?? [];
      
      // Filter to only resource bookmarks and convert to Resource objects
      final resources = <Resource>[];
      for (final bookmark in bookmarks) {
        if (bookmark['type'] == 'resource' && bookmark['content'] != null) {
          try {
            resources.add(Resource.fromJson(bookmark['content']));
          } catch (e) {
            debugPrint('Error parsing bookmarked resource: $e');
          }
        }
      }
      return resources;
    } catch (e) {
      debugPrint('Error fetching bookmarks: $e');
      return [];
    }
  }

  Future<bool> isBookmarked(String userEmail, String resourceId) async {
    try {
      return await _api.checkBookmark(resourceId);
    } catch (e) {
      debugPrint('Error checking bookmark: $e');
      return false;
    }
  }

  Future<bool> toggleBookmark(String userEmail, String resourceId) async {
    try {
      // Check if already bookmarked
      final isCurrentlyBookmarked = await _api.checkBookmark(resourceId);
      
      if (isCurrentlyBookmarked) {
        // Remove bookmark
        await _api.removeBookmarkByItem(itemId: resourceId, context: _ctx);
        return false;
      } else {
        // Add bookmark
        await _api.addBookmark(
          itemId: resourceId, 
          type: 'resource', 
          context: _ctx
        );
        return true;
      }
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getChatRooms(String userEmail, String collegeId) async {
    try {
      final response = await _client
          .from('chat_rooms')
          .select('*, member_count:room_members(count)')
          .eq('college_id', collegeId)
          .order('created_at', ascending: false);
      
      return (response as List).map((e) {
        final data = Map<String, dynamic>.from(e);
        // Fix count format if it comes as list
        final countVal = data['member_count'];
        if (countVal is List && countVal.isNotEmpty) {
           data['member_count'] = countVal[0]['count'];
        } else if (countVal is int) {
           data['member_count'] = countVal;
        } else {
           data['member_count'] = 0;
        }
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Error fetching chat rooms: $e');
      return [];
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

  // ============ USER PROFILE ============
  
  /// Get user stats (upload count)
  Future<Map<String, int>> getUserStats(String userEmail) async {
    try {
      final uploads = await _client
          .from('resources')
          .count(CountOption.exact)
          .eq('uploaded_by_email', userEmail)
          .eq('status', 'approved');
      
      return {'uploads': uploads};
    } catch (e) {
      debugPrint('Error fetching user stats: $e');
      return {'uploads': 0};
    }
  }

  /// Get all resources uploaded by a user
  Future<List<Resource>> getUserResources(
    String userEmail, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _client
          .from('resources')
          .select()
          .eq('uploaded_by_email', userEmail)
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      
      return (response as List)
          .map((json) => Resource.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching user resources: $e');
      rethrow;
    }
  }
}
