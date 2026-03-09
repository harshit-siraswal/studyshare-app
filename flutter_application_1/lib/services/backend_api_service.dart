import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'recaptcha_service.dart';

class BackendApiHttpException implements Exception {
  const BackendApiHttpException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => 'Exception: $message';
}

const Set<int> kBackendCompatibilityFallbackStatuses = <int>{
  404,
  405,
  406,
  415,
  501,
};

bool isBackendCompatibilityFallbackError(Object error) {
  if (error is BackendApiHttpException) {
    return kBackendCompatibilityFallbackStatuses.contains(error.statusCode);
  }

  final message = error.toString().toLowerCase();
  return message.contains('http 404') ||
      message.contains('http 405') ||
      message.contains('http 406') ||
      message.contains('http 415') ||
      message.contains('http 501');
}
/// Backend API client (same pattern as Studyspace/src/lib/api.ts).
///
/// Use this for ALL privileged writes (create room, post, comment, upload, profile update).
/// This avoids client-side Supabase inserts that fail under RLS with anon key.
class BackendApiService {
  BackendApiService({FirebaseAuth? firebaseAuth, http.Client? httpClient})
    : _injectedAuth = firebaseAuth,
      _httpClient = httpClient ?? http.Client();

  final FirebaseAuth? _injectedAuth;
  final http.Client _httpClient;
  bool _ragStreamUnavailable = false;
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _streamRequestTimeout = Duration(seconds: 120);
  static const Duration _aiRequestTimeout = Duration(seconds: 120);
  static const Set<int> _hardUnsupportedRagStreamStatuses = <int>{
    404,
    405,
    406,
    415,
    501,
  };
  static const Set<int> _transientRagStreamFallbackStatuses = <int>{
    500,
    502,
    503,
    504,
    520,
    521,
    522,
    523,
    524,
    525,
    526,
  };
  static const Set<int> _edgeNetworkErrorStatuses = <int>{
    520,
    521,
    522,
    523,
    524,
    525,
    526,
  };

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
    Duration timeout,
  ) async {
    final encodedBody = body == null ? null : jsonEncode(body);
    final future = switch (method.toUpperCase()) {
      'POST' => _httpClient.post(uri, headers: headers, body: encodedBody),
      'PUT' => _httpClient.put(uri, headers: headers, body: encodedBody),
      'PATCH' => _httpClient.patch(uri, headers: headers, body: encodedBody),
      'DELETE' => _httpClient.delete(uri, headers: headers, body: encodedBody),
      _ => _httpClient.get(uri, headers: headers),
    };
    return future.timeout(timeout);
  }

  Future<http.StreamedResponse> _sendStreamedRequest(http.BaseRequest request) {
    return _httpClient.send(request).timeout(_streamRequestTimeout);
  }

  String _compactErrorBody(String body, {int maxLength = 220}) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maxLength) return compact;
    return '${compact.substring(0, maxLength)}...';
  }

  bool _looksLikeHtmlPayload(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) return false;
    final lowered = trimmed.toLowerCase();
    return lowered.startsWith('<!doctype html') ||
        lowered.startsWith('<html') ||
        lowered.contains('<html') ||
        lowered.contains('<body');
  }

  String _friendlyHttpErrorMessage({
    required int statusCode,
    required String body,
    required String fallbackMessage,
  }) {
    if (_looksLikeHtmlPayload(body)) {
      if (_edgeNetworkErrorStatuses.contains(statusCode)) {
        return 'Backend temporarily unreachable (HTTP $statusCode). '
            'Please retry in a moment.';
      }
      return '$fallbackMessage (HTTP $statusCode).';
    }
    final compact = _compactErrorBody(body);
    if (compact.isEmpty) return '$fallbackMessage (HTTP $statusCode).';
    return '$fallbackMessage (HTTP $statusCode): $compact';
  }

  Future<Map<String, dynamic>> _requestJson(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Duration timeout = _requestTimeout,
    bool requireAuthToken = false,
    String? bearerOverride,
    BuildContext? securityContext,
    bool includeRecaptchaToken = false,
    String recaptchaAction = 'mobile_write',
  }) async {
    final trimmedBearerOverride = bearerOverride?.trim();
    final usesBearerOverride =
        trimmedBearerOverride != null && trimmedBearerOverride.isNotEmpty;
    String? token = usesBearerOverride
        ? trimmedBearerOverride
        : await _getIdToken();
    if (requireAuthToken && (token == null || token.isEmpty)) {
      throw Exception('Authentication required');
    }
    final uri = Uri.parse('$_baseUrl$path');

    var headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    Map<String, dynamic>? effectiveBody = body == null
        ? null
        : Map<String, dynamic>.from(body);

    if (includeRecaptchaToken) {
      final normalizedMethod = method.toUpperCase();
      if (normalizedMethod == 'GET') {
        throw Exception('Security verification is only supported for writes');
      }
      if (securityContext == null || !securityContext.mounted) {
        throw Exception('Security verification context missing');
      }
      final recaptchaToken = await RecaptchaService.getToken(
        securityContext,
        action: recaptchaAction,
      );
      effectiveBody ??= <String, dynamic>{};
      effectiveBody['recaptchaToken'] = recaptchaToken;
    }

    var res = await _sendRequest(method, uri, headers, effectiveBody, timeout);

    if (!usesBearerOverride &&
        (res.statusCode == 401 || res.statusCode == 403)) {
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
        res = await _sendRequest(method, uri, headers, effectiveBody, timeout);
      }
    }

    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else if (decoded is Map) {
        data = decoded.cast<String, dynamic>();
      }
    } catch (_) {}

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg =
          data?['message']?.toString() ?? data?['error']?.toString() ?? '';
      if (msg.trim().isNotEmpty) {
        throw BackendApiHttpException(
          statusCode: res.statusCode,
          message: msg.trim(),
        );
      }
      throw BackendApiHttpException(
        statusCode: res.statusCode,
        message: _friendlyHttpErrorMessage(
          statusCode: res.statusCode,
          body: res.body,
          fallbackMessage: 'API request failed',
        ),
      );
    }
    if (data == null) {
      throw Exception(
        _friendlyHttpErrorMessage(
          statusCode: res.statusCode,
          body: res.body,
          fallbackMessage: 'API response was not valid JSON',
        ),
      );
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
      body: <String, dynamic>{
        'name': name,
        'isPrivate': isPrivate,
        'collegeId': collegeId,
        if (description != null) 'description': description,
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
      body: <String, dynamic>{
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
      body: <String, dynamic>{
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

  Future<List<Map<String, dynamic>>> getNotices(
    String collegeId, {
    String? department,
  }) async {
    final query = StringBuffer(
      '/api/notices?college_id=${Uri.encodeQueryComponent(collegeId)}',
    );
    final normalizedDepartment = department?.trim();
    if (normalizedDepartment != null && normalizedDepartment.isNotEmpty) {
      query.write(
        '&department=${Uri.encodeQueryComponent(normalizedDepartment)}',
      );
    }
    final data = await _requestJson(
      query.toString(),
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
    String? fileUrl,
  }) async {
    final normalizedImageUrl = imageUrl?.trim();
    final normalizedFileUrl = fileUrl?.trim();
    final effectiveAttachmentUrl = (normalizedFileUrl?.isNotEmpty ?? false)
        ? normalizedFileUrl
        : ((normalizedImageUrl?.isNotEmpty ?? false)
              ? normalizedImageUrl
              : null);

    return _requestJson(
      '/api/notices',
      method: 'POST',
      body: <String, dynamic>{
        'collegeId': collegeId,
        'title': title,
        'content': content,
        'department': department,
        if (effectiveAttachmentUrl != null) 'imageUrl': effectiveAttachmentUrl,
        if (effectiveAttachmentUrl != null) 'fileUrl': effectiveAttachmentUrl,
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
      body: <String, dynamic>{
        'content': content,
        if (parentId != null) 'parentId': parentId,
      },
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
    required BuildContext context,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) {
      body['display_name'] = displayName.trim();
    }
    if (username != null) {
      body['username'] = username.trim();
    }
    if (bio != null) {
      body['bio'] = bio.trim();
    }
    if (profilePhotoUrl != null) {
      body['profile_photo_url'] = profilePhotoUrl.trim();
    }
    if (college != null) {
      body['college'] = college.trim();
    }
    if (branch != null) {
      body['branch'] = branch.trim();
    }
    if (semester != null) {
      body['semester'] = semester.trim();
    }
    if (subject != null) {
      body['subject'] = subject.trim();
    }

    return _requestJson(
      '/api/users/profile',
      method: 'PUT',
      body: body,
      securityContext: context,
      includeRecaptchaToken: true,
      recaptchaAction: 'profile_update',
    );
  }

  // ----------------------------
  // Payments
  // ----------------------------

  Future<Map<String, dynamic>> createPaymentOrder({
    String? planId,
    String purchaseType = 'premium',
    int? rechargeRupees,
    int? amount,
    BuildContext? context,
  }) async {
    return _requestJson(
      '/api/payments/order',
      method: 'POST',
      body: <String, dynamic>{
        'purchaseType': purchaseType,
        if (planId != null) 'planId': planId,
        if (rechargeRupees != null) 'rechargeRupees': rechargeRupees,
        if (amount != null) 'amount': amount,
      },
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
    try {
      final data = await _requestJson(
        '/api/notifications/unread-count',
        method: 'GET',
      );
      final countRaw = data['count'] ?? data['unreadCount'] ?? data['unread'];
      if (countRaw is num) {
        return countRaw.toInt();
      }
      final parsed = int.tryParse(countRaw?.toString() ?? '');
      if (parsed != null) {
        return parsed;
      }
    } catch (_) {
      // Fallback below for backward compatibility.
    }

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
    String? bearerToken,
    required BuildContext context,
  }) async {
    await _requestJson(
      '/api/admin/resources/${Uri.encodeComponent(resourceId)}/status',
      method: 'PATCH',
      body: {'status': status},
      bearerOverride: bearerToken,
      requireAuthToken: true,
    );
  }

  Future<void> deleteResourceAsAdmin({
    required String resourceId,
    String? bearerToken,
  }) async {
    try {
      await _requestJson(
        '/api/admin/resources/${Uri.encodeComponent(resourceId)}',
        method: 'DELETE',
        bearerOverride: bearerToken,
        requireAuthToken: true,
      );
      return;
    } on BackendApiHttpException catch (error) {
      if (error.statusCode != 404 && error.statusCode != 405) {
        rethrow;
      }
    }

    await _requestJson(
      '/api/admin',
      method: 'POST',
      body: {
        'action': 'delete_resource',
        'resourceId': resourceId,
        if ((bearerToken ?? '').trim().isNotEmpty)
          'keyHash': bearerToken!.trim(),
      },
      bearerOverride: bearerToken,
      requireAuthToken: true,
    );
  }

  Future<void> deleteOwnedResource({
    required String resourceId,
    String? bearerToken,
    String? fileUrl,
    String? thumbnailUrl,
    String? uploadedByEmail,
  }) async {
    final normalizedFileUrl = fileUrl?.trim();
    final normalizedThumbnailUrl = thumbnailUrl?.trim();
    final normalizedUploadedByEmail = uploadedByEmail?.trim().toLowerCase();
    final deletePayload = <String, dynamic>{
      if (normalizedFileUrl != null && normalizedFileUrl.isNotEmpty)
        'fileUrl': normalizedFileUrl,
      if (normalizedFileUrl != null && normalizedFileUrl.isNotEmpty)
        'file_url': normalizedFileUrl,
      if (normalizedThumbnailUrl != null && normalizedThumbnailUrl.isNotEmpty)
        'thumbnailUrl': normalizedThumbnailUrl,
      if (normalizedThumbnailUrl != null && normalizedThumbnailUrl.isNotEmpty)
        'thumbnail_url': normalizedThumbnailUrl,
      if (normalizedUploadedByEmail != null &&
          normalizedUploadedByEmail.isNotEmpty)
        'uploadedByEmail': normalizedUploadedByEmail,
      if (normalizedUploadedByEmail != null &&
          normalizedUploadedByEmail.isNotEmpty)
        'uploaded_by_email': normalizedUploadedByEmail,
    };

    try {
      await _requestJson(
        '/api/resources/${Uri.encodeComponent(resourceId)}',
        method: 'DELETE',
        body: deletePayload.isEmpty ? null : deletePayload,
        bearerOverride: bearerToken,
        requireAuthToken: true,
      );
      return;
    } on BackendApiHttpException catch (error) {
      if (error.statusCode != 404 && error.statusCode != 405) {
        rethrow;
      }
    }

    await _requestJson(
      '/api/admin',
      method: 'POST',
      body: {
        'action': 'delete_resource',
        'resourceId': resourceId,
        if ((bearerToken ?? '').trim().isNotEmpty)
          'keyHash': bearerToken!.trim(),
        if (normalizedFileUrl != null && normalizedFileUrl.isNotEmpty)
          'fileUrl': normalizedFileUrl,
        if (normalizedFileUrl != null && normalizedFileUrl.isNotEmpty)
          'file_url': normalizedFileUrl,
        if (normalizedThumbnailUrl != null && normalizedThumbnailUrl.isNotEmpty)
          'thumbnailUrl': normalizedThumbnailUrl,
        if (normalizedThumbnailUrl != null && normalizedThumbnailUrl.isNotEmpty)
          'thumbnail_url': normalizedThumbnailUrl,
        if (normalizedUploadedByEmail != null &&
            normalizedUploadedByEmail.isNotEmpty)
          'uploadedByEmail': normalizedUploadedByEmail,
        if (normalizedUploadedByEmail != null &&
            normalizedUploadedByEmail.isNotEmpty)
          'uploaded_by_email': normalizedUploadedByEmail,
      },
      bearerOverride: bearerToken,
      requireAuthToken: true,
    );
  }

  Future<Map<String, dynamic>> banUserAsAdmin({
    required String email,
    String? bearerToken,
    String? reason,
    String? collegeId,
  }) async {
    return _requestJson(
      '/api/admin/users-ban',
      method: 'POST',
      body: <String, dynamic>{
        'email': email.trim().toLowerCase(),
        if (reason != null) 'reason': reason,
        if (collegeId != null) 'collegeId': collegeId,
      },
      bearerOverride: bearerToken,
      requireAuthToken: true,
    );
  }

  Future<List<Map<String, dynamic>>> listAdminResources({
    String? bearerToken,
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

    final data = await _requestJson(
      Uri(
        path: '/api/admin/resources',
        queryParameters: queryParams,
      ).toString(),
      method: 'GET',
      bearerOverride: bearerToken,
      requireAuthToken: true,
    );

    final resourcesRaw = data['resources'];
    if (resourcesRaw is! List) return const [];
    return resourcesRaw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> uploadSyllabusAsAdmin({
    String? bearerToken,
    required String collegeId,
    required String semester,
    required String branch,
    required String subject,
    required String title,
    required String pdfUrl,
    String? academicYear,
  }) async {
    return _requestJson(
      '/api/admin',
      method: 'POST',
      body: <String, dynamic>{
        'action': 'upload_syllabus',
        'collegeId': collegeId,
        'semester': semester,
        'branch': branch,
        'subject': subject,
        'title': title,
        'pdfUrl': pdfUrl,
        if (academicYear != null) 'academicYear': academicYear,
      },
      bearerOverride: bearerToken,
      requireAuthToken: true,
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
    String targetEmail, {
    required BuildContext context,
  }) async {
    await _requestJson(
      '/api/follow/request', // Corrected from /api/follows/requests
      method: 'POST',
      body: {
        'targetEmail': targetEmail,
      }, // Changed targetId to targetEmail per API
      securityContext: context,
      includeRecaptchaToken: true,
      recaptchaAction: 'follow_request',
    );
  }

  Future<void> acceptFollowRequest(
    int requestId, {
    required BuildContext context,
  }) async {
    await _requestJson(
      '/api/follow/approve/${requestId.toString()}', // Corrected endpoint
      method: 'POST',
      securityContext: context,
      includeRecaptchaToken: true,
      recaptchaAction: 'follow_approve',
    );
  }

  Future<void> rejectFollowRequest(
    int requestId, {
    required BuildContext context,
  }) async {
    await _requestJson(
      '/api/follow/reject/${requestId.toString()}', // Corrected endpoint
      method: 'POST',
      securityContext: context,
      includeRecaptchaToken: true,
      recaptchaAction: 'follow_reject',
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
      timeout: _aiRequestTimeout,
      body: <String, dynamic>{
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
      timeout: _aiRequestTimeout,
      body: <String, dynamic>{
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
      timeout: _aiRequestTimeout,
      body: <String, dynamic>{
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
      body: <String, dynamic>{
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
      timeout: _aiRequestTimeout,
      body: <String, dynamic>{
        'question': question,
        if (collegeId != null) 'college_id': collegeId,
        if (sessionId != null) 'session_id': sessionId,
        if (topK != null) 'top_k': topK,
        if (minScore != null) 'min_score': minScore,
        if (allowWeb != null) 'allow_web': allowWeb,
        if (fileId != null) 'file_id': fileId,
        if (useOcr != null) 'use_ocr': useOcr,
        if (forceOcr != null) 'force_ocr': forceOcr,
        if (ocrProvider != null) 'ocr_provider': ocrProvider,
        if (attachments != null) 'attachments': attachments,
        if (history != null) 'history': history,
        if (filters != null) 'filters': filters,
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
      body: <String, dynamic>{
        'replacement_file_id': replacementFileId,
        if (reason != null) 'reason': reason,
        if (ocrErrorCode != null) 'ocr_error_code': ocrErrorCode,
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
      body: <String, dynamic>{if (reason != null) 'reason': reason},
    );
  }

  Future<Map<String, dynamic>> cancelNotebookSourceRetry({
    required String sourceId,
    String? reason,
  }) async {
    return _requestJson(
      '/api/notebooks/sources/${Uri.encodeComponent(sourceId)}/cancel-retry',
      method: 'POST',
      body: <String, dynamic>{if (reason != null) 'reason': reason},
    );
  }

  bool _isUnsupportedRagStreamStatus(int statusCode) {
    return _hardUnsupportedRagStreamStatuses.contains(statusCode);
  }

  bool _shouldFallbackRagStreamStatus(int statusCode) {
    return _isUnsupportedRagStreamStatus(statusCode) ||
        _transientRagStreamFallbackStatuses.contains(statusCode);
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
        'data': <String, dynamic>{
          'sources': normalizedSources,
          'no_local': noLocal,
          if (retrievalScore != null) 'retrieval_score': retrievalScore,
          if (llmConfidenceScore != null)
            'llm_confidence_score': llmConfidenceScore,
          if (combinedConfidence != null)
            'combined_confidence': combinedConfidence,
          if (ocrFailureAffectsRetrieval != null)
            'ocr_failure_affects_retrieval': ocrFailureAffectsRetrieval,
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
    Stream<String> fallbackStream() {
      return _queryRagAsSyntheticStream(
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
    }

    if (_ragStreamUnavailable) {
      yield* fallbackStream();
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
      ..body = jsonEncode(<String, dynamic>{
        'question': question,
        if (collegeId != null) 'college_id': collegeId,
        if (sessionId != null) 'session_id': sessionId,
        if (topK != null) 'top_k': topK,
        if (minScore != null) 'min_score': minScore,
        if (allowWeb != null) 'allow_web': allowWeb,
        if (fileId != null) 'file_id': fileId,
        if (useOcr != null) 'use_ocr': useOcr,
        if (forceOcr != null) 'force_ocr': forceOcr,
        if (ocrProvider != null) 'ocr_provider': ocrProvider,
        if (attachments != null) 'attachments': attachments,
        if (history != null) 'history': history,
        if (filters != null) 'filters': filters,
      });

    http.StreamedResponse response;
    try {
      response = await _sendStreamedRequest(request);
    } on TimeoutException catch (error) {
      debugPrint(
        '[BackendApi] Stream request timed out. Falling back to /api/rag/query. '
        '$error',
      );
      yield* fallbackStream();
      return;
    } on SocketException catch (error) {
      debugPrint(
        '[BackendApi] Stream socket failure. Falling back to /api/rag/query. '
        '$error',
      );
      yield* fallbackStream();
      return;
    } on http.ClientException catch (error) {
      debugPrint(
        '[BackendApi] Stream client failure. Falling back to /api/rag/query. '
        '$error',
      );
      yield* fallbackStream();
      return;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      if (_shouldFallbackRagStreamStatus(response.statusCode)) {
        if (_isUnsupportedRagStreamStatus(response.statusCode)) {
          _ragStreamUnavailable = true;
        }
        debugPrint(
          '[BackendApi] Stream endpoint failure (${response.statusCode}). '
          '${_isUnsupportedRagStreamStatus(response.statusCode) ? 'Disabling stream endpoint until app restart. ' : ''}'
          'Falling back to /api/rag/query.',
        );
        yield* fallbackStream();
        return;
      }
      String? parsedMessage;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final data = decoded.cast<String, dynamic>();
          parsedMessage =
              data['message']?.toString() ?? data['error']?.toString();
        }
      } catch (_) {}
      if (parsedMessage != null && parsedMessage.trim().isNotEmpty) {
        throw Exception(parsedMessage.trim());
      }
      throw Exception(
        _friendlyHttpErrorMessage(
          statusCode: response.statusCode,
          body: body,
          fallbackMessage: 'RAG stream request failed',
        ),
      );
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
      requireAuthToken: true,
      // Recaptcha context removed as it cannot be a string
    );
  }

  /// Delete the current install token using backend-owned token semantics.
  Future<void> deleteFcmToken(String token) async {
    await _requestJson(
      '/api/notifications/fcm-token',
      method: 'DELETE',
      body: {'token': token},
      requireAuthToken: true,
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
      securityContext: context,
      includeRecaptchaToken: context != null,
      recaptchaAction: 'follow_unfollow',
    );
  }

  Future<void> cancelFollowRequest(
    int requestId, {
    BuildContext? context,
  }) async {
    await _requestJson(
      '/api/follow/request/${Uri.encodeComponent(requestId.toString())}',
      method: 'DELETE',
      securityContext: context,
      includeRecaptchaToken: context != null,
      recaptchaAction: 'follow_cancel',
    );
  }
}
