import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../config/app_config.dart';

/// Backend API client (same pattern as Studyspace/src/lib/api.ts).
///
/// Use this for ALL privileged writes (create room, post, comment, upload, profile update).
/// This avoids client-side Supabase inserts that fail under RLS with anon key.
class BackendApiService {
  BackendApiService({FirebaseAuth? firebaseAuth}) : _auth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  String get _baseUrl => AppConfig.apiUrl; // e.g. https://studyspace-backend.onrender.com

  Future<String?> _getIdToken() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken();
    } catch (e) {
      debugPrint('[BackendApi] token error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _requestJson(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    BuildContext? contextForRecaptcha,
    String recaptchaAction = 'mobile_write',
  }) async {
    final token = await _getIdToken();
    final uri = Uri.parse('$_baseUrl$path');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    // Attach reCAPTCHA token for privileged writes (POST/PUT/DELETE) if context provided.
    // TEMPORARILY DISABLED: reCAPTCHA requires Android package registration in Google Cloud Console.
    // To re-enable: uncomment the block below after registering package name.
    Map<String, dynamic>? effectiveBody = body == null ? null : Map<String, dynamic>.from(body);
    // final m = method.toUpperCase();
    // final needsBody = m == 'POST' || m == 'PUT' || m == 'DELETE';
    // if (needsBody && contextForRecaptcha != null) {
    //   try {
    //     final recaptchaToken = await RecaptchaService.getToken(
    //       contextForRecaptcha,
    //       action: recaptchaAction,
    //     );
    //     effectiveBody ??= <String, dynamic>{};
    //     effectiveBody['recaptchaToken'] = recaptchaToken;
    //   } catch (e) {
    //     // If recaptcha fails, block the request (security-first).
    //     throw Exception('Security check failed. Please try again.');
    //   }
    // }

    late http.Response res;
    switch (method.toUpperCase()) {
      case 'POST':
        res = await http.post(uri, headers: headers, body: jsonEncode(effectiveBody ?? {}));
        break;
      case 'PUT':
        res = await http.put(uri, headers: headers, body: jsonEncode(effectiveBody ?? {}));
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: headers, body: jsonEncode(effectiveBody ?? {}));
        break;
      default:
        res = await http.get(uri, headers: headers);
        break;
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('API error (${res.statusCode}): ${res.body}');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = data['message']?.toString() ?? data['error']?.toString() ?? 'API request failed';
      throw Exception(msg);
    }
    return data;
  }

  // ----------------------------
  // Chat (Rooms / Messages / Comments)
  // ----------------------------

  Future<Map<String, dynamic>> createChatRoom({
    required String name,
    String? description,
    required bool isPrivate,
    required String collegeId,
    required BuildContext context,
    int? durationInDays,
    List<String>? tags,
  }) async {
    return _requestJson(
      '/api/chat/rooms',
      method: 'POST',
      body: {
        'name': name,
        'description': description,
        'isPrivate': isPrivate,
        'collegeId': collegeId,

        if (durationInDays != null) 'durationInDays': durationInDays,
        if (tags != null) 'tags': tags,
      },
      contextForRecaptcha: context,
      recaptchaAction: 'create_chat_room',
    );
  }

  /// Leave a chat room
  Future<Map<String, dynamic>> leaveChatRoom({
    required String roomId,
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/leave',
      method: 'POST',
      contextForRecaptcha: context,
      recaptchaAction: 'leave_chat_room',
    );
  }

  Future<Map<String, dynamic>> postChatMessage({
    required String roomId,
    required String content,
    String? imageUrl,
    String? authorName,
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/chat/messages',
      method: 'POST',
      body: {
        'roomId': roomId,
        'content': content,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (authorName != null) 'authorName': authorName,      },
      contextForRecaptcha: context,
      recaptchaAction: 'post_chat_message',
    );  }

  Future<List<Map<String, dynamic>>> getChatComments(String messageId) async {
    final data = await _requestJson('/api/chat/comments/${Uri.encodeComponent(messageId)}', method: 'GET');
    final list = (data['comments'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> voteChatMessage({
    required String messageId,
    required String direction, // 'up' or 'down'
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/chat/messages/${Uri.encodeComponent(messageId)}/vote',
      method: 'PUT',
      body: {'direction': direction},
      contextForRecaptcha: context,
      recaptchaAction: 'vote_chat_message',
    );
  }

  Future<Map<String, dynamic>> toggleSaveChatMessage({
    required String messageId,
    required String roomId,
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/chat/saved',
      method: 'POST',
      body: {
        'messageId': messageId,
        'roomId': roomId,
      },
      contextForRecaptcha: context,
      recaptchaAction: 'save_chat_message',
    );
  }

  Future<void> deleteChatComment({
    required String commentId,
    required BuildContext context,
  }) async {
    await _requestJson(
      '/api/chat/comments/$commentId',
      method: 'DELETE',
      contextForRecaptcha: context,
      recaptchaAction: 'delete_chat_comment',
    );
  }

  Future<Map<String, dynamic>> addChatComment({
    required String messageId,
    required String content,
    String? authorName,
    String? parentId,
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/chat/comments',
      method: 'POST',
      body: {
        'messageId': messageId,
        'content': content,
        if (authorName != null) 'authorName': authorName,
        if (parentId != null) 'parentId': parentId,
      },
      contextForRecaptcha: context,
      recaptchaAction: 'post_chat_message',
    );
  }

  // ----------------------------
  // Resources
  // ----------------------------

  Future<Map<String, dynamic>> getResourceUploadUrl({
    required String filename,
  }) async {
    return _requestJson(
      '/api/resources/upload-url',
      method: 'POST',
      body: {'filename': filename},
    );
  }

  Future<Map<String, dynamic>> createResource(
    Map<String, dynamic> input, {
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/resources',
      method: 'POST',
      body: input,
      contextForRecaptcha: context,
      recaptchaAction: 'create_resource',
    );
  }

  Future<Map<String, dynamic>> castVote({
    required String resourceId,
    required String voteType,
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/votes',
      method: 'POST',
      body: {
        'resourceId': resourceId,
        'voteType': voteType,
      },
      contextForRecaptcha: context,
      recaptchaAction: 'cast_vote',
    );
  }

  Future<Map<String, dynamic>> getVoteStatus(String resourceId) async {
    return _requestJson('/api/votes/$resourceId', method: 'GET');
  }

  Future<Map<String, dynamic>> getBookmarks() async {
    return _requestJson('/api/bookmarks', method: 'GET');
  }

  Future<Map<String, dynamic>> addBookmark({
    required String itemId,
    required String type, // 'resource' or 'notice'
    BuildContext? context,
  }) async {
    return _requestJson(
      '/api/bookmarks',
      method: 'POST',
      body: {
        'itemId': itemId,
        'type': type,
      },
      contextForRecaptcha: context,
      recaptchaAction: 'add_bookmark',
    );
  }

  Future<void> removeBookmarkByItem({
    required String itemId,
    BuildContext? context,
  }) async {
    await _requestJson(
      '/api/bookmarks/item/${Uri.encodeComponent(itemId)}',
      method: 'DELETE',
      contextForRecaptcha: context,
      recaptchaAction: 'remove_bookmark',
    );
  }

  Future<bool> checkBookmark(String itemId) async {
    try {
      final data = await _requestJson(
        '/api/bookmarks/check/${Uri.encodeComponent(itemId)}',
        method: 'GET',
      );
      return data['isBookmarked'] == true;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------
  // Notices
  // ----------------------------

  String _noticePath(String noticeId, {String? commentId}) {
    final path = '/api/notices/${Uri.encodeComponent(noticeId)}';
    if (commentId != null) {
      return '$path/comments/${Uri.encodeComponent(commentId)}';
    }
    return path;
  }

  Future<List<Map<String, dynamic>>> getNotices(String collegeId) async {
    final data = await _requestJson('/api/notices?college_id=${Uri.encodeQueryComponent(collegeId)}', method: 'GET');
    final list = (data['notices'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  // ----------------------------
  // Notice comments
  // ----------------------------

  Future<List<Map<String, dynamic>>> getNoticeComments(String noticeId) async {
    final data = await _requestJson('${_noticePath(noticeId)}/comments', method: 'GET');
    final list = (data['comments'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> postNoticeComment({
    required String noticeId,
    required String content,
    String? parentId,
    required BuildContext context,
  }) async {
    return _requestJson(
      '${_noticePath(noticeId)}/comments',
      method: 'POST',
      body: {
        'content': content,
        if (parentId != null) 'parentId': parentId,
      },
      contextForRecaptcha: context,
      recaptchaAction: 'post_notice_comment',
    );
  }

  Future<void> deleteNoticeComment({
    required String noticeId,
    required String commentId,
    required BuildContext context,
  }) async {
    await _requestJson(
      _noticePath(noticeId, commentId: commentId),
      method: 'DELETE',
      contextForRecaptcha: context,
      recaptchaAction: 'delete_notice_comment',
    );
  }

  Future<Map<String, dynamic>> likeNotice({
    required String noticeId,
    required BuildContext context,
  }) async {
    return _requestJson(
      '${_noticePath(noticeId)}/like',
      method: 'POST',
      contextForRecaptcha: context,
      recaptchaAction: 'like_notice',
    );
  }

  Future<Map<String, dynamic>> getNoticeLikes(String noticeId) async {
    return _requestJson('${_noticePath(noticeId)}/likes', method: 'GET');
  }

  Future<Map<String, dynamic>> likeNoticeComment({
    required String noticeId,
    required String commentId,
    required BuildContext context,
  }) async {
    return _requestJson(
      '${_noticePath(noticeId, commentId: commentId)}/like',
      method: 'POST',
      contextForRecaptcha: context,
      recaptchaAction: 'like_notice_comment',
    );
  }

  // ----------------------------
  // Profile
  // ----------------------------

  Future<Map<String, dynamic>> getProfile() async {
    return _requestJson('/api/users/profile', method: 'GET');
  }

  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? username,
    String? bio,
    String? profilePhotoUrl,
    String? college,
    String? branch,
    String? semester,
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/users/profile',
      method: 'PUT',
      body: {
        if (displayName != null) 'display_name': displayName,
        if (username != null) 'username': username,
        if (bio != null) 'bio': bio,
        if (profilePhotoUrl != null) 'profile_photo_url': profilePhotoUrl,
        if (college != null) 'college': college,
        if (branch != null) 'branch': branch,
        if (semester != null) 'semester': semester,
      },
      contextForRecaptcha: context,
      recaptchaAction: 'update_profile',
    );
  }

  // ----------------------------
  // Payments
  // ----------------------------

  Future<Map<String, dynamic>> createPaymentOrder({
    required int amount,
    required String planId,
    BuildContext? context,
  }) async {
    return _requestJson(
      '/api/payments/order', 
      method: 'POST',
      body: {
        'amount': amount,
        'planId': planId,
      },
      contextForRecaptcha: context,
      recaptchaAction: 'create_payment_order',
    );
  }

  Future<Map<String, dynamic>> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    return _requestJson(
      '/api/payments/verify', 
      method: 'POST',
      body: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      },
    );
  }
  // ----------------------------
  // Chat
  // ----------------------------

  Future<Map<String, dynamic>> joinChatRoom(String code, String? userEmail, String collegeId) async {
    return _requestJson(
      '/api/chat/join',
      method: 'POST',
      body: {
        'code': code,
        'collegeId': collegeId,
      },
    );
  }

  Future<Map<String, dynamic>> getUserVotes(String roomId) async {
    return _requestJson('/api/chat/rooms/${Uri.encodeComponent(roomId)}/votes', method: 'GET');
  }

  // Reporting
  Future<void> reportPost(String postId, String reason, String reporterId, {String type = 'post'}) async {
    await _requestJson(
      '/api/reports',
      method: 'POST',
      body: {
        'postId': postId,
        'reason': reason,
        'reporterId': reporterId,
        'reportType': type,
      },
    );
  }
  // ----------------------------
  // Notifications & Follows
  // ----------------------------

  Future<List<Map<String, dynamic>>> getNotifications({int limit = 20, int offset = 0}) async {
    final data = await _requestJson('/api/notifications?limit=$limit&offset=$offset', method: 'GET');
    final list = (data['notifications'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> markNotificationRead(int id, {BuildContext? contextForRecaptcha}) async {
    await _requestJson(
      '/api/notifications/$id/read',
      method: 'POST',
      contextForRecaptcha: contextForRecaptcha,
      recaptchaAction: 'mark_notification_read',
    );
  }

  Future<void> markAllNotificationsRead({BuildContext? contextForRecaptcha}) async {
    await _requestJson(
      '/api/notifications/read-all',
      method: 'POST',
      contextForRecaptcha: contextForRecaptcha,
      recaptchaAction: 'mark_all_notifications_read',
    );
  }

  Future<void> deleteNotification(int id, {BuildContext? contextForRecaptcha}) async {
    await _requestJson(
      '/api/notifications/$id',
      method: 'DELETE',
      contextForRecaptcha: contextForRecaptcha,
      recaptchaAction: 'delete_notification',
    );
  }

  // Follows
  Future<void> sendFollowRequest(String targetEmail, BuildContext context) async {
    await _requestJson(
        '/api/follow/request', // Corrected from /api/follows/requests
        method: 'POST', 
        body: {'targetEmail': targetEmail}, // Changed targetId to targetEmail per API
        contextForRecaptcha: context,
        recaptchaAction: 'follow_user'
    );
  }

  Future<void> acceptFollowRequest(int requestId, {BuildContext? context}) async {
    await _requestJson(
      '/api/follow/approve/${requestId.toString()}', // Corrected endpoint
      method: 'POST',
      contextForRecaptcha: context,
      recaptchaAction: 'accept_follow_request',
    );
  }
  
  Future<void> rejectFollowRequest(int requestId, {BuildContext? context}) async {
    await _requestJson(
      '/api/follow/reject/${requestId.toString()}', // Corrected endpoint
      method: 'POST',
      contextForRecaptcha: context,
      recaptchaAction: 'reject_follow_request',
    );
  }

  Future<List<Map<String, dynamic>>> getSavedPosts() async {
    final data = await _requestJson('/api/chat/saved', method: 'GET');
    final list = (data['savedPosts'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ----------------------------
  // AI (Study Tools + RAG Chat)
  // ----------------------------

  Future<Map<String, dynamic>> getAiSummary({
    required String fileId,
    String? collegeId,
    bool? useOcr,
    bool? forceOcr,
    String? ocrProvider,
    bool? force,
    bool? includeSource,
    String? videoUrl,
  }) async {
    return _requestJson(
      '/api/ai/summary',
      method: 'POST',
      body: {
        'file_id': fileId,
        if (collegeId != null) 'college_id': collegeId,
        if (useOcr != null) 'use_ocr': useOcr,
        if (forceOcr != null) 'force_ocr': forceOcr,
        if (ocrProvider != null) 'ocr_provider': ocrProvider,
        if (force != null) 'force': force,
        if (includeSource != null) 'include_source': includeSource,
        if (videoUrl != null) 'video_url': videoUrl,
      },
    );
  }

  Future<Map<String, dynamic>> getAiQuiz({
    required String fileId,
    String? collegeId,
    bool? useOcr,
    bool? forceOcr,
    String? ocrProvider,
    bool? force,
    bool? includeSource,
    String? videoUrl,
  }) async {
    return _requestJson(
      '/api/ai/quiz',
      method: 'POST',
      body: {
        'file_id': fileId,
        if (collegeId != null) 'college_id': collegeId,
        if (useOcr != null) 'use_ocr': useOcr,
        if (forceOcr != null) 'force_ocr': forceOcr,
        if (ocrProvider != null) 'ocr_provider': ocrProvider,
        if (force != null) 'force': force,
        if (includeSource != null) 'include_source': includeSource,
        if (videoUrl != null) 'video_url': videoUrl,
      },
    );
  }

  Future<Map<String, dynamic>> getAiFlashcards({
    required String fileId,
    String? collegeId,
    bool? useOcr,
    bool? forceOcr,
    String? ocrProvider,
    bool? force,
    bool? includeSource,
    String? videoUrl,
  }) async {
    return _requestJson(
      '/api/ai/flashcards',
      method: 'POST',
      body: {
        'file_id': fileId,
        if (collegeId != null) 'college_id': collegeId,
        if (useOcr != null) 'use_ocr': useOcr,
        if (forceOcr != null) 'force_ocr': forceOcr,
        if (ocrProvider != null) 'ocr_provider': ocrProvider,
        if (force != null) 'force': force,
        if (includeSource != null) 'include_source': includeSource,
        if (videoUrl != null) 'video_url': videoUrl,
      },
    );
  }

  Future<Map<String, dynamic>> findInAiText({
    required String fileId,
    required String query,
    String? collegeId,
    bool? useOcr,
    bool? forceOcr,
    String? ocrProvider,
  }) async {
    return _requestJson(
      '/api/ai/find',
      method: 'POST',
      body: {
        'file_id': fileId,
        'query': query,
        if (collegeId != null) 'college_id': collegeId,
        if (useOcr != null) 'use_ocr': useOcr,
        if (forceOcr != null) 'force_ocr': forceOcr,
        if (ocrProvider != null) 'ocr_provider': ocrProvider,
      },
    );
  }

  Future<Map<String, dynamic>> queryRag({
    required String question,
    String? collegeId,
    int? topK,
    double? minScore,
    bool? allowWeb,
  }) async {
    return _requestJson(
      '/api/rag/query',
      method: 'POST',
      body: {
        'question': question,
        if (collegeId != null) 'college_id': collegeId,
        if (topK != null) 'top_k': topK,
        if (minScore != null) 'min_score': minScore,
        if (allowWeb != null) 'allow_web': allowWeb,
      },
    );
  }
  // ----------------------------
  // Push Notifications (FCM)
  // ----------------------------

  /// Register FCM token for push notifications
  Future<void> registerFcmToken({
    required String token,
    required String platform, // 'ios' or 'android'
  }) async {
    await _requestJson(
      '/api/notifications/fcm-token',
      method: 'POST',
      body: {
        'token': token,
        'platform': platform,
      },
      // Recaptcha context removed as it cannot be a string
    );
  }

  /// Delete FCM token (on logout)
  Future<void> deleteFcmToken(String token) async {
    await _requestJson(
      '/api/notifications/fcm-token',
      method: 'DELETE',
      body: {
        'token': token,
      },
      // Recaptcha context removed
    );
  }
  Future<Map<String, dynamic>> joinChatRoomById(String roomId) async {
    return _requestJson(
      '/api/chat/join-room',
      method: 'POST',
      body: {'roomId': roomId},
    );
  }

  // ----------------------------
  // Follows & Users
  // ----------------------------

  Future<Map<String, dynamic>> checkFollowStatus(String email) async {
    // Corrected endpoint
    return _requestJson('/api/follow/status/${Uri.encodeComponent(email)}', method: 'GET');
  }
  Future<Map<String, dynamic>> getFollowers() async {
    return _requestJson('/api/follow/followers', method: 'GET');
  }

  Future<Map<String, dynamic>> getFollowing() async {
    return _requestJson('/api/follow/following', method: 'GET');
  }

  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final data = await _requestJson('/api/follow/pending', method: 'GET');
    final list = (data['requests'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> unfollowUser(String email, {BuildContext? context}) async {
    await _requestJson(
      '/api/follow/${Uri.encodeComponent(email)}',
      method: 'DELETE',
      contextForRecaptcha: context,
      recaptchaAction: 'unfollow_user',
    );
  }

  Future<void> cancelFollowRequest(String requestId) async {
    await _requestJson('/api/follow/request/${Uri.encodeComponent(requestId)}', method: 'DELETE');
  }
}
