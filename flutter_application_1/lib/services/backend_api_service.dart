import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Backend API client (same pattern as Studyspace/src/lib/api.ts).
///
/// Use this for ALL privileged writes (create room, post, comment, upload, profile update).
/// This avoids client-side Supabase inserts that fail under RLS with anon key.
class BackendApiService {
  BackendApiService({FirebaseAuth? firebaseAuth})
    : _firebaseAuthInstance = firebaseAuth;

  FirebaseAuth get _auth => _firebaseAuthInstance ?? FirebaseAuth.instance;
  final FirebaseAuth? _firebaseAuthInstance;

  static const Duration _requestTimeout = Duration(seconds: 30);

  List<String> get _baseUrls => AppConfig.apiBaseUrls;

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
    Map<String, String>? customHeaders,
  }) async {
    final token = await _getIdToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    if (customHeaders != null) {
      headers.addAll(customHeaders);
    }

    Map<String, dynamic>? effectiveBody = body == null
        ? null
        : Map<String, dynamic>.from(body);

    Object? lastError;
    final baseUrls = _baseUrls;

    for (var i = 0; i < baseUrls.length; i++) {
      final baseUrl = baseUrls[i];
      final uri = Uri.parse('$baseUrl$path');
      final hasNextBaseUrl = i < baseUrls.length - 1;

      try {
        final res = await _sendRequest(
          uri: uri,
          method: method,
          headers: headers,
          body: effectiveBody,
        ).timeout(_requestTimeout);

        if (res.statusCode >= 200 && res.statusCode < 300) {
          return _decodeJsonBody(res);
        }

        final msg = _responseErrorMessage(res);
        if (hasNextBaseUrl && _shouldTryNextHost(res.statusCode)) {
          debugPrint(
            '[BackendApi] $method $uri failed (${res.statusCode}), '
            'trying next host. Reason: $msg',
          );
          continue;
        }
        throw Exception(msg);
      } on TimeoutException catch (e) {
        lastError = e;
        if (hasNextBaseUrl) {
          debugPrint(
            '[BackendApi] timeout for $method $uri, trying next host.',
          );
          continue;
        }
        throw Exception('Backend request timed out for $uri');
      } on SocketException catch (e) {
        lastError = e;
        if (hasNextBaseUrl) {
          debugPrint(
            '[BackendApi] network error for $method $uri, '
            'trying next host: $e',
          );
          continue;
        }
        throw Exception('Network error while reaching backend: $e');
      } on http.ClientException catch (e) {
        lastError = e;
        if (hasNextBaseUrl) {
          debugPrint(
            '[BackendApi] client error for $method $uri, '
            'trying next host: $e',
          );
          continue;
        }
        throw Exception('HTTP client error while reaching backend: $e');
      }
    }

    if (lastError != null) {
      throw Exception('Unable to reach backend: $lastError');
    }
    throw Exception('Backend request failed before any response was received');
  }

  bool _shouldTryNextHost(int statusCode) {
    return statusCode >= 500;
  }

  Future<http.Response> _sendRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Map<String, dynamic>? body,
  }) {
    switch (method.toUpperCase()) {
      case 'POST':
        return http.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? <String, dynamic>{}),
        );
      case 'PUT':
        return http.put(
          uri,
          headers: headers,
          body: jsonEncode(body ?? <String, dynamic>{}),
        );
      case 'DELETE':
        if (body != null) {
          return http.delete(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
        }
        return http.delete(uri, headers: headers);
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }
  }

  Map<String, dynamic> _decodeJsonBody(http.Response res) {
    final trimmed = res.body.trim();
    if (trimmed.isEmpty) {
      return <String, dynamic>{};
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (e) {
      throw Exception('Invalid JSON response (${res.statusCode}): $e');
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    if (decoded is List) {
      return <String, dynamic>{'data': decoded};
    }

    throw Exception('Invalid API response (${res.statusCode}): ${res.body}');
  }

  String _responseErrorMessage(http.Response res) {
    try {
      final data = _decodeJsonBody(res);
      return data['message']?.toString() ??
          data['error']?.toString() ??
          'API request failed (${res.statusCode})';
    } catch (_) {
      return 'API request failed (${res.statusCode}): ${res.body}';
    }
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
        if (description != null) 'description': description,
        'isPrivate': isPrivate,
        'collegeId': collegeId,
        if (durationInDays != null) 'durationInDays': durationInDays,
        if (tags != null) 'tags': tags,
      },
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
        if (authorName != null) 'authorName': authorName,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getChatComments(String messageId) async {
    final data = await _requestJson(
      '/api/chat/comments/${Uri.encodeComponent(messageId)}',
      method: 'GET',
    );
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
      body: {'messageId': messageId, 'roomId': roomId},
    );
  }

  Future<void> deleteChatComment({
    required String commentId,
    BuildContext? context,
  }) async {
    await _requestJson(
      '/api/chat/comments/${Uri.encodeComponent(commentId)}',
      method: 'DELETE',
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
    return _requestJson('/api/resources', method: 'POST', body: input);
  }

  Future<Map<String, dynamic>> castVote({
    required String resourceId,
    required String voteType,
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/votes',
      method: 'POST',
      body: {'resourceId': resourceId, 'voteType': voteType},
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
      body: {'itemId': itemId, 'type': type},
    );
  }

  Future<void> removeBookmarkByItem({
    required String itemId,
    BuildContext? context,
  }) async {
    await _requestJson(
      '/api/bookmarks/item/${Uri.encodeComponent(itemId)}',
      method: 'DELETE',
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
    final data = await _requestJson(
      '/api/notices?college_id=${Uri.encodeQueryComponent(collegeId)}',
      method: 'GET',
    );
    final list = (data['notices'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  // ----------------------------
  // Notice comments
  // ----------------------------

  Future<List<Map<String, dynamic>>> getNoticeComments(String noticeId) async {
    final data = await _requestJson(
      '${_noticePath(noticeId)}/comments',
      method: 'GET',
    );
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
      body: {'content': content, if (parentId != null) 'parentId': parentId},
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
    );
  }

  Future<Map<String, dynamic>> likeNotice({
    required String noticeId,
    required BuildContext context,
  }) async {
    return _requestJson('${_noticePath(noticeId)}/like', method: 'POST');
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
    String? bio,
    String? profilePhotoUrl,
    String? collegeId,
    String? semester,
    String? branch,
    String? adminKey,
    required BuildContext context,
  }) async {
    final payload = <String, dynamic>{};
    if (displayName != null) payload['display_name'] = displayName;
    if (bio != null) payload['bio'] = bio;
    if (profilePhotoUrl != null) payload['profile_photo_url'] = profilePhotoUrl;
    if (collegeId != null) payload['college_id'] = collegeId;
    if (semester != null) payload['semester'] = semester;
    if (branch != null) payload['branch'] = branch;

    final customHeaders = <String, String>{};
    if (adminKey != null && adminKey.isNotEmpty) {
      customHeaders['X-Admin-Key'] = adminKey;
    }

    return _requestJson(
      '/api/users/profile',
      method: 'PUT',
      body: payload,
      customHeaders: customHeaders.isEmpty ? null : customHeaders,
    );
  }

  Future<Map<String, dynamic>> updateResourceStatus({
    required String resourceId,
    required String status,
    required String adminKey,
    required BuildContext context,
  }) async {
    const allowedStatuses = {'approved', 'rejected', 'pending'};
    final normalizedStatus = status.toLowerCase();
    if (!allowedStatuses.contains(normalizedStatus)) {
      throw ArgumentError('Invalid status: $status. Must be one of $allowedStatuses');
    }

    return _requestJson(
      '/api/admin',
      method: 'POST',
      body: {
        'action': 'update_resource_status',
        'admin_key': adminKey,
        'resource_id': resourceId,
        'new_status': normalizedStatus,
      }
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
      body: {'amount': amount, 'planId': planId},
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

  Future<Map<String, dynamic>> joinChatRoom(
    String code,
    String userEmail,
    String collegeId,
  ) async {
    return _requestJson(
      '/api/chat/join',
      method: 'POST',
      body: {'code': code, 'userEmail': userEmail, 'collegeId': collegeId},
    );
  }

  Future<Map<String, dynamic>> getUserVotes(String roomId) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/votes',
      method: 'GET',
    );
  }

  // Reporting
  Future<void> reportPost(
    String postId,
    String reason,
    String reporterId, {
    String type = 'post',
  }) async {
    final payload = <String, dynamic>{
      'postId': postId,
      'reason': reason,
      'reporterId': reporterId,
      'reportType': type,
    };

    try {
      await _requestJson('/api/reports', method: 'POST', body: payload);
    } catch (primaryError) {
      debugPrint(
        '[BackendApi] /api/reports failed, retrying /api/chat/reports: '
        '$primaryError',
      );
      await _requestJson('/api/chat/reports', method: 'POST', body: payload);
    }
  }

  Future<void> reportComment(
    String commentId,
    String reason,
    String reporterId,
  ) async {
    return reportPost(commentId, reason, reporterId, type: 'comment');
  }
  // ----------------------------
  // Notifications & Follows
  // ----------------------------

  Future<List<Map<String, dynamic>>> getNotifications({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final data = await _requestJson(
        '/api/notifications?limit=$limit&offset=$offset',
        method: 'GET',
      );
      final list = (data['notifications'] as List?) ?? const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Backend /api/notifications query failed. Bubbling up: $e');
      rethrow;
    }
  }

  Future<void> markNotificationRead(
    Object id, {
    BuildContext? contextForRecaptcha,
  }) async {
    await _requestJson(
      '/api/notifications/${Uri.encodeComponent(id.toString())}/read',
      method: 'POST',
    );
  }

  Future<void> markAllNotificationsRead({
    BuildContext? contextForRecaptcha,
  }) async {
    await _requestJson('/api/notifications/read-all', method: 'POST');
  }

  Future<void> deleteNotification(
    Object id, {
    BuildContext? contextForRecaptcha,
  }) async {
    await _requestJson(
      '/api/notifications/${Uri.encodeComponent(id.toString())}',
      method: 'DELETE',
    );
  }

  // ----------------------------
  // Comment Reactions (Emoji)
  // ----------------------------

  Future<Map<String, dynamic>> getCommentReactions({
    required String commentId,
    required String commentType,
  }) async {
    final query = Uri(
      queryParameters: {'commentId': commentId, 'commentType': commentType},
    ).query;
    return _requestJson('/api/reactions/comments?$query', method: 'GET');
  }

  Future<bool> toggleCommentReaction({
    required String commentId,
    required String commentType,
    required String emoji,
    required BuildContext context,
  }) async {
    final data = await _requestJson(
      '/api/reactions/comments/toggle',
      method: 'POST',
      body: {
        'commentId': commentId,
        'commentType': commentType,
        'emoji': emoji,
      },
    );

    return data['added'] == true;
  }

  // Follows
  Future<void> sendFollowRequest(
    String targetEmail,
    BuildContext context,
  ) async {
    await _requestJson(
      '/api/follow/request', // Corrected from /api/follows/requests
      method: 'POST',
      body: {
        'targetEmail': targetEmail,
      }, // Changed targetId to targetEmail per API
    );
  }

  Future<void> acceptFollowRequest(
    int requestId, {
    BuildContext? context,
  }) async {
    await _requestJson(
      '/api/follow/approve/${requestId.toString()}', // Corrected endpoint
      method: 'POST',
    );
  }

  Future<void> rejectFollowRequest(
    int requestId, {
    BuildContext? context,
  }) async {
    await _requestJson(
      '/api/follow/reject/${requestId.toString()}', // Corrected endpoint
      method: 'POST',
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
    String? fileId,
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
        if (fileId != null) 'file_id': fileId,
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
      body: {'token': token, 'platform': platform},
      // Recaptcha context removed as it cannot be a string
    );
  }

  /// Delete FCM token (on logout)
  Future<void> deleteFcmToken(String token) async {
    await _requestJson(
      '/api/notifications/fcm-token',
      method: 'DELETE',
      body: {'token': token},
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
    return _requestJson(
      '/api/follow/status/${Uri.encodeComponent(email)}',
      method: 'GET',
    );
  }

  Future<Map<String, dynamic>> getFollowers() async {
    return _requestJson('/api/follow/followers', method: 'GET');
  }

  Future<Map<String, dynamic>> getFollowing() async {
    return _requestJson('/api/follow/following', method: 'GET');
  }

  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    try {
      final data = await _requestJson('/api/follow/pending', method: 'GET');
      final list = (data['requests'] as List?) ?? const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Backend /api/follow/pending query failed: $e');
      rethrow;
    }
  }

  Future<void> unfollowUser(String email, {BuildContext? context}) async {
    await _requestJson(
      '/api/follow/${Uri.encodeComponent(email)}',
      method: 'DELETE',
    );
  }

  Future<void> cancelFollowRequest(String requestId) async {
    await _requestJson(
      '/api/follow/request/${Uri.encodeComponent(requestId)}',
      method: 'DELETE',
    );
  }
}
