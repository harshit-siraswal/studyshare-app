import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
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
  BackendApiService({
    FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
    List<String>? apiBaseUrls,
    bool startMaintenanceTimer = true,
  }) : _injectedAuth = firebaseAuth,
       _httpClient = httpClient ?? _sharedHttpClient,
       _apiBaseUrls = List.unmodifiable(
         _normalizeApiBaseUrls(apiBaseUrls ?? AppConfig.apiBaseUrls),
       ) {
    if (startMaintenanceTimer) {
      _bookmarkRateLimitCleanupTimer ??= Timer.periodic(
        const Duration(minutes: 10),
        (_) => _cleanupExpiredBookmarkCheckRateLimits(),
      );
    }
  }

  static const String _primaryBackendHost = 'api.studyshare.in';
  static const String _primaryBackendFallbackIp = '13.61.19.178';
  static const Duration _connectionAttemptTimeout = Duration(seconds: 10);

  static final http.Client _sharedHttpClient = _createSharedHttpClient();

  final FirebaseAuth? _injectedAuth;
  final http.Client _httpClient;
  final List<String> _apiBaseUrls;
  bool _ragStreamUnavailable = false;
  static const Duration _ragStreamDisableTtl = Duration(minutes: 10);
  DateTime? _ragStreamUnavailableSince;
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _streamRequestTimeout = Duration(seconds: 120);
  static const Duration _streamIdleTimeout = Duration(seconds: 45);
  static const Duration _aiRequestTimeout = Duration(seconds: 120);
  static const Set<int> _hardUnsupportedRagStreamStatuses =
      kBackendCompatibilityFallbackStatuses;
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

  static List<String> _normalizeApiBaseUrls(List<String> baseUrls) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final baseUrl in baseUrls) {
      final trimmed = baseUrl.trim();
      if (trimmed.isEmpty) continue;
      final stripped = trimmed.replaceAll(RegExp(r'/+$'), '');
      if (seen.add(stripped)) {
        normalized.add(stripped);
      }
    }
    if (normalized.isEmpty) {
      normalized.add(AppConfig.apiUrl);
    }
    return normalized;
  }

  static http.Client _createSharedHttpClient() {
    final inner = HttpClient();
    inner.findProxy = (uri) => 'DIRECT';
    inner.connectionFactory = _backendConnectionFactory;
    return IOClient(inner);
  }

  static Future<ConnectionTask<Socket>> _backendConnectionFactory(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final addresses = await _resolveBackendAddresses(uri.host);
    Object? lastError;

    for (final address in addresses) {
      try {
        final socket = await Socket.connect(
          address,
          port,
        ).timeout(_connectionAttemptTimeout);
        if (uri.scheme == 'https') {
          final secureSocket = await SecureSocket.secure(
            socket,
            host: uri.host,
          ).timeout(_connectionAttemptTimeout);
          return ConnectionTask.fromSocket(
            Future<Socket>.value(secureSocket),
            () => secureSocket.destroy(),
          );
        }

        return ConnectionTask.fromSocket(
          Future<Socket>.value(socket),
          () => socket.destroy(),
        );
      } catch (error) {
        lastError = error;
      }
    }

    throw SocketException(
      'Failed to connect to ${uri.host}: ${lastError ?? 'unknown error'}',
    );
  }

  static Future<List<InternetAddress>> _resolveBackendAddresses(
    String host,
  ) async {
    final addresses = <InternetAddress>[];

    if (host == _primaryBackendHost) {
      addresses.add(InternetAddress(_primaryBackendFallbackIp));
    }

    try {
      final resolved = await InternetAddress.lookup(
        host,
      ).timeout(_connectionAttemptTimeout);
      for (final address in resolved) {
        if (addresses.any((existing) => existing.address == address.address)) {
          continue;
        }
        addresses.add(address);
      }
    } catch (_) {
      // Keep the explicit fallback address if DNS resolution fails.
    }

    if (addresses.isEmpty) {
      throw SocketException('No backend addresses available for $host');
    }

    return addresses;
  }

  bool _isRecaptchaTransientFailure(Object error) {
    final lowered = error.toString().toLowerCase();
    return lowered.contains('security check timed out') ||
        lowered.contains('security verification') ||
        lowered.contains('recaptcha') ||
        lowered.contains('not supported');
  }

  bool _isKietSyncTransientFailure(Object error) {
    if (error is TimeoutException || error is SocketException) {
      return true;
    }

    if (error is BackendApiHttpException) {
      final status = error.statusCode;
      return status == 408 ||
          status == 425 ||
          (status >= 500 && status <= 504) ||
          _edgeNetworkErrorStatuses.contains(status);
    }

    final lowered = error.toString().toLowerCase();
    return lowered.contains('timeout') ||
        lowered.contains('timed out') ||
        lowered.contains('temporarily unavailable') ||
        lowered.contains('connection') ||
        lowered.contains('network') ||
        lowered.contains('socket') ||
        lowered.contains('gateway') ||
        lowered.contains('http 502') ||
        lowered.contains('http 503') ||
        lowered.contains('http 504') ||
        lowered.contains('http 520') ||
        lowered.contains('http 521') ||
        lowered.contains('http 522') ||
        lowered.contains('http 523') ||
        lowered.contains('http 524') ||
        lowered.contains('http 525') ||
        lowered.contains('http 526');
  }

  bool _isAiOrRagPath(String path) {
    return path.startsWith('/api/rag/') || path.startsWith('/api/ai/');
  }

  bool _shouldPreferFreshConnection(String path) {
    return _isAiOrRagPath(path);
  }

  bool _shouldRetryTransientConnectionFailure({
    required String path,
    required String method,
  }) {
    final normalizedMethod = method.toUpperCase();
    if (_isAiOrRagPath(path)) {
      return true;
    }
    return normalizedMethod == 'GET';
  }

  bool _isTransientConnectionFailure(Object error) {
    if (error is TimeoutException || error is SocketException) {
      return true;
    }
    if (error is http.ClientException) {
      final lowered = error.message.toLowerCase();
      return lowered.contains('connection reset') ||
          lowered.contains('reset by peer') ||
          lowered.contains('broken pipe') ||
          lowered.contains('connection closed') ||
          lowered.contains('connection abort') ||
          lowered.contains('software caused connection abort') ||
          lowered.contains('stream terminated') ||
          lowered.contains('timed out') ||
          lowered.contains('host lookup') ||
          lowered.contains('failed host lookup') ||
          lowered.contains('no address associated with hostname') ||
          lowered.contains('name or service not known') ||
          lowered.contains('socketfailed');
    }

    final lowered = error.toString().toLowerCase();
    return lowered.contains('connection reset') ||
        lowered.contains('reset by peer') ||
        lowered.contains('broken pipe') ||
        lowered.contains('connection abort') ||
        lowered.contains('socketexception') ||
        lowered.contains('timed out') ||
        lowered.contains('host lookup') ||
        lowered.contains('failed host lookup') ||
        lowered.contains('no address associated with hostname') ||
        lowered.contains('name or service not known') ||
        lowered.contains('socketfailed');
  }

  static final Map<String, DateTime> _bookmarkCheckRateLimitUntil =
      <String, DateTime>{};
  static Timer? _bookmarkRateLimitCleanupTimer;
  static final Map<String, List<DateTime>> _clientRateLimitEvents =
      <String, List<DateTime>>{};
  DateTime? _notificationsRateLimitUntil;
  int? _lastUnreadNotificationCount;
  List<Map<String, dynamic>> _lastNotificationsCache =
      const <Map<String, dynamic>>[];

  static void _cleanupExpiredBookmarkCheckRateLimits() {
    final now = DateTime.now();
    _bookmarkCheckRateLimitUntil.removeWhere((_, until) => !until.isAfter(now));
  }

  static void disposeTimersForTesting() {
    _bookmarkRateLimitCleanupTimer?.cancel();
    _bookmarkRateLimitCleanupTimer = null;
    _bookmarkCheckRateLimitUntil.clear();
  }

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

  List<Uri> _backendUris(String path) {
    return _apiBaseUrls
        .map((baseUrl) => Uri.parse('$baseUrl$path'))
        .toList(growable: false);
  }

  bool _shouldRequireAuthForPath(String path, String method) {
    final normalizedMethod = method.toUpperCase();
    if (normalizedMethod != 'GET') {
      return true;
    }

    return path.startsWith('/api/bookmarks') ||
        path.startsWith('/api/follow') ||
        path.startsWith('/api/notifications') ||
        path.startsWith('/api/resources/mine') ||
        path.startsWith('/api/resources/state') ||
        path.startsWith('/api/votes') ||
        path.startsWith('/api/notebooks') ||
        _isAiOrRagPath(path);
  }

  void _enforceClientRateLimit({
    required String bucket,
    required int maxRequests,
    required Duration window,
  }) {
    final now = DateTime.now();
    final events = _clientRateLimitEvents.putIfAbsent(
      bucket,
      () => <DateTime>[],
    );
    events.removeWhere((timestamp) => now.difference(timestamp) > window);
    if (events.length >= maxRequests) {
      developer.log(
        'bucket=$bucket max_requests=$maxRequests window_seconds=${window.inSeconds}',
        name: 'api.abuse',
        level: 1000,
      );
      throw const BackendApiHttpException(
        statusCode: 429,
        message: 'Too many requests. Please slow down and try again shortly.',
      );
    }
    events.add(now);
  }

  void _enforceAbuseProtection(String path, String method) {
    final normalizedMethod = method.toUpperCase();
    if (normalizedMethod != 'GET') {
      _enforceClientRateLimit(
        bucket: 'write',
        maxRequests: 40,
        window: const Duration(minutes: 1),
      );
    }

    if (_isAiOrRagPath(path)) {
      _enforceClientRateLimit(
        bucket: 'ai',
        maxRequests: 6,
        window: const Duration(minutes: 1),
      );
    }

    if (path.contains('/upload') || path.contains('/sources/upload')) {
      _enforceClientRateLimit(
        bucket: 'upload',
        maxRequests: 4,
        window: const Duration(minutes: 10),
      );
    }
  }

  void _logApiSecurityEvent({
    required String path,
    required String method,
    required int statusCode,
    required String outcome,
  }) {
    final shouldLog =
        statusCode == 401 ||
        statusCode == 403 ||
        statusCode == 429 ||
        statusCode >= 500;
    if (!shouldLog) return;

    developer.log(
      'method=${method.toUpperCase()} path=$path status=$statusCode outcome=$outcome',
      name: 'api.security',
      level: statusCode >= 500 ? 1000 : 900,
    );
  }

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

  Future<http.StreamedResponse> _sendStreamedRequestAtUri({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) {
    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);
    return _sendStreamedRequest(request);
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

  bool _shouldFallbackToNextBaseUrl(Object error, String path, String method) {
    if (_apiBaseUrls.length <= 1) return false;
    if (!_isTransientConnectionFailure(error)) return false;

    final normalizedMethod = method.toUpperCase();
    if (_isAiOrRagPath(path)) {
      return true;
    }

    return normalizedMethod == 'GET';
  }

  Future<Map<String, dynamic>> _requestJsonAtUri(
    Uri uri, {
    required String path,
    required String method,
    Map<String, dynamic>? body,
    Duration timeout = _requestTimeout,
    required bool requireAuthToken,
    required String? bearerOverride,
    required BuildContext? securityContext,
    required bool includeRecaptchaToken,
    required String recaptchaAction,
    required bool usesBearerOverride,
    required bool preferFreshConnection,
    required bool allowTransientConnectionRetry,
  }) async {
    String? token = usesBearerOverride
        ? bearerOverride?.trim()
        : await _getIdToken();
    if (requireAuthToken && (token == null || token.isEmpty)) {
      throw Exception('Authentication required');
    }

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

    Future<http.Response> sendJsonAttempt({
      required Map<String, String> currentHeaders,
      required bool closeConnection,
    }) {
      final requestHeaders = Map<String, String>.from(currentHeaders);
      if (closeConnection) {
        requestHeaders['Connection'] = 'close';
      }
      return _sendRequest(method, uri, requestHeaders, effectiveBody, timeout);
    }

    late http.Response res;
    Object? lastTransientConnectionError;
    final retryTransientConnectionFailure =
        allowTransientConnectionRetry &&
        _shouldRetryTransientConnectionFailure(path: path, method: method);
    for (
      var attempt = 0;
      attempt < (retryTransientConnectionFailure ? 2 : 1);
      attempt++
    ) {
      try {
        res = await sendJsonAttempt(
          currentHeaders: headers,
          closeConnection: preferFreshConnection || attempt > 0,
        );
        lastTransientConnectionError = null;
        break;
      } catch (error) {
        lastTransientConnectionError = error;
        final canRetry =
            retryTransientConnectionFailure &&
            attempt == 0 &&
            _isTransientConnectionFailure(error);
        if (!canRetry) {
          rethrow;
        }
        debugPrint(
          '[BackendApi] Retrying $method $path after transient connection '
          'failure: $error',
        );
        await Future<void>.delayed(const Duration(milliseconds: 260));
      }
    }
    if (lastTransientConnectionError != null) {
      throw lastTransientConnectionError;
    }

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
        res = await sendJsonAttempt(
          currentHeaders: headers,
          closeConnection: preferFreshConnection,
        );
      }
    }

    final normalizedMethod = method.toUpperCase();
    final allowRateLimitRetry =
        normalizedMethod == 'GET' ||
        (normalizedMethod == 'PUT' && path == '/api/users/profile');
    if (allowRateLimitRetry && res.statusCode == 429) {
      for (var attempt = 1; attempt <= 2; attempt++) {
        final waitMs = 350 * attempt;
        await Future<void>.delayed(Duration(milliseconds: waitMs));
        res = await sendJsonAttempt(
          currentHeaders: headers,
          closeConnection: preferFreshConnection,
        );
        if (res.statusCode != 429) break;
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
      _logApiSecurityEvent(
        path: path,
        method: method,
        statusCode: res.statusCode,
        outcome: 'error',
      );
      if (path == '/api/users/profile' && normalizedMethod == 'PUT') {
        debugPrint('[ProfileUpdate] HTTP ${res.statusCode} response received');
      }
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
    _enforceAbuseProtection(path, method);
    final trimmedBearerOverride = bearerOverride?.trim();
    final usesBearerOverride =
        trimmedBearerOverride != null && trimmedBearerOverride.isNotEmpty;
    final preferFreshConnection = _shouldPreferFreshConnection(path);
    final allowTransientConnectionRetry =
        !_isAiOrRagPath(path) || _apiBaseUrls.length <= 1;
    final effectiveRequireAuthToken =
        requireAuthToken || _shouldRequireAuthForPath(path, method);
    Object? lastError;
    final candidateUris = _backendUris(path);
    for (final uri in candidateUris) {
      try {
        return await _requestJsonAtUri(
          uri,
          path: path,
          method: method,
          body: body,
          timeout: timeout,
          requireAuthToken: effectiveRequireAuthToken,
          bearerOverride: bearerOverride,
          securityContext: securityContext,
          includeRecaptchaToken: includeRecaptchaToken,
          recaptchaAction: recaptchaAction,
          usesBearerOverride: usesBearerOverride,
          preferFreshConnection: preferFreshConnection,
          allowTransientConnectionRetry: allowTransientConnectionRetry,
        );
      } catch (error) {
        lastError = error;
        if (!_shouldFallbackToNextBaseUrl(error, path, method)) {
          rethrow;
        }
        debugPrint(
          '[BackendApi] Retrying $method $path on next backend base URL '
          'after transport failure: $error',
        );
        await Future<void>.delayed(const Duration(milliseconds: 260));
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    throw Exception('API request failed for $path');
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
        'description': ?description,
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
    String? imageFileId,
    String? authorName,
    required BuildContext context,
  }) async {
    return _requestJson(
      '/api/chat/messages',
      method: 'POST',
      body: <String, dynamic>{
        'roomId': roomId,
        'content': content,
        'imageUrl': ?imageUrl,
        'imageFileId': ?imageFileId,
        'authorName': ?authorName,
      },
    );
  }

  Future<Map<String, dynamic>> uploadChatImage({
    required PlatformFile file,
  }) async {
    final token = await _getIdToken();
    final uri = Uri.parse('$_baseUrl/api/chat/messages/upload-image');
    final request = http.MultipartRequest('POST', uri);

    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('image', file.bytes!, filename: file.name),
      );
    } else if (file.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          file.path!,
          filename: file.name,
        ),
      );
    } else {
      throw BackendApiHttpException(
        statusCode: 400,
        message: 'Image data is unavailable for upload.',
      );
    }

    final streamed = await _sendStreamedRequest(request);
    final body = await streamed.stream.bytesToString();
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw BackendApiHttpException(
        statusCode: streamed.statusCode,
        message: 'Chat image upload failed (${streamed.statusCode}): $body',
      );
    }

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final message =
          data['message']?.toString() ??
          data['error']?.toString() ??
          'Chat image upload failed';
      throw BackendApiHttpException(
        statusCode: streamed.statusCode,
        message: message,
      );
    }

    return data;
  }

  Future<Map<String, dynamic>> getChatRoomInfo(String roomId) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/info',
      method: 'GET',
    );
  }

  Future<List<Map<String, dynamic>>> getChatRoomMembers(String roomId) async {
    final data = await _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/members',
      method: 'GET',
    );
    final list = (data['members'] as List?) ?? const [];
    return list
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  Future<Map<String, dynamic>> updateRoomCodeVisibility({
    required String roomId,
    required bool showRoomCode,
  }) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/code-visibility',
      method: 'PATCH',
      body: {'showRoomCode': showRoomCode},
      requireAuthToken: true,
    );
  }

  Future<Map<String, dynamic>> updateRoomMemberRole({
    required String roomId,
    required String targetEmail,
    required String role,
  }) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/members/role',
      method: 'PATCH',
      body: {'targetEmail': targetEmail, 'role': role},
      requireAuthToken: true,
    );
  }

  Future<Map<String, dynamic>> removeRoomMember({
    required String roomId,
    required String targetEmail,
  }) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/members',
      method: 'DELETE',
      body: {'targetEmail': targetEmail},
      requireAuthToken: true,
    );
  }

  Future<Map<String, dynamic>> deleteChatRoom(String roomId) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}',
      method: 'DELETE',
    );
  }

  Future<Map<String, dynamic>> banRoomMember({
    required String roomId,
    required String targetEmail,
  }) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/ban',
      method: 'POST',
      body: {'targetEmail': targetEmail},
    );
  }

  Future<Map<String, dynamic>> unbanRoomMember({
    required String roomId,
    required String targetEmail,
  }) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/unban',
      method: 'POST',
      body: {'targetEmail': targetEmail},
    );
  }

  Future<Map<String, dynamic>> regenerateChatRoomCode(String roomId) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/regenerate-code',
      method: 'POST',
    );
  }

  Future<Map<String, dynamic>> toggleChatRoomMute({
    required String roomId,
    required bool muted,
  }) async {
    return _requestJson(
      '/api/chat/rooms/${Uri.encodeComponent(roomId)}/mute',
      method: 'POST',
      body: {'muted': muted},
    );
  }

  Future<Map<String, dynamic>> updateChatMessage({
    required String messageId,
    required String content,
    String? imageUrl,
    BuildContext? context,
  }) async {
    return _requestJson(
      '/api/chat/messages/${Uri.encodeComponent(messageId)}',
      method: 'PUT',
      body: <String, dynamic>{'content': content, 'imageUrl': ?imageUrl},
    );
  }

  Future<void> deleteChatMessage({
    required String messageId,
    BuildContext? context,
  }) async {
    await _requestJson(
      '/api/chat/messages/${Uri.encodeComponent(messageId)}',
      method: 'DELETE',
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

  Future<Map<String, dynamic>> getAcademicCatalog() async {
    return _requestJson('/api/academics/catalog', method: 'GET');
  }

  Future<Map<String, dynamic>> syncKietAttendance({
    required String collegeId,
    required String cybervidyaToken,
    required BuildContext context,
  }) async {
    Future<Map<String, dynamic>> performSync({
      required bool includeRecaptcha,
    }) async {
      final maxAttempts = includeRecaptcha ? 2 : 1;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          return await _requestJson(
            '/api/attendance/kiet/sync',
            method: 'POST',
            body: {'collegeId': collegeId, 'cybervidyaToken': cybervidyaToken},
            securityContext: includeRecaptcha ? context : null,
            includeRecaptchaToken: includeRecaptcha,
            recaptchaAction: 'attendance_sync',
            requireAuthToken: true,
          );
        } catch (error) {
          final shouldRetry =
              _isKietSyncTransientFailure(error) && attempt < maxAttempts;
          if (!shouldRetry) rethrow;
          final delay = Duration(milliseconds: 500 * attempt);
          await Future<void>.delayed(delay);
        }
      }
      throw Exception('Attendance sync failed after retries');
    }

    try {
      return await performSync(includeRecaptcha: true);
    } catch (error) {
      if (!_isRecaptchaTransientFailure(error)) rethrow;
      debugPrint(
        'Attendance sync security check failed on mobile; retrying without recaptcha token: $error',
      );
      return performSync(includeRecaptcha: false);
    }
  }

  Future<Map<String, dynamic>> getKietAttendanceDaywise({
    required String collegeId,
    required String cybervidyaToken,
    required int courseId,
    required int courseComponentId,
    int? studentId,
  }) async {
    return _requestJson(
      '/api/attendance/kiet/daywise',
      method: 'POST',
      body: {
        'collegeId': collegeId,
        'cybervidyaToken': cybervidyaToken,
        'courseId': courseId,
        'courseComponentId': courseComponentId,
        'studentId': ?studentId,
      },
      requireAuthToken: true,
    );
  }

  Future<Map<String, dynamic>> resolveResourceScopes({
    required Map<String, dynamic> selectedScope,
  }) async {
    return _requestJson(
      '/api/resources/resolve-scopes',
      method: 'POST',
      body: {'selectedScope': selectedScope},
    );
  }

  Future<Map<String, dynamic>> planResourceUpload({
    required String filename,
    required String contentType,
    required int sizeBytes,
    required String fileSha256,
    required String type,
    required Map<String, dynamic> selectedScope,
  }) async {
    return _requestJson(
      '/api/resources/upload-plan',
      method: 'POST',
      body: <String, dynamic>{
        'filename': filename,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        'fileSha256': fileSha256,
        'type': type,
        'selectedScope': selectedScope,
      },
    );
  }

  Future<Map<String, dynamic>> listResources({
    String? branch,
    String? semester,
    String? subject,
    String? type,
    String? search,
    int? page,
    int? limit,
  }) async {
    final query = <String, String>{};
    if (branch != null && branch.trim().isNotEmpty && branch != 'all') {
      query['branch'] = branch.trim();
    }
    if (semester != null && semester.trim().isNotEmpty && semester != 'all') {
      query['semester'] = semester.trim();
    }
    if (subject != null && subject.trim().isNotEmpty && subject != 'all') {
      query['subject'] = subject.trim();
    }
    if (type != null && type.trim().isNotEmpty && type != 'all') {
      query['type'] = type.trim();
    }
    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }
    if (page != null && page > 0) {
      query['page'] = page.toString();
    }
    if (limit != null && limit > 0) {
      query['limit'] = limit.toString();
    }

    final uri = Uri(path: '/api/resources', queryParameters: query);
    final path = uri.toString();
    return _requestJson(path, method: 'GET');
  }

  Future<Map<String, dynamic>> getMyResources() async {
    return _requestJson('/api/resources/mine', method: 'GET');
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

  Future<Map<String, dynamic>> getBulkResourceStates({
    required Iterable<String> resourceIds,
  }) async {
    final ids = resourceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return const {'states': <Map<String, dynamic>>[]};
    }

    return _requestJson(
      '/api/resources/state',
      method: 'POST',
      body: <String, dynamic>{'resourceIds': ids},
    );
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
    _cleanupExpiredBookmarkCheckRateLimits();
    final cooldownUntil = _bookmarkCheckRateLimitUntil[itemId];
    if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil)) {
      return false;
    }

    try {
      final data = await _requestJson(
        '/api/bookmarks/check/${Uri.encodeComponent(itemId)}',
        method: 'GET',
      );
      _bookmarkCheckRateLimitUntil.remove(itemId);
      return data['isBookmarked'] == true;
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('rate limit') || message.contains('429')) {
        _cleanupExpiredBookmarkCheckRateLimits();
        _bookmarkCheckRateLimitUntil[itemId] = DateTime.now().add(
          const Duration(seconds: 20),
        );
      }
      debugPrint('checkBookmark failed for $itemId: $e');
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
    final data = await _requestJson(query.toString(), method: 'GET');
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
    String? fileType,
  }) async {
    final normalizedImageUrl = imageUrl?.trim();
    final normalizedFileUrl = fileUrl?.trim();
    final normalizedFileType = fileType?.trim().toLowerCase();
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
        // Both keys sent for backend compat: older endpoints read 'imageUrl',
        // newer ones read 'fileUrl'.
        'imageUrl': ?effectiveAttachmentUrl,
        'fileUrl': ?effectiveAttachmentUrl,
        'fileType': ?normalizedFileType,
      },
    );
  }

  Future<Map<String, dynamic>> setNoticeVisibility({
    required String noticeId,
    required bool isActive,
  }) async {
    return _requestJson(
      '${_noticePath(noticeId)}/visibility',
      method: 'PATCH',
      body: <String, dynamic>{'isActive': isActive},
    );
  }

  Future<void> deleteNotice({required String noticeId}) async {
    await _requestJson(_noticePath(noticeId), method: 'DELETE');
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
      body: <String, dynamic>{'content': content, 'parentId': ?parentId},
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
      body['photo_url'] = profilePhotoUrl.trim();
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
      // reCAPTCHA is intentionally omitted on mobile: the write is already
      // protected by Firebase ID-token auth.  Including reCAPTCHA breaks
      // native Flutter builds where RecaptchaService is unavailable.
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
        'planId': ?planId,
        'rechargeRupees': ?rechargeRupees,
        'amount': ?amount,
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
    final cooldownUntil = _notificationsRateLimitUntil;
    if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil)) {
      return List<Map<String, dynamic>>.from(_lastNotificationsCache);
    }

    try {
      final data = await _requestJson(
        '/api/notifications?limit=$limit&offset=$offset',
        method: 'GET',
      );
      _notificationsRateLimitUntil = null;
      final list = (data['notifications'] as List?) ?? const [];
      final notifications = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _lastNotificationsCache = notifications;
      return notifications;
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('rate limit') || message.contains('429')) {
        _notificationsRateLimitUntil = DateTime.now().add(
          const Duration(seconds: 20),
        );
        return List<Map<String, dynamic>>.from(_lastNotificationsCache);
      }
      debugPrint('Backend /api/notifications query failed. Bubbling up: $e');
      rethrow;
    }
  }

  Future<void> markNotificationRead(Object id) async {
    await _requestJson(
      '/api/notifications/${Uri.encodeComponent(id.toString())}/read',
      method: 'POST',
    );
  }

  Future<void> markAllNotificationsRead() async {
    await _requestJson('/api/notifications/read-all', method: 'POST');
  }

  Future<void> deleteNotification(Object id) async {
    await _requestJson(
      '/api/notifications/${Uri.encodeComponent(id.toString())}',
      method: 'DELETE',
    );
  }

  // ----------------------------
  // Follow / Unfollow
  // ----------------------------

  /// Check current user's follow relationship with [targetEmail].
  /// Returns a map with at least a {'status': String} key.
  Future<Map<String, dynamic>> checkFollowStatus(String targetEmail) async {
    final encoded = Uri.encodeComponent(targetEmail.trim());
    try {
      return await _requestJson('/api/follow/status/$encoded', method: 'GET');
    } on BackendApiHttpException catch (e) {
      if (isBackendCompatibilityFallbackError(e)) {
        try {
          return await _requestJson(
            '/api/follows/status?targetEmail=$encoded',
            method: 'GET',
          );
        } on BackendApiHttpException catch (fallbackError) {
          if (isBackendCompatibilityFallbackError(fallbackError)) {
            return await _requestJson(
              '/api/users/${Uri.encodeComponent(targetEmail.trim())}/follow-status',
              method: 'GET',
            );
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// Send a follow request to the user identified by [targetEmail].
  Future<Map<String, dynamic>> sendFollowRequest(
    String targetEmail, {
    BuildContext? context,
  }) async {
    try {
      return await _requestJson(
        '/api/follow/request',
        method: 'POST',
        body: {'targetEmail': targetEmail.trim()},
        requireAuthToken: true,
      );
    } on BackendApiHttpException catch (e) {
      if (isBackendCompatibilityFallbackError(e)) {
        try {
          return await _requestJson(
            '/api/follows',
            method: 'POST',
            body: {'targetEmail': targetEmail.trim()},
            requireAuthToken: true,
          );
        } on BackendApiHttpException catch (fallbackError) {
          if (isBackendCompatibilityFallbackError(fallbackError)) {
            return await _requestJson(
              '/api/users/${Uri.encodeComponent(targetEmail.trim())}/follow',
              method: 'POST',
              requireAuthToken: true,
            );
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// Unfollow a user identified by [targetEmail].
  Future<void> unfollowUser(String targetEmail, {BuildContext? context}) async {
    final encoded = Uri.encodeComponent(targetEmail.trim());
    try {
      await _requestJson(
        '/api/follow/$encoded',
        method: 'DELETE',
        requireAuthToken: true,
      );
      return;
    } on BackendApiHttpException catch (e) {
      if (isBackendCompatibilityFallbackError(e)) {
        try {
          await _requestJson(
            '/api/follows/$encoded',
            method: 'DELETE',
            requireAuthToken: true,
          );
          return;
        } on BackendApiHttpException catch (fallbackError) {
          if (isBackendCompatibilityFallbackError(fallbackError)) {
            await _requestJson(
              '/api/users/$encoded/unfollow',
              method: 'POST',
              requireAuthToken: true,
            );
            return;
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// Cancel a pending follow request by its [requestId].
  Future<void> cancelFollowRequest(
    int requestId, {
    BuildContext? context,
  }) async {
    try {
      await _requestJson(
        '/api/follow/request/$requestId',
        method: 'DELETE',
        requireAuthToken: true,
      );
      return;
    } on BackendApiHttpException catch (e) {
      if (isBackendCompatibilityFallbackError(e)) {
        try {
          await _requestJson(
            '/api/follows/requests/$requestId',
            method: 'DELETE',
            requireAuthToken: true,
          );
          return;
        } on BackendApiHttpException catch (fallbackError) {
          if (isBackendCompatibilityFallbackError(fallbackError)) {
            await _requestJson(
              '/api/follows/$requestId/cancel',
              method: 'POST',
              requireAuthToken: true,
            );
            return;
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<int> getUnreadNotificationCount() async {
    try {
      final data = await _requestJson(
        '/api/notifications/unread-count',
        method: 'GET',
      );
      final countRaw = data['count'] ?? data['unreadCount'] ?? data['unread'];
      if (countRaw is num) {
        _lastUnreadNotificationCount = countRaw.toInt();
        return _lastUnreadNotificationCount!;
      }
      final parsed = int.tryParse(countRaw?.toString() ?? '');
      if (parsed != null) {
        _lastUnreadNotificationCount = parsed;
        return parsed;
      }
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('rate limit') || message.contains('429')) {
        return _lastUnreadNotificationCount ?? 0;
      }
      // Fallback below for backward compatibility.
    }

    final notifications = await getNotifications(limit: 200, offset: 0);
    final unreadCount = notifications.where((notification) {
      final isReadRaw = notification.containsKey('is_read')
          ? notification['is_read']
          : notification['isRead'];
      if (isReadRaw is bool) return !isReadRaw;
      return isReadRaw?.toString().toLowerCase() != 'true';
    }).length;
    _lastUnreadNotificationCount = unreadCount;
    return unreadCount;
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
        'reason': ?reason,
        'collegeId': ?collegeId,
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

  Future<List<Map<String, dynamic>>> listModerationResources({
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
      'limit': pageSize.toString(),
      if (collegeId != null && collegeId.trim().isNotEmpty)
        'college_id': collegeId.trim(),
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      if (semester != null && semester.trim().isNotEmpty)
        'semester': semester.trim(),
      if (branch != null && branch.trim().isNotEmpty) 'branch': branch.trim(),
      if (subject != null && subject.trim().isNotEmpty)
        'subject': subject.trim(),
    };

    Map<String, dynamic> data;
    try {
      data = await _requestJson(
        Uri(
          path: '/api/resources/moderation',
          queryParameters: queryParams,
        ).toString(),
        method: 'GET',
        bearerOverride: bearerToken,
        requireAuthToken: true,
      );
    } on BackendApiHttpException catch (error) {
      if (!isBackendCompatibilityFallbackError(error)) rethrow;
      return listAdminResources(
        bearerToken: bearerToken,
        collegeId: collegeId,
        status: status,
        semester: semester,
        branch: branch,
        subject: subject,
        page: page,
        pageSize: pageSize,
      );
    }

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
        'academicYear': ?academicYear,
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
        'college_id': ?collegeId,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
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
        'college_id': ?collegeId,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
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
        'college_id': ?collegeId,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
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
  }) async {
    return _requestJson(
      '/api/ai/find',
      method: 'POST',
      timeout: _aiRequestTimeout,
      body: <String, dynamic>{
        'file_id': fileId,
        'query': query,
        'college_id': ?collegeId,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
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
    String? videoUrl,
    bool? useOcr,
    bool? forceOcr,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, String>>? history,
    Map<String, dynamic>? filters,
    bool? sourceSwitchForTurn,
    List<String>? excludeFileIds,
    String? dialectIntensity,
    String? languageHint,
  }) async {
    final response = await _requestJson(
      '/api/rag/query',
      method: 'POST',
      timeout: _aiRequestTimeout,
      body: <String, dynamic>{
        'question': question,
        'college_id': ?collegeId,
        'session_id': ?sessionId,
        'top_k': ?topK,
        'min_score': ?minScore,
        'allow_web': allowWeb == true,
        // Keep only one retrieval selector to avoid duplicated semantics.
        'retrieval_mode': allowWeb == true ? 'web' : 'local',
        'strict_notes_mode': allowWeb != true,
        'file_id': ?fileId,
        'video_url': ?videoUrl,
        'use_ocr': ?useOcr,
        'force_ocr': ?forceOcr,
        'attachments': ?attachments,
        'history': ?history,
        'filters': ?filters,
        'source_switch_for_turn': ?sourceSwitchForTurn,
        'exclude_file_ids': ?excludeFileIds,
        'dialect_intensity': ?dialectIntensity,
        'language_hint': ?languageHint,
      },
    );
    return _normalizeRagResponse(response);
  }

  Map<String, dynamic> _normalizeRagResponse(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map) return response;

    final normalized = Map<String, dynamic>.from(response);
    final nested = Map<String, dynamic>.from(data);
    const mirroredKeys = <String>[
      'answer',
      'response',
      'sources',
      'primary_source',
      'primary_source_file_id',
      'no_local',
      'retrieval_score',
      'llm_confidence_score',
      'combined_confidence',
      'source_switch_applied',
      'retrieval_mode',
      'dialect_intensity_used',
      'tone_profile_used',
      'ocr_failure_affects_retrieval',
      'ocr_errors',
      'answer_origin',
      'strict_notes_mode',
    ];

    for (final key in mirroredKeys) {
      if (normalized[key] == null && nested[key] != null) {
        normalized[key] = nested[key];
      }
    }

    return normalized;
  }

  Map<String, dynamic> _normalizeRagSourceEntry(Map<dynamic, dynamic> item) {
    final normalized = Map<String, dynamic>.from(item);
    final rawFileUrl =
        normalized['file_url']?.toString().trim() ??
        normalized['source_url']?.toString().trim() ??
        normalized['url']?.toString().trim() ??
        normalized['href']?.toString().trim() ??
        '';
    final rawVideoUrl =
        normalized['video_url']?.toString().trim() ??
        normalized['youtube_url']?.toString().trim() ??
        '';
    final existingType = normalized['source_type']
        ?.toString()
        .trim()
        .toLowerCase();
    final looksLikeYoutube =
        rawVideoUrl.toLowerCase().contains('youtu') ||
        rawFileUrl.toLowerCase().contains('youtu');
    final looksLikePdf =
        rawFileUrl.toLowerCase().contains('.pdf') ||
        rawFileUrl.toLowerCase().contains('/pdf') ||
        rawFileUrl.toLowerCase().contains('application/pdf');

    if (normalized['file_url'] == null && rawFileUrl.isNotEmpty) {
      normalized['file_url'] = rawFileUrl;
    }
    if (normalized['video_url'] == null && rawVideoUrl.isNotEmpty) {
      normalized['video_url'] = rawVideoUrl;
    }
    if ((existingType == null || existingType.isEmpty) &&
        (rawFileUrl.isNotEmpty || rawVideoUrl.isNotEmpty)) {
      normalized['source_type'] = looksLikeYoutube
          ? 'youtube'
          : (looksLikePdf ? 'pdf' : 'web');
    }

    return normalized;
  }

  bool _ragPayloadContainsAnswerText(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final data = decoded.cast<String, dynamic>();
        final type = data['type']?.toString();
        if (type == 'metadata' || type == 'done') {
          return false;
        }
        final text =
            data['text']?.toString() ??
            data['answer']?.toString() ??
            data['response']?.toString() ??
            data['message']?.toString() ??
            '';
        return text.trim().isNotEmpty;
      }
      if (decoded is String) {
        return decoded.trim().isNotEmpty;
      }
    } catch (_) {
      return payload.trim().isNotEmpty;
    }
    return false;
  }

  Future<Map<String, dynamic>> uploadNotebookSource({
    required String filePath,
    required String collegeId,
    String? notebookId,
    String? title,
    String? sourceScope,
  }) async {
    _enforceAbuseProtection('/api/notebooks/sources/upload', 'POST');
    final token = await _getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Authentication required');
    }
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
    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await _sendStreamedRequest(request);
    final body = await streamed.stream.bytesToString();
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw BackendApiHttpException(
        statusCode: streamed.statusCode,
        message:
            'Notebook source upload failed (${streamed.statusCode}): $body',
      );
    }

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final message =
          data['message']?.toString() ??
          data['error_code']?.toString() ??
          data['error']?.toString() ??
          'Notebook source upload failed';
      throw BackendApiHttpException(
        statusCode: streamed.statusCode,
        message: message,
      );
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
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (ocrErrorCode != null && ocrErrorCode.isNotEmpty)
          'ocr_error_code': ocrErrorCode,
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
      body: <String, dynamic>{
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
  }

  Future<Map<String, dynamic>> cancelNotebookSourceRetry({
    required String sourceId,
    String? reason,
  }) async {
    return _requestJson(
      '/api/notebooks/sources/${Uri.encodeComponent(sourceId)}/cancel-retry',
      method: 'POST',
      body: <String, dynamic>{
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
  }

  Future<Map<String, dynamic>> cancelNotebookSourceReupload({
    required String sourceId,
    String? reason,
  }) async {
    return cancelNotebookSourceRetry(sourceId: sourceId, reason: reason);
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
    String? videoUrl,
    bool? useOcr,
    bool? forceOcr,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, String>>? history,
    Map<String, dynamic>? filters,
    bool? sourceSwitchForTurn,
    List<String>? excludeFileIds,
    String? dialectIntensity,
    String? languageHint,
  }) async* {
    final response = await queryRag(
      question: question,
      collegeId: collegeId,
      sessionId: sessionId,
      topK: topK,
      minScore: minScore,
      allowWeb: allowWeb,
      fileId: fileId,
      videoUrl: videoUrl,
      useOcr: useOcr,
      forceOcr: forceOcr,
      attachments: attachments,
      history: history,
      filters: filters,
      sourceSwitchForTurn: sourceSwitchForTurn,
      excludeFileIds: excludeFileIds,
      dialectIntensity: dialectIntensity,
      languageHint: languageHint,
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
        .map(_normalizeRagSourceEntry)
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
    final ocrErrors =
        response['ocr_errors'] ?? (data is Map ? data['ocr_errors'] : null);
    final primarySource =
        response['primary_source'] ??
        (data is Map ? data['primary_source'] : null);
    final primarySourceFileId =
        response['primary_source_file_id'] ??
        (data is Map ? data['primary_source_file_id'] : null);
    final sourceSwitchApplied =
        response['source_switch_applied'] ??
        (data is Map ? data['source_switch_applied'] : null);
    final retrievalMode =
        response['retrieval_mode'] ??
        (data is Map ? data['retrieval_mode'] : null);
    final dialectIntensityUsed =
        response['dialect_intensity_used'] ??
        (data is Map ? data['dialect_intensity_used'] : null);
    final toneProfileUsed =
        response['tone_profile_used'] ??
        (data is Map ? data['tone_profile_used'] : null);
    final answerOrigin =
        response['answer_origin'] ??
        (data is Map ? data['answer_origin'] : null);
    final strictNotesMode =
        response['strict_notes_mode'] ??
        (data is Map ? data['strict_notes_mode'] : null);

    final hasOcrDiagnostics =
        ocrFailureAffectsRetrieval == true ||
        (ocrErrors is List && ocrErrors.isNotEmpty);
    if (normalizedSources.isNotEmpty ||
        noLocal ||
        answerOrigin != null ||
        hasOcrDiagnostics) {
      yield jsonEncode({
        'type': 'metadata',
        'data': <String, dynamic>{
          'sources': normalizedSources,
          'primary_source': ?primarySource,
          'primary_source_file_id': ?primarySourceFileId,
          'no_local': noLocal,
          'retrieval_score': ?retrievalScore,
          'llm_confidence_score': ?llmConfidenceScore,
          'combined_confidence': ?combinedConfidence,
          'source_switch_applied': ?sourceSwitchApplied,
          'retrieval_mode': ?retrievalMode,
          'dialect_intensity_used': ?dialectIntensityUsed,
          'tone_profile_used': ?toneProfileUsed,
          'answer_origin': ?answerOrigin,
          'strict_notes_mode': ?strictNotesMode,
          'ocr_failure_affects_retrieval': ?ocrFailureAffectsRetrieval,
          'ocr_errors': ?ocrErrors,
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
    String? videoUrl,
    bool? useOcr,
    bool? forceOcr,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, String>>? history,
    Map<String, dynamic>? filters,
    bool? sourceSwitchForTurn,
    List<String>? excludeFileIds,
    String? dialectIntensity,
    String? languageHint,
  }) async* {
    const path = '/api/rag/query/stream';
    _enforceAbuseProtection(path, 'POST');

    Stream<String> fallbackStream() {
      return _queryRagAsSyntheticStream(
        question: question,
        collegeId: collegeId,
        sessionId: sessionId,
        topK: topK,
        minScore: minScore,
        allowWeb: allowWeb,
        fileId: fileId,
        videoUrl: videoUrl,
        useOcr: useOcr,
        forceOcr: forceOcr,
        attachments: attachments,
        history: history,
        filters: filters,
        sourceSwitchForTurn: sourceSwitchForTurn,
        excludeFileIds: excludeFileIds,
        dialectIntensity: dialectIntensity,
        languageHint: languageHint,
      );
    }

    final shouldPreferSyntheticStream =
        allowWeb != true && (useOcr == true || forceOcr == true);
    if (shouldPreferSyntheticStream) {
      debugPrint(
        '[BackendApi] Using synthetic stream for OCR-sensitive RAG request.',
      );
      yield* fallbackStream();
      return;
    }

    if (_ragStreamUnavailable) {
      final since = _ragStreamUnavailableSince;
      if (since != null &&
          DateTime.now().difference(since) > _ragStreamDisableTtl) {
        _ragStreamUnavailable = false;
        _ragStreamUnavailableSince = null;
      } else {
        yield* fallbackStream();
        return;
      }
    }

    final token = await _getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Authentication required');
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Connection': 'close',
      'Authorization': 'Bearer $token',
    };
    final requestBody = <String, dynamic>{
      'question': question,
      'college_id': ?collegeId,
      'session_id': ?sessionId,
      'top_k': ?topK,
      'min_score': ?minScore,
      'allow_web': allowWeb == true,
      // Keep only one retrieval selector to avoid duplicated semantics.
      'retrieval_mode': allowWeb == true ? 'web' : 'local',
      'strict_notes_mode': allowWeb != true,
      'file_id': ?fileId,
      'video_url': ?videoUrl,
      'use_ocr': ?useOcr,
      'force_ocr': ?forceOcr,
      'attachments': ?attachments,
      'history': ?history,
      'filters': ?filters,
      'source_switch_for_turn': ?sourceSwitchForTurn,
      'exclude_file_ids': ?excludeFileIds,
      'dialect_intensity': ?dialectIntensity,
      'language_hint': ?languageHint,
    };

    http.StreamedResponse? response;
    Object? lastTransportError;
    final candidateUris = _backendUris(path);
    for (var index = 0; index < candidateUris.length; index++) {
      final uri = candidateUris[index];
      try {
        response = await _sendStreamedRequestAtUri(
          uri: uri,
          headers: headers,
          body: requestBody,
        );
        lastTransportError = null;
        break;
      } catch (error) {
        lastTransportError = error;
        final shouldTryNext =
            index < candidateUris.length - 1 &&
            _shouldFallbackToNextBaseUrl(error, path, 'POST');
        if (!shouldTryNext) {
          break;
        }
        debugPrint(
          '[BackendApi] Retrying stream request on next backend base URL '
          'after transport failure: $error',
        );
        await Future<void>.delayed(const Duration(milliseconds: 260));
      }
    }

    if (response == null && lastTransportError is TimeoutException) {
      final error = lastTransportError;
      debugPrint(
        '[BackendApi] Stream request timed out. Falling back to /api/rag/query. '
        '$error',
      );
      yield* fallbackStream();
      return;
    }
    if (response == null && lastTransportError is SocketException) {
      final error = lastTransportError;
      debugPrint(
        '[BackendApi] Stream socket failure. Falling back to /api/rag/query. '
        '$error',
      );
      yield* fallbackStream();
      return;
    }
    if (response == null && lastTransportError is http.ClientException) {
      final error = lastTransportError;
      debugPrint(
        '[BackendApi] Stream client failure. Falling back to /api/rag/query. '
        '$error',
      );
      yield* fallbackStream();
      return;
    }
    if (response == null) {
      if (lastTransportError != null) throw lastTransportError;
      yield* fallbackStream();
      return;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _logApiSecurityEvent(
        path: path,
        method: 'POST',
        statusCode: response.statusCode,
        outcome: 'stream_error',
      );
      final body = await response.stream.bytesToString();
      if (_shouldFallbackRagStreamStatus(response.statusCode)) {
        if (_isUnsupportedRagStreamStatus(response.statusCode)) {
          _ragStreamUnavailable = true;
          _ragStreamUnavailableSince = DateTime.now();
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

    var receivedPayload = false;
    var receivedAnswerPayload = false;
    final lineStream = response.stream
        .timeout(_streamIdleTimeout)
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    try {
      await for (final line in lineStream) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        receivedPayload = true;
        receivedAnswerPayload =
            receivedAnswerPayload || _ragPayloadContainsAnswerText(payload);
        yield payload;
      }
      if (!receivedAnswerPayload) {
        debugPrint(
          '[BackendApi] Stream completed without answer chunks. '
          'Falling back to /api/rag/query.',
        );
        yield* fallbackStream();
        return;
      }
    } on TimeoutException catch (error) {
      debugPrint(
        '[BackendApi] Stream stalled while reading response. '
        '${receivedPayload ? 'Finishing partial stream.' : 'Falling back to /api/rag/query. '}'
        '$error',
      );
      if (!receivedAnswerPayload) {
        yield* fallbackStream();
        return;
      }
      yield jsonEncode({'type': 'done'});
    } on SocketException catch (error) {
      debugPrint(
        '[BackendApi] Stream socket interrupted. '
        '${receivedPayload ? 'Finishing partial stream.' : 'Falling back to /api/rag/query. '}'
        '$error',
      );
      if (!receivedAnswerPayload) {
        yield* fallbackStream();
        return;
      }
      yield jsonEncode({'type': 'done'});
    } on http.ClientException catch (error) {
      debugPrint(
        '[BackendApi] Stream client interrupted. '
        '${receivedPayload ? 'Finishing partial stream.' : 'Falling back to /api/rag/query. '}'
        '$error',
      );
      if (!receivedAnswerPayload) {
        yield* fallbackStream();
        return;
      }
      yield jsonEncode({'type': 'done'});
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
  // Follows & Users (additional)
  // ----------------------------

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
}
