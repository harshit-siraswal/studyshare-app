import 'dart:convert';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../config/app_config.dart';

/// Backend API client (same pattern as Studyspace/src/lib/api.ts).
///
/// Use this for ALL privileged writes (create room, post, comment, upload, profile update).
/// This avoids client-side Supabase inserts that fail under RLS with anon key.
class BackendApiService {
  BackendApiService({FirebaseAuth? firebaseAuth})
    : _injectedAuth = firebaseAuth;

  final FirebaseAuth? _injectedAuth;
  bool _ragStreamUnavailable = false;
  static final http.Client _httpClient = http.Client();
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _streamRequestTimeout = Duration(seconds: 30);

  FirebaseAuth? get _auth {
    if (_injectedAuth != null) return _injectedAuth;
    try {
      return FirebaseAuth.instance;
    } catch (e) {
      debugPrint('[BackendApi] FirebaseAuth unavailable during startup: $e');
      return null;
    }
  }

  String get _baseUrl =>
      AppConfig.apiUrl; // e.g. https://studyspace-backend.onrender.com

  Future<String?> _getIdToken({bool forceRefresh = false}) async {
    final auth = _auth;
    if (auth == null) return null;

    User? user = auth.currentUser;
    if (user == null) {
      try {
        user = await auth
            .authStateChanges()
            .where((u) => u != null)
            .cast<User>()
            .first
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        return null;
      }
    }

    try {
      return await user.getIdToken(forceRefresh);
    } catch (e) {
      debugPrint('[BackendApi] token error: $e');
      return null;
    }
  }

  Future<http.Response> _sendRequest(
    String method,
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic>? body,
  ) async {
    final encodedBody = jsonEncode(body ?? {});
    final future = switch (method.toUpperCase()) {
      'POST' => _httpClient.post(uri, headers: headers, body: encodedBody),
      'PUT' => _httpClient.put(uri, headers: headers, body: encodedBody),
      'DELETE' => _httpClient.delete(uri, headers: headers, body: encodedBody),
      _ => _httpClient.get(uri, headers: headers),
    };
    return future.timeout(_requestTimeout);
  }

  Future<http.StreamedResponse> _sendStreamedRequest(http.BaseRequest request) {
    return _httpClient.send(request).timeout(_streamRequestTimeout);
  }

  Future<Map<String, dynamic>> _requestJson(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    String? token = await _getIdToken();
    final uri = Uri.parse('$_baseUrl$path');

    var headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    Map<String, dynamic>? effectiveBody = body == null
        ? null
        : Map<String, dynamic>.from(body);

    var res = await _sendRequest(method, uri, headers, effectiveBody);

    if (res.statusCode == 401 || res.statusCode == 403) {
      final refreshedToken = await _getIdToken(forceRefresh: true);
      final shouldRetry =
          refreshedToken != null &&
          refreshedToken.isNotEmpty &&
          refreshedToken != token;
      if (shouldRetry) {
        token = refreshedToken;
        headers = <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        };
        res = await _sendRequest(method, uri, headers, effectiveBody);
      }
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('API error (${res.statusCode}): ${res.body}');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg =
          data['message']?.toString() ??
          data['error']?.toString() ??
          'API request failed';
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
        'description': ?description,
        'isPrivate': isPrivate,
        'collegeId': collegeId,
        'durationInDays': ?durationInDays,
        'tags': ?tags,
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
        'imageUrl': ?imageUrl,
        'authorName': ?authorName,
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
    BuildContext? context,
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
        'authorName': ?authorName,
        'parentId': ?parentId,
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

  Future<Map<String, dynamic>> createNotice({
    required String collegeId,
    required String title,
    required String content,
    String department = 'general',
    String? imageUrl,
  }) async {
    return _requestJson(
      '/api/notices',
      method: 'POST',
      body: {
        // API currently expects imageUrl and fileUrl to match for notice attachments.
        'collegeId': collegeId,
        'title': title,
        'content': content,
        'department': department,
        'imageUrl': ?imageUrl,
        'fileUrl': ?imageUrl,
      },
    );
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
      body: {'content': content, 'parentId': ?parentId},
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
    String? username,
    String? bio,
    String? profilePhotoUrl,
    String? college,
    String? branch,
    String? semester,
    String? subject,
    String? adminKey,
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/users/profile',
      method: 'PUT',
      body: {
        'display_name': ?displayName,
        'username': ?username,
        'bio': ?bio,
        'profile_photo_url': ?profilePhotoUrl,
        'college': ?college,
        'branch': ?branch,
        'semester': ?semester,
        'subject': ?subject,
        'admin_key': ?adminKey,
      },
    );
  }

  // ----------------------------
  // Payments
  // ----------------------------

  Future<Map<String, dynamic>> createPaymentOrder({
    required String planId,
    int? amount,
    BuildContext? context,
  }) async {
    return _requestJson(
      '/api/payments/order',
      method: 'POST',
      body: {'planId': planId, 'amount': ?amount},
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

  Future<int> getUnreadNotificationCount() async {
    final notifications = await getNotifications(limit: 200, offset: 0);
    return notifications.where((notification) {
      final isReadRaw = notification.containsKey('is_read')
          ? notification['is_read']
          : notification['isRead'];
      if (isReadRaw is bool) return !isReadRaw;
      return isReadRaw?.toString().toLowerCase() != 'true';
    }).length;
  }

  Future<void> updateResourceStatus({
    required String resourceId,
    required String status,
    required String adminKey,
    required BuildContext context,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/admin/resources/${Uri.encodeComponent(resourceId)}/status',
    );
    final res = await _httpClient
        .patch(
          uri,
          headers: {
            'Content-Type': 'application/json',
            // Admin endpoints authenticate via bearer admin key/hash.
            'Authorization': 'Bearer $adminKey',
          },
          body: jsonEncode({'status': status}),
        )
        .timeout(_requestTimeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message = 'Failed to update resource status';
      try {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        message =
            data['message']?.toString() ?? data['error']?.toString() ?? message;
      } catch (_) {
        if (res.body.trim().isNotEmpty) {
          message = res.body;
        }
      }
      throw Exception(message);
    }
  }

  Future<void> deleteResourceAsAdmin({
    required String resourceId,
    required String adminKey,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/admin/resources/${Uri.encodeComponent(resourceId)}',
    );
    final res = await _httpClient
        .delete(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $adminKey',
          },
        )
        .timeout(_requestTimeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message = 'Failed to delete resource';
      try {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        message =
            data['message']?.toString() ?? data['error']?.toString() ?? message;
      } catch (_) {
        if (res.body.trim().isNotEmpty) {
          message = res.body;
        }
      }
      throw Exception(message);
    }
  }

  Future<Map<String, dynamic>> banUserAsAdmin({
    required String email,
    required String adminKey,
    String? reason,
    String? collegeId,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/admin/users-ban');
    final res = await _httpClient
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            // Keep parity with admin-studyspace: bearer admin key/hash auth.
            'Authorization': 'Bearer $adminKey',
          },
          body: jsonEncode({
            'email': email.trim().toLowerCase(),
            'reason': ?reason,
            'collegeId': ?collegeId,
          }),
        )
        .timeout(_requestTimeout);

    Map<String, dynamic> data = <String, dynamic>{};
    try {
      final parsed = jsonDecode(res.body);
      if (parsed is Map<String, dynamic>) {
        data = parsed;
      } else if (parsed is Map) {
        data = Map<String, dynamic>.from(parsed);
      }
    } catch (_) {
      // Preserve best-effort message fallback below.
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message =
          data['message']?.toString() ??
          data['error']?.toString() ??
          (res.body.trim().isNotEmpty ? res.body : 'Failed to ban user');
      throw Exception(message);
    }

    return data;
  }

  Future<List<Map<String, dynamic>>> listAdminResources({
    required String adminKey,
    String? collegeId,
    String? status,
    String? semester,
    String? branch,
    String? subject,
    int page = 1,
    int pageSize = 100,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
      if (collegeId != null && collegeId.trim().isNotEmpty)
        'collegeId': collegeId.trim(),
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      if (semester != null && semester.trim().isNotEmpty)
        'semester': semester.trim(),
      if (branch != null && branch.trim().isNotEmpty) 'branch': branch.trim(),
      if (subject != null && subject.trim().isNotEmpty)
        'subject': subject.trim(),
    };

    final uri = Uri.parse(
      '$_baseUrl/api/admin/resources',
    ).replace(queryParameters: queryParams);
    final res = await _httpClient
        .get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $adminKey',
          },
        )
        .timeout(_requestTimeout);

    Map<String, dynamic> data = <String, dynamic>{};
    try {
      final parsed = jsonDecode(res.body);
      if (parsed is Map<String, dynamic>) {
        data = parsed;
      } else if (parsed is Map) {
        data = Map<String, dynamic>.from(parsed);
      }
    } catch (_) {
      // Preserve best-effort fallback below.
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message =
          data['message']?.toString() ??
          data['error']?.toString() ??
          (res.body.trim().isNotEmpty
              ? res.body
              : 'Failed to load admin resources');
      throw Exception(message);
    }

    final resourcesRaw = data['resources'];
    if (resourcesRaw is! List) return const [];
    return resourcesRaw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> uploadSyllabusAsAdmin({
    required String adminKey,
    required String collegeId,
    required String semester,
    required String branch,
    required String subject,
    required String title,
    required String pdfUrl,
    String? academicYear,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/admin');
    final res = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'upload_syllabus',
            'keyHash': adminKey,
            'collegeId': collegeId,
            'semester': semester,
            'branch': branch,
            'subject': subject,
            'title': title,
            'pdfUrl': pdfUrl,
            'academicYear': ?academicYear,
          }),
        )
        .timeout(_requestTimeout);

    Map<String, dynamic> data = <String, dynamic>{};
    try {
      final parsed = jsonDecode(res.body);
      if (parsed is Map<String, dynamic>) {
        data = parsed;
      } else if (parsed is Map) {
        data = Map<String, dynamic>.from(parsed);
      }
    } catch (_) {
      // Preserve best-effort fallback below.
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message =
          data['message']?.toString() ??
          data['error']?.toString() ??
          (res.body.trim().isNotEmpty ? res.body : 'Failed to upload syllabus');
      throw Exception(message);
    }

    return data;
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
    final list =
        (data['savedPosts'] as List?) ??
        (data['saved_posts'] as List?) ??
        (data['posts'] as List?) ??
        (data['items'] as List?) ??
        const [];
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
        'college_id': ?collegeId,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
        'ocr_provider': ?ocrProvider,
        'force': ?force,
        'include_source': ?includeSource,
        'video_url': ?videoUrl,
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
        'college_id': ?collegeId,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
        'ocr_provider': ?ocrProvider,
        'force': ?force,
        'include_source': ?includeSource,
        'video_url': ?videoUrl,
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
        'college_id': ?collegeId,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
        'ocr_provider': ?ocrProvider,
        'force': ?force,
        'include_source': ?includeSource,
        'video_url': ?videoUrl,
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
        'college_id': ?collegeId,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
        'ocr_provider': ?ocrProvider,
      },
    );
  }

  Future<Map<String, dynamic>> queryRag({
    required String question,
    String? collegeId,
    String? sessionId,
    int? topK,
    double? minScore,
    bool? allowWeb,
    String? fileId,
    bool? useOcr,
    bool? forceOcr,
    String? ocrProvider,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, String>>? history,
    Map<String, dynamic>? filters,
  }) async {
    return _requestJson(
      '/api/rag/query',
      method: 'POST',
      body: {
        'question': question,
        'college_id': ?collegeId,
        'session_id': ?sessionId,
        'top_k': ?topK,
        'min_score': ?minScore,
        'allow_web': ?allowWeb,
        'file_id': ?fileId,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
        'ocr_provider': ?ocrProvider,
        'attachments': ?attachments,
        'history': ?history,
        'filters': ?filters,
      },
    );
  }

  Future<Map<String, dynamic>> uploadNotebookSource({
    required String filePath,
    required String collegeId,
    String? notebookId,
    String? title,
    String? sourceScope,
  }) async {
    final token = await _getIdToken();
    final uri = Uri.parse('$_baseUrl/api/notebooks/sources/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['college_id'] = collegeId;

    if (notebookId != null && notebookId.trim().isNotEmpty) {
      request.fields['notebook_id'] = notebookId.trim();
    }
    if (title != null && title.trim().isNotEmpty) {
      request.fields['title'] = title.trim();
    }
    if (sourceScope != null && sourceScope.trim().isNotEmpty) {
      request.fields['source_scope'] = sourceScope.trim();
    }
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await _sendStreamedRequest(request);
    final body = await streamed.stream.bytesToString();
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'Notebook source upload failed (${streamed.statusCode}): $body',
      );
    }

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final message =
          data['message']?.toString() ??
          data['error_code']?.toString() ??
          data['error']?.toString() ??
          'Notebook source upload failed';
      throw Exception(message);
    }

    return data;
  }

  Future<Map<String, dynamic>> requestNotebookSourceReupload({
    required String sourceId,
    required String replacementFileId,
    String? reason,
    String? ocrErrorCode,
  }) async {
    return _requestJson(
      '/api/notebooks/sources/${Uri.encodeComponent(sourceId)}/request-reupload',
      method: 'POST',
      body: {
        'replacement_file_id': replacementFileId,
        'reason': ?reason,
        'ocr_error_code': ?ocrErrorCode,
      },
    );
  }

  Future<Map<String, dynamic>> retryNotebookSourceNow({
    required String sourceId,
    String? reason,
  }) async {
    return _requestJson(
      '/api/notebooks/sources/${Uri.encodeComponent(sourceId)}/retry-now',
      method: 'POST',
      body: {'reason': ?reason},
    );
  }

  Future<Map<String, dynamic>> cancelNotebookSourceRetry({
    required String sourceId,
    String? reason,
  }) async {
    return _requestJson(
      '/api/notebooks/sources/${Uri.encodeComponent(sourceId)}/cancel-retry',
      method: 'POST',
      body: {'reason': ?reason},
    );
  }

  bool _isUnsupportedRagStreamStatus(int statusCode) {
    return statusCode == 404 ||
        statusCode == 405 ||
        statusCode == 406 ||
        statusCode == 415 ||
        statusCode == 501;
  }

  Stream<String> _queryRagAsSyntheticStream({
    required String question,
    String? collegeId,
    String? sessionId,
    int? topK,
    double? minScore,
    bool? allowWeb,
    String? fileId,
    bool? useOcr,
    bool? forceOcr,
    String? ocrProvider,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, String>>? history,
    Map<String, dynamic>? filters,
  }) async* {
    final response = await queryRag(
      question: question,
      collegeId: collegeId,
      sessionId: sessionId,
      topK: topK,
      minScore: minScore,
      allowWeb: allowWeb,
      fileId: fileId,
      useOcr: useOcr,
      forceOcr: forceOcr,
      ocrProvider: ocrProvider,
      attachments: attachments,
      history: history,
      filters: filters,
    );

    List<dynamic> sourcesRaw = const [];
    final data = response['data'];
    if (response['sources'] is List) {
      sourcesRaw = response['sources'] as List;
    } else if (data is Map && data['sources'] is List) {
      sourcesRaw = data['sources'] as List;
    }

    final normalizedSources = sourcesRaw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final noLocal =
        response['no_local'] == true ||
        (data is Map && data['no_local'] == true);
    final retrievalScore =
        response['retrieval_score'] ??
        (data is Map ? data['retrieval_score'] : null);
    final llmConfidenceScore =
        response['llm_confidence_score'] ??
        (data is Map ? data['llm_confidence_score'] : null);
    final combinedConfidence =
        response['combined_confidence'] ??
        (data is Map ? data['combined_confidence'] : null);
    final ocrFailureAffectsRetrieval =
        response['ocr_failure_affects_retrieval'] ??
        (data is Map ? data['ocr_failure_affects_retrieval'] : null);

    if (normalizedSources.isNotEmpty || noLocal) {
      yield jsonEncode({
        'type': 'metadata',
        'data': {
          'sources': normalizedSources,
          'no_local': noLocal,
          'retrieval_score': ?retrievalScore,
          'llm_confidence_score': ?llmConfidenceScore,
          'combined_confidence': ?combinedConfidence,
          'ocr_failure_affects_retrieval': ?ocrFailureAffectsRetrieval,
        },
      });
    }

    final answerRaw =
        response['answer'] ??
        response['response'] ??
        (data is Map ? (data['answer'] ?? data['response']) : data);
    final answer = answerRaw?.toString() ?? '';
    if (answer.trim().isNotEmpty) {
      yield jsonEncode({'type': 'chunk', 'text': answer});
    }
    yield jsonEncode({'type': 'done'});
  }

  Stream<String> queryRagStream({
    required String question,
    String? collegeId,
    String? sessionId,
    int? topK,
    double? minScore,
    bool? allowWeb,
    String? fileId,
    bool? useOcr,
    bool? forceOcr,
    String? ocrProvider,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, String>>? history,
    Map<String, dynamic>? filters,
  }) async* {
    if (_ragStreamUnavailable) {
      yield* _queryRagAsSyntheticStream(
        question: question,
        collegeId: collegeId,
        sessionId: sessionId,
        topK: topK,
        minScore: minScore,
        allowWeb: allowWeb,
        fileId: fileId,
        useOcr: useOcr,
        forceOcr: forceOcr,
        ocrProvider: ocrProvider,
        attachments: attachments,
        history: history,
        filters: filters,
      );
      return;
    }

    final token = await _getIdToken();
    final uri = Uri.parse('$_baseUrl/api/rag/query/stream');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode({
        'question': question,
        'college_id': ?collegeId,
        'session_id': ?sessionId,
        'top_k': ?topK,
        'min_score': ?minScore,
        'allow_web': ?allowWeb,
        'file_id': ?fileId,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
        'ocr_provider': ?ocrProvider,
        'attachments': ?attachments,
        'history': ?history,
        'filters': ?filters,
      });

    final response = await _sendStreamedRequest(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      if (_isUnsupportedRagStreamStatus(response.statusCode)) {
        _ragStreamUnavailable = true;
        debugPrint(
          '[BackendApi] Stream endpoint unavailable '
          '(${response.statusCode}). Falling back to /api/rag/query.',
        );
        yield* _queryRagAsSyntheticStream(
          question: question,
          collegeId: collegeId,
          sessionId: sessionId,
          topK: topK,
          minScore: minScore,
          allowWeb: allowWeb,
          fileId: fileId,
          useOcr: useOcr,
          forceOcr: forceOcr,
          ocrProvider: ocrProvider,
          attachments: attachments,
          history: history,
          filters: filters,
        );
        return;
      }
      try {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final message =
            data['message']?.toString() ??
            data['error']?.toString() ??
            'RAG stream request failed';
        throw Exception(message);
      } catch (_) {
        throw Exception(
          'RAG stream request failed (${response.statusCode}): $body',
        );
      }
    }

    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lineStream) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      yield payload;
    }
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
