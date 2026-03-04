import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/college.dart';
import '../models/resource.dart';
import '../models/user.dart';
import 'backend_api_service.dart';
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
  static const Duration _profileCacheTtl = Duration(seconds: 45);
  static const Duration _resourcesCacheTtl = Duration(seconds: 20);
  static const Duration _filterValuesCacheTtl = Duration(minutes: 5);
  static const int _maxResourceListCacheEntries = 24;
  static const int _maxFilterValuesCacheEntries = 24;
  static final ValueNotifier<int> aiTokenRefreshNotifier = ValueNotifier<int>(
    0,
  );

  SupabaseClient get _client => Supabase.instance.client;
  final BackendApiService _api = BackendApiService();
  static Map<String, dynamic>? _cachedCurrentUserProfile;
  static String? _cachedCurrentUserProfileEmail;
  static DateTime? _cachedCurrentUserProfileAt;
  static Future<Map<String, dynamic>>? _currentUserProfileFetchFuture;
  static final Map<String, ({DateTime cachedAt, List<Resource> data})>
  _resourceListCache = <String, ({DateTime cachedAt, List<Resource> data})>{};
  static final Map<String, Future<List<Resource>>> _resourceListInFlight =
      <String, Future<List<Resource>>>{};
  static final Map<String, ({DateTime cachedAt, List<String> data})>
  _uniqueValuesCache = <String, ({DateTime cachedAt, List<String> data})>{};
  static final Map<String, bool> _bookmarkStateCache = <String, bool>{};
  static final Map<String, ({int? userVote, int upvotes, int downvotes})>
  _voteStateCache = <String, ({int? userVote, int upvotes, int downvotes})>{};
  static ({
    bool hasUserEmail,
    bool hasUserId,
    bool hasMessageId,
    bool hasPostId,
    bool hasRoomId,
    bool hasCreatedAt,
  })?
  _savedPostsSchemaCache;
  static DateTime? _savedPostsSchemaCachedAt;
  static const Duration _savedPostsSchemaCacheTtl = Duration(minutes: 15);

  /// A BuildContext is required to run reCAPTCHA (invisible WebView) before privileged writes.
  /// Set this once from a top-level screen (e.g. HomeScreen) via [attachContext].
  static BuildContext? _ctx;

  void attachContext(BuildContext context) {
    _ctx = context;
  }

  String? get currentUserEmail => _client.auth.currentUser?.email;
  String? get currentUserId => _client.auth.currentUser?.id;

  String _currentSessionEmail() {
    final supabaseEmail = _normalizeEmail(currentUserEmail);
    if (supabaseEmail.isNotEmpty) return supabaseEmail;
    final firebaseEmail = _normalizeEmail(
      firebase_auth.FirebaseAuth.instance.currentUser?.email,
    );
    return firebaseEmail;
  }

  String _normalizeEmail(String? email) => email?.trim().toLowerCase() ?? '';

  String _resourceStateKey(String resourceId, {String? userEmail}) {
    final normalizedInputEmail = _normalizeEmail(userEmail);
    final scopedEmail = normalizedInputEmail.isNotEmpty
        ? normalizedInputEmail
        : _currentSessionEmail();
    return '$scopedEmail::$resourceId';
  }

  bool _hasFreshCurrentUserProfileCacheFor(String email) {
    if (email.isEmpty) return false;
    final cachedAt = _cachedCurrentUserProfileAt;
    if (cachedAt == null) return false;
    return _cachedCurrentUserProfile != null &&
        _cachedCurrentUserProfileEmail == email &&
        DateTime.now().difference(cachedAt) < _profileCacheTtl;
  }

  void _cacheCurrentUserProfile(String email, Map<String, dynamic> profile) {
    if (email.isEmpty || profile.isEmpty) return;
    _cachedCurrentUserProfile = Map<String, dynamic>.from(profile);
    _cachedCurrentUserProfileEmail = email;
    _cachedCurrentUserProfileAt = DateTime.now();
  }

  void invalidateCurrentUserProfileCache() {
    _cachedCurrentUserProfile = null;
    _cachedCurrentUserProfileEmail = null;
    _cachedCurrentUserProfileAt = null;
  }

  void markAiTokenBalanceStale() {
    invalidateCurrentUserProfileCache();
    aiTokenRefreshNotifier.value = aiTokenRefreshNotifier.value + 1;
  }

  void invalidateResourceListCache() {
    _resourceListCache.clear();
    _resourceListInFlight.clear();
  }

  String _resourceListCacheKey({
    required String collegeId,
    String? semester,
    String? branch,
    String? subject,
    String? type,
    String? searchQuery,
    String? sortBy,
    required int limit,
    required int offset,
  }) {
    final normalizedSearch = searchQuery?.trim().toLowerCase() ?? '';
    return [
      collegeId.trim(),
      semester?.trim().toLowerCase() ?? '',
      branch?.trim().toLowerCase() ?? '',
      subject?.trim().toLowerCase() ?? '',
      type?.trim().toLowerCase() ?? '',
      normalizedSearch,
      sortBy?.trim().toLowerCase() ?? '',
      limit.toString(),
      offset.toString(),
    ].join('|');
  }

  String _uniqueValuesCacheKey({
    required String column,
    required String collegeId,
    String? branch,
  }) {
    return [
      column.trim().toLowerCase(),
      collegeId.trim(),
      branch?.trim().toLowerCase() ?? '',
    ].join('|');
  }

  void _pruneResourceListCacheIfNeeded() {
    while (_resourceListCache.length > _maxResourceListCacheEntries) {
      final oldest = _resourceListCache.entries.reduce(
        (a, b) => a.value.cachedAt.isBefore(b.value.cachedAt) ? a : b,
      );
      _resourceListCache.remove(oldest.key);
    }
  }

  void _pruneUniqueValuesCacheIfNeeded() {
    while (_uniqueValuesCache.length > _maxFilterValuesCacheEntries) {
      final oldest = _uniqueValuesCache.entries.reduce(
        (a, b) => a.value.cachedAt.isBefore(b.value.cachedAt) ? a : b,
      );
      _uniqueValuesCache.remove(oldest.key);
    }
  }

  String _normalizeRoleValue(String? role) {
    final raw = role?.trim().toUpperCase() ?? '';
    switch (raw) {
      case 'ADMIN':
        return AppRoles.admin;
      case 'MODERATOR':
        return AppRoles.moderator;
      case 'COLLEGE_USER':
        return AppRoles.collegeUser;
      case 'TEACHER':
        return AppRoles.teacher;
      case 'READ_ONLY':
        return AppRoles.readOnly;
      case 'STUDENT':
        return AppRoles.collegeUser;
      default:
        return AppRoles.readOnly;
    }
  }

  String _resolveEffectiveRole(Map<String, dynamic> profile) {
    final normalizedRole = _normalizeRoleValue(profile['role']?.toString());
    final adminKey = profile['admin_key']?.toString().trim() ?? '';
    if (adminKey.isNotEmpty &&
        normalizedRole != AppRoles.admin &&
        normalizedRole != AppRoles.teacher) {
      return AppRoles.teacher;
    }
    return normalizedRole;
  }

  bool _isDuplicateKeyError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('duplicate key') || message.contains('23505');
  }

  bool _isMissingColumnError(Object error, String column) {
    final message = error.toString().toLowerCase();
    return message.contains('column') &&
        message.contains(column.toLowerCase()) &&
        message.contains('does not exist');
  }

  bool _isStatusColumnMissingError(Object error) {
    return _isMissingColumnError(error, 'status');
  }

  Future<List<Map<String, dynamic>>> _fetchAcceptedOrApprovedFollows({
    required String selectColumns,
    required String filterColumn,
    required dynamic filterValue,
  }) async {
    try {
      final withStatuses = await _client
          .from('follows')
          .select(selectColumns)
          .eq(filterColumn, filterValue)
          .inFilter('status', ['accepted', 'approved']);
      return List<Map<String, dynamic>>.from(withStatuses);
    } catch (e) {
      if (!_isStatusColumnMissingError(e)) rethrow;
      final withoutStatus = await _client
          .from('follows')
          .select(selectColumns)
          .eq(filterColumn, filterValue);
      return List<Map<String, dynamic>>.from(withoutStatus);
    }
  }

  Future<int> _countAcceptedOrApprovedFollows({
    required String filterColumn,
    required dynamic filterValue,
  }) async {
    try {
      return await _client
          .from('follows')
          .count(CountOption.exact)
          .eq(filterColumn, filterValue)
          .inFilter('status', ['accepted', 'approved']);
    } catch (e) {
      if (!_isStatusColumnMissingError(e)) rethrow;
      return await _client
          .from('follows')
          .count(CountOption.exact)
          .eq(filterColumn, filterValue);
    }
  }

  bool _isRowLevelSecurityError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('row-level security') ||
        message.contains('violates row-level security policy') ||
        message.contains('42501');
  }

  bool _isAdminUploadAuthError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('unauthorized') ||
        message.contains('forbidden') ||
        message.contains('invalid admin') ||
        message.contains('admin key') ||
        message.contains('expired') ||
        message.contains('401') ||
        message.contains('403');
  }

  bool _isAdminUploadTransientError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('connection reset') ||
        message.contains('connection refused') ||
        message.contains('network') ||
        message.contains('429') ||
        message.contains('503');
  }

  bool _isAdminUploadServerError(Object error) {
    // Intentionally excludes transient errors to avoid overlapping classification.
    final message = error.toString().toLowerCase();
    final has5xxCode = RegExp(r'\b5\d\d\b').hasMatch(message);
    return !_isAdminUploadTransientError(error) &&
        (has5xxCode ||
            message.contains('internal server error') ||
            message.contains('service unavailable'));
  }

  Future<({int? userVote, int upvotes, int downvotes})> getResourceVoteStatus(
    String resourceId,
  ) async {
    final key = _resourceStateKey(resourceId);
    final cached = _voteStateCache[key];
    if (cached != null) {
      return cached;
    }

    try {
      final data = await _api.getVoteStatus(resourceId);
      final rawVote = data['userVote'];
      int? userVote;
      if (rawVote is String) {
        if (rawVote == 'upvote') {
          userVote = 1;
        } else if (rawVote == 'downvote') {
          userVote = -1;
        }
      } else if (rawVote is num) {
        userVote = rawVote.toInt();
      }

      final upvotesRaw = data['upvotes'] ?? data['up_votes'] ?? 0;
      final downvotesRaw = data['downvotes'] ?? data['down_votes'] ?? 0;

      final resolved = (
        userVote: userVote,
        upvotes: upvotesRaw is num ? upvotesRaw.toInt() : 0,
        downvotes: downvotesRaw is num ? downvotesRaw.toInt() : 0,
      );
      _voteStateCache[key] = resolved;
      return resolved;
    } catch (e) {
      debugPrint('Error fetching resource vote status: $e');
      return (userVote: null, upvotes: 0, downvotes: 0);
    }
  }

  Map<String, dynamic> _normalizeSocialUser(Map<String, dynamic> raw) {
    final email = (raw['email'] ?? raw['user_email'] ?? '').toString();
    final displayName =
        (raw['display_name'] ??
                raw['name'] ??
                raw['user_name'] ??
                (email.isNotEmpty ? email.split('@').first : 'User'))
            .toString();
    final username =
        (raw['username'] ?? (email.isNotEmpty ? email.split('@').first : null))
            ?.toString();
    final photoUrl =
        (raw['profile_photo_url'] ?? raw['photo_url'] ?? raw['avatar_url'])
            ?.toString();

    return {
      'email': email,
      'display_name': displayName,
      'profile_photo_url': photoUrl,
      'photo_url': photoUrl,
      'username': username,
    };
  }

  List<Map<String, dynamic>> _normalizeSocialUsers(dynamic rows) {
    if (rows is! List) return [];
    final normalized = rows
        .whereType<Map>()
        .map((entry) => _normalizeSocialUser(Map<String, dynamic>.from(entry)))
        .where((entry) => (entry['email'] ?? '').toString().isNotEmpty)
        .toList();

    final deduped = <String, Map<String, dynamic>>{};
    for (final user in normalized) {
      deduped[_normalizeEmail(user['email']?.toString())] = user;
    }
    return deduped.values.toList();
  }

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
        for (final user in result) {
          final userId = user['id'];
          if (userId != null) {
            deduped[userId] = user;
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
    final normalizedSemester = semester?.trim();
    final normalizedBranch = branch?.trim();
    final normalizedSubject = subject?.trim();
    final normalizedType = type?.trim();
    final normalizedSearch = searchQuery?.trim() ?? '';
    final cacheKey = _resourceListCacheKey(
      collegeId: collegeId,
      semester: normalizedSemester,
      branch: normalizedBranch,
      subject: normalizedSubject,
      type: normalizedType,
      searchQuery: normalizedSearch,
      sortBy: sortBy,
      limit: limit,
      offset: offset,
    );
    final shouldUseCache = offset == 0 && normalizedSearch.isEmpty;

    if (shouldUseCache) {
      final cached = _resourceListCache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.cachedAt) < _resourcesCacheTtl) {
        return List<Resource>.from(cached.data);
      }

      final pending = _resourceListInFlight[cacheKey];
      if (pending != null) {
        return List<Resource>.from(await pending);
      }
    }

    final fetchFuture = () async {
      try {
        debugPrint(
          'SupabaseService.getResources: collegeId=$collegeId, semester=$normalizedSemester, branch=$normalizedBranch, type=$normalizedType',
        );

        var query = _client
            .from('resources')
            .select()
            .eq('college_id', collegeId)
            .eq('status', 'approved');

        if (normalizedSemester != null && normalizedSemester.isNotEmpty) {
          query = query.eq('semester', normalizedSemester);
        }
        if (normalizedBranch != null && normalizedBranch.isNotEmpty) {
          query = query.ilike('branch', '%$normalizedBranch%');
        }
        if (normalizedSubject != null && normalizedSubject.isNotEmpty) {
          query = query.ilike('subject', '%$normalizedSubject%');
        }
        if (normalizedType != null && normalizedType.isNotEmpty) {
          query = query.ilike('type', normalizedType);
        }
        if (normalizedSearch.isNotEmpty) {
          query = query.ilike('title', '%$normalizedSearch%');
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
        final rows = (response as List)
            .whereType<Map>()
            .map((json) => Resource.fromJson(Map<String, dynamic>.from(json)))
            .toList();

        debugPrint(
          'SupabaseService.getResources: returned ${rows.length} resources',
        );

        if (shouldUseCache) {
          _resourceListCache[cacheKey] = (
            cachedAt: DateTime.now(),
            data: List<Resource>.unmodifiable(rows),
          );
          _pruneResourceListCacheIfNeeded();
        }

        return rows;
      } catch (e) {
        debugPrint('Error fetching resources: $e');
        rethrow;
      }
    }();

    if (shouldUseCache) {
      _resourceListInFlight[cacheKey] = fetchFuture;
    }

    try {
      return List<Resource>.from(await fetchFuture);
    } finally {
      if (shouldUseCache) {
        _resourceListInFlight.remove(cacheKey);
      }
    }
  }

  /// Get resources from users the current user follows
  Future<List<Resource>> _fetchApprovedResourcesByUploaderEmails({
    required String collegeId,
    required List<String> uploaderEmails,
    int limit = 20,
    int offset = 0,
  }) async {
    final normalizedEmails = uploaderEmails
        .map(_normalizeEmail)
        .where((email) => email.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedEmails.isEmpty) return [];

    try {
      final response = await _client
          .from('resources')
          .select()
          .eq('college_id', collegeId)
          .eq('status', 'approved')
          .inFilter('uploaded_by_email', normalizedEmails)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final rows = (response as List)
          .map((json) => Resource.fromJson(json as Map<String, dynamic>))
          .toList();
      if (rows.isNotEmpty) {
        return rows;
      }
    } catch (e) {
      debugPrint(
        'Following feed exact-email query failed, falling back to '
        'case-insensitive filter: $e',
      );
    }

    // Fallback for schemas/data with mixed-case email values.
    try {
      final fetchWindow = (limit * 8).clamp(80, 240).toInt();
      final raw = await _client
          .from('resources')
          .select()
          .eq('college_id', collegeId)
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .range(0, offset + fetchWindow - 1);
      final emailSet = normalizedEmails.toSet();
      final filtered = (raw as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where(
            (row) => emailSet.contains(
              _normalizeEmail(row['uploaded_by_email']?.toString()),
            ),
          )
          .skip(offset)
          .take(limit)
          .map(Resource.fromJson)
          .toList();
      return filtered;
    } catch (fallbackError) {
      debugPrint('Following feed fallback query failed: $fallbackError');
      return [];
    }
  }

  Future<List<Resource>> getFollowingFeed({
    required String userEmail,
    required String collegeId,
    int limit = 20,
    int offset = 0,
  }) async {
    final normalizedEmail = _normalizeEmail(userEmail);
    final activeUserEmail = normalizedEmail.isNotEmpty
        ? normalizedEmail
        : _currentSessionEmail();
    if (activeUserEmail.isEmpty) return [];

    // Primary path: backend endpoint already handles follow schema variants.
    try {
      final followingPayload = await _api.getFollowing();
      final followingRows = List<Map<String, dynamic>>.from(
        followingPayload['following'] ?? const [],
      );
      final followingEmails = followingRows
          .map(
            (row) => _normalizeEmail(
              row['email']?.toString() ??
                  row['user_email']?.toString() ??
                  row['following_email']?.toString(),
            ),
          )
          .where((email) => email.isNotEmpty)
          .toSet()
          .toList();

      if (followingEmails.isNotEmpty) {
        return _fetchApprovedResourcesByUploaderEmails(
          collegeId: collegeId,
          uploaderEmails: followingEmails,
          limit: limit,
          offset: offset,
        );
      }
    } catch (e) {
      debugPrint('Error fetching following feed via backend endpoint: $e');
    }

    try {
      final identifiers = await _resolveUserIdentifiers(activeUserEmail);
      List<String> followingIds = [];

      for (final id in identifiers) {
        final followsResponse = await _fetchAcceptedOrApprovedFollows(
          selectColumns: 'following_id',
          filterColumn: 'follower_id',
          filterValue: id,
        );

        final ids = followsResponse
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
          return _fetchApprovedResourcesByUploaderEmails(
            collegeId: collegeId,
            uploaderEmails: followingEmails,
            limit: limit,
            offset: offset,
          );
        }
      }
    } catch (e) {
      debugPrint('Error fetching following feed (id): $e');
    }

    // Fallback: email-based follows
    try {
      final followsResponse = await _fetchAcceptedOrApprovedFollows(
        selectColumns: 'following_email',
        filterColumn: 'follower_email',
        filterValue: activeUserEmail,
      );

      final followingEmails = followsResponse
          .map((r) => r['following_email'] as String?)
          .whereType<String>()
          .toList();

      if (followingEmails.isEmpty) return [];

      return _fetchApprovedResourcesByUploaderEmails(
        collegeId: collegeId,
        uploaderEmails: followingEmails,
        limit: limit,
        offset: offset,
      );
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

  /// Update a room member role (admin/member).
  Future<void> updateRoomMemberRole({
    required String roomId,
    required String userEmail,
    required String role,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedRole != 'admin' && normalizedRole != 'member') {
      throw Exception('Invalid role: $role');
    }

    try {
      await _client
          .from('room_members')
          .update({'role': normalizedRole})
          .eq('room_id', roomId)
          .eq('user_email', userEmail);
    } catch (e) {
      debugPrint('Error updating room member role: $e');
      rethrow;
    }
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
  }) async {
    // Backend handles this
  }

  // ============ NOTIFICATIONS & REQUESTS ============

  /// Get recent notifications
  Future<List<Map<String, dynamic>>> getNotifications({int limit = 50}) async {
    try {
      return await _api.getNotifications(limit: limit);
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      return [];
    }
  }

  /// Mark notification as read
  Future<void> markNotificationRead(String notificationId) async {
    try {
      final ctx = _ctx;
      await _api.markNotificationRead(notificationId, contextForRecaptcha: ctx);
    } catch (e) {
      debugPrint('Error marking notification read: $e');
    }
  }

  Future<Map<String, dynamic>> getCurrentUserProfile({
    int maxAttempts = 3,
    bool forceRefresh = false,
  }) async {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'maxAttempts must be >= 1',
      );
    }
    if (forceRefresh) {
      invalidateCurrentUserProfileCache();
    }
    final email = _currentSessionEmail();
    if (!forceRefresh && _hasFreshCurrentUserProfileCacheFor(email)) {
      return Map<String, dynamic>.from(_cachedCurrentUserProfile!);
    }

    if (_currentUserProfileFetchFuture != null) {
      return _currentUserProfileFetchFuture!;
    }

    _currentUserProfileFetchFuture = () async {
      Object? lastError;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final payload = await _api.getProfile();
          final profile =
              (payload['profile'] as Map?)?.cast<String, dynamic>() ??
              payload.cast<String, dynamic>();
          if (profile.isNotEmpty) {
            _cacheCurrentUserProfile(email, profile);
            return profile;
          }
          lastError = Exception('Empty profile payload');
        } catch (e) {
          lastError = e;
        }

        if (attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 250 * attempt));
        }
      }

      if (lastError != null) {
        debugPrint(
          'Error resolving current user profile after $maxAttempts attempts: '
          '$lastError',
        );
      }
      if (_cachedCurrentUserProfile != null &&
          _cachedCurrentUserProfileEmail == email) {
        return Map<String, dynamic>.from(_cachedCurrentUserProfile!);
      }
      return <String, dynamic>{};
    }();

    try {
      return await _currentUserProfileFetchFuture!;
    } finally {
      _currentUserProfileFetchFuture = null;
    }
  }

  Future<String> getCurrentUserRole() async {
    final profile = await getCurrentUserProfile(maxAttempts: 1);
    if (profile.isEmpty) return AppRoles.readOnly;
    return _resolveEffectiveRole(profile);
  }

  Future<void> addNotice({
    required String collegeId,
    required String title,
    required String content,
    String department = 'general',
    String? imageUrl,
  }) async {
    try {
      await _api.createNotice(
        collegeId: collegeId,
        title: title,
        content: content,
        department: department,
        imageUrl: imageUrl,
      );
      return;
    } catch (e) {
      debugPrint('Backend notice post failed, retrying via Supabase: $e');
    }

    final email = _normalizeEmail(currentUserEmail);
    if (email.isEmpty) {
      throw Exception('Please sign in to post notices');
    }

    final userInfo = await getUserInfo(email);
    final displayName =
        userInfo?['display_name']?.toString().trim().isNotEmpty == true
        ? userInfo!['display_name'].toString().trim()
        : email.split('@').first;

    final payload = <String, dynamic>{
      'college_id': collegeId,
      'title': title,
      'content': content,
      'department': department,
      'created_by': email,
      'created_by_name': displayName,
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
      if (imageUrl != null && imageUrl.isNotEmpty) 'file_url': imageUrl,
    };

    try {
      await _client.from('notices').insert(payload);
    } catch (e) {
      debugPrint('Error posting notice: $e');
      rethrow;
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
    final normalizedTarget = _normalizeEmail(userEmail);
    final normalizedCurrent = _currentSessionEmail();

    try {
      if (normalizedTarget.isNotEmpty &&
          normalizedTarget == normalizedCurrent) {
        final res = await _api.getFollowers();
        return _normalizeSocialUsers(res['followers']);
      }

      final identifiers = await _resolveUserIdentifiers(normalizedTarget);
      if (identifiers.isNotEmpty) {
        List<String> followerIds = [];
        for (final id in identifiers) {
          final response = await _fetchAcceptedOrApprovedFollows(
            selectColumns: 'follower_id',
            filterColumn: 'following_id',
            filterValue: id,
          );

          final ids = response
              .map((r) => r['follower_id'] as String?)
              .whereType<String>()
              .toList();

          if (ids.isNotEmpty) {
            followerIds = ids;
            break;
          }
        }

        if (followerIds.isNotEmpty) {
          final usersResponse = await _fetchUsersByIds(followerIds);
          final normalized = _normalizeSocialUsers(usersResponse);
          if (normalized.isNotEmpty) return normalized;
        }
      }
    } catch (e) {
      debugPrint('Error getting followers: $e');
    }

    // Fallback: email-based follows (older schema)
    try {
      final response = await _fetchAcceptedOrApprovedFollows(
        selectColumns: 'follower_email',
        filterColumn: 'following_email',
        filterValue: normalizedTarget,
      );

      final followerEmails = response
          .map((r) => r['follower_email'] as String?)
          .whereType<String>()
          .toList();

      if (followerEmails.isEmpty) return [];

      final usersResponse = await _client
          .from('users')
          .select('email, display_name, profile_photo_url, username, photo_url')
          .inFilter('email', followerEmails);

      return _normalizeSocialUsers(usersResponse);
    } catch (e) {
      debugPrint('Error getting followers (email fallback): $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFollowing(String userEmail) async {
    final normalizedTarget = _normalizeEmail(userEmail);
    final normalizedCurrent = _currentSessionEmail();

    try {
      if (normalizedTarget.isNotEmpty &&
          normalizedTarget == normalizedCurrent) {
        final res = await _api.getFollowing();
        return _normalizeSocialUsers(res['following']);
      }

      final identifiers = await _resolveUserIdentifiers(normalizedTarget);
      if (identifiers.isNotEmpty) {
        List<String> followingIds = [];
        for (final id in identifiers) {
          final response = await _fetchAcceptedOrApprovedFollows(
            selectColumns: 'following_id',
            filterColumn: 'follower_id',
            filterValue: id,
          );

          final ids = response
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
          final normalized = _normalizeSocialUsers(usersResponse);
          if (normalized.isNotEmpty) return normalized;
        }
      }
    } catch (e) {
      debugPrint('Error getting following: $e');
    }

    // Fallback: email-based follows (older schema)
    try {
      final response = await _fetchAcceptedOrApprovedFollows(
        selectColumns: 'following_email',
        filterColumn: 'follower_email',
        filterValue: normalizedTarget,
      );

      final followingEmails = response
          .map((r) => r['following_email'] as String?)
          .whereType<String>()
          .toList();

      if (followingEmails.isEmpty) return [];

      final usersResponse = await _client
          .from('users')
          .select('email, display_name, profile_photo_url, username, photo_url')
          .inFilter('email', followingEmails);

      return _normalizeSocialUsers(usersResponse);
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
      final raw = List<Map<String, dynamic>>.from(res['bookmarks'] ?? []);
      return raw.map((item) {
        final normalized = Map<String, dynamic>.from(item);
        normalized['resource_id'] ??= normalized['resourceId'];
        normalized['notice_id'] ??= normalized['noticeId'];
        normalized['created_at'] ??= normalized['createdAt'];
        final type =
            normalized['type'] ??
            (normalized['resource_id'] != null ? 'resource' : 'notice');
        normalized['type'] = type;
        if (type == 'resource') {
          normalized['resource'] ??= normalized['content'];
        } else if (type == 'notice') {
          normalized['notice'] ??= normalized['content'];
        }
        // Unknown types: content not mapped to avoid incorrect field assignment
        return normalized;
      }).toList();
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
      if (_normalizeEmail(userEmail) == _currentSessionEmail()) {
        final res = await _api.getFollowers();
        final list = List<Map<String, dynamic>>.from(res['followers'] ?? []);
        return list.length;
      }

      final identifiers = await _resolveUserIdentifiers(userEmail);
      var maxCount = 0;

      if (identifiers.isNotEmpty) {
        for (final id in identifiers) {
          try {
            final withStatus = await _countAcceptedOrApprovedFollows(
              filterColumn: 'following_id',
              filterValue: id,
            );
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
        final emailCount = await _countAcceptedOrApprovedFollows(
          filterColumn: 'following_email',
          filterValue: userEmail.toLowerCase(),
        );
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
      if (_normalizeEmail(userEmail) == _currentSessionEmail()) {
        final res = await _api.getFollowing();
        final list = List<Map<String, dynamic>>.from(res['following'] ?? []);
        return list.length;
      }

      final identifiers = await _resolveUserIdentifiers(userEmail);
      var maxCount = 0;

      if (identifiers.isNotEmpty) {
        for (final id in identifiers) {
          try {
            final withStatus = await _countAcceptedOrApprovedFollows(
              filterColumn: 'follower_id',
              filterValue: id,
            );
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
        final emailCount = await _countAcceptedOrApprovedFollows(
          filterColumn: 'follower_email',
          filterValue: userEmail.toLowerCase(),
        );
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
    final cacheKey = _uniqueValuesCacheKey(
      column: column,
      collegeId: collegeId,
      branch: branch,
    );
    final cached = _uniqueValuesCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _filterValuesCacheTtl) {
      return List<String>.from(cached.data);
    }

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
      final resolved = values.cast<String>();
      _uniqueValuesCache[cacheKey] = (
        cachedAt: DateTime.now(),
        data: List<String>.unmodifiable(resolved),
      );
      _pruneUniqueValuesCacheIfNeeded();
      return resolved;
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
      // Vote changes can affect ordering/counts in resource feeds.
      invalidateResourceListCache();
      _voteStateCache.remove(
        _resourceStateKey(resourceId, userEmail: userEmail),
      );
      // The backend handles the logic of toggling/updating and returns the new counts,
      // but here we just need to ensure the request succeeds.
    } catch (e) {
      debugPrint('Error voting on resource: $e');
      rethrow;
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

  Future<bool> _savedPostsColumnExists(String column) async {
    try {
      await _client.from('saved_posts').select(column).limit(1);
      return true;
    } catch (e) {
      if (_isMissingColumnError(e, column)) {
        return false;
      }
      rethrow;
    }
  }

  Future<
    ({
      bool hasUserEmail,
      bool hasUserId,
      bool hasMessageId,
      bool hasPostId,
      bool hasRoomId,
      bool hasCreatedAt,
    })
  >
  _getSavedPostsSchema() async {
    final cached = _savedPostsSchemaCache;
    final cachedAt = _savedPostsSchemaCachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _savedPostsSchemaCacheTtl) {
      return cached;
    }

    final checks = await Future.wait<bool>([
      _savedPostsColumnExists('user_email'),
      _savedPostsColumnExists('user_id'),
      _savedPostsColumnExists('message_id'),
      _savedPostsColumnExists('post_id'),
      _savedPostsColumnExists('room_id'),
      _savedPostsColumnExists('created_at'),
    ]);

    final schema = (
      hasUserEmail: checks[0],
      hasUserId: checks[1],
      hasMessageId: checks[2],
      hasPostId: checks[3],
      hasRoomId: checks[4],
      hasCreatedAt: checks[5],
    );
    _savedPostsSchemaCache = schema;
    _savedPostsSchemaCachedAt = DateTime.now();
    return schema;
  }

  Set<String> _resolveSavedPostUserIds() {
    final ids = <String>{};
    final supabaseId = (currentUserId ?? '').trim();
    if (supabaseId.isNotEmpty) {
      ids.add(supabaseId);
    }
    final firebaseId = firebase_auth.FirebaseAuth.instance.currentUser?.uid
        .toString()
        .trim();
    if (firebaseId != null && firebaseId.isNotEmpty) {
      ids.add(firebaseId);
    }
    return ids;
  }

  List<({String column, String value})> _savedPostUserFilters(
    ({
      bool hasUserEmail,
      bool hasUserId,
      bool hasMessageId,
      bool hasPostId,
      bool hasRoomId,
      bool hasCreatedAt,
    })
    schema,
    String userEmail,
  ) {
    final filters = <({String column, String value})>[];
    final normalizedEmail = _normalizeEmail(userEmail);
    if (schema.hasUserEmail && normalizedEmail.isNotEmpty) {
      filters.add((column: 'user_email', value: normalizedEmail));
    }
    if (schema.hasUserId) {
      for (final id in _resolveSavedPostUserIds()) {
        if (id.isEmpty) continue;
        filters.add((column: 'user_id', value: id));
      }
    }
    return filters;
  }

  List<String> _savedPostMessageColumns(
    ({
      bool hasUserEmail,
      bool hasUserId,
      bool hasMessageId,
      bool hasPostId,
      bool hasRoomId,
      bool hasCreatedAt,
    })
    schema,
  ) {
    final columns = <String>[];
    if (schema.hasMessageId) columns.add('message_id');
    if (schema.hasPostId) columns.add('post_id');
    return columns;
  }

  Future<Set<String>> _collectSavedPostRowIdsDirect(
    String postId,
    String userEmail,
  ) async {
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) return {};

    final schema = await _getSavedPostsSchema();
    final userFilters = _savedPostUserFilters(schema, userEmail);
    final messageColumns = _savedPostMessageColumns(schema);
    if (userFilters.isEmpty || messageColumns.isEmpty) {
      return {};
    }

    final rowIds = <String>{};

    for (final filter in userFilters) {
      for (final messageColumn in messageColumns) {
        try {
          final rows = await _client
              .from('saved_posts')
              .select('id')
              .eq(filter.column, filter.value)
              .eq(messageColumn, normalizedPostId);

          for (final row in List<Map<String, dynamic>>.from(rows)) {
            final id = row['id']?.toString().trim() ?? '';
            if (id.isNotEmpty) {
              rowIds.add(id);
            }
          }
        } catch (e) {
          final ignoreMissing =
              _isMissingColumnError(e, filter.column) ||
              _isMissingColumnError(e, messageColumn);
          if (!ignoreMissing) {
            debugPrint(
              'saved_posts direct row lookup failed for '
              '${filter.column}/$messageColumn: $e',
            );
          }
        }
      }
    }

    return rowIds;
  }

  Future<Set<String>> _getSavedPostIdsDirect(String userEmail) async {
    final schema = await _getSavedPostsSchema();
    final userFilters = _savedPostUserFilters(schema, userEmail);
    final messageColumns = _savedPostMessageColumns(schema);
    if (userFilters.isEmpty || messageColumns.isEmpty) {
      return {};
    }

    final ids = <String>{};
    for (final filter in userFilters) {
      for (final messageColumn in messageColumns) {
        try {
          final rows = await _client
              .from('saved_posts')
              .select(messageColumn)
              .eq(filter.column, filter.value);

          for (final row in List<Map<String, dynamic>>.from(rows)) {
            final id = row[messageColumn]?.toString().trim() ?? '';
            if (id.isNotEmpty) {
              ids.add(id);
            }
          }
        } catch (e) {
          final ignoreMissing =
              _isMissingColumnError(e, filter.column) ||
              _isMissingColumnError(e, messageColumn);
          if (!ignoreMissing) {
            debugPrint(
              'saved_posts direct id fetch failed for '
              '${filter.column}/$messageColumn: $e',
            );
          }
        }
      }
    }
    return ids;
  }

  Future<List<Map<String, dynamic>>> _getSavedPostsDirect(
    String userEmail,
  ) async {
    final schema = await _getSavedPostsSchema();
    final userFilters = _savedPostUserFilters(schema, userEmail);
    final messageColumns = _savedPostMessageColumns(schema);
    if (userFilters.isEmpty || messageColumns.isEmpty) {
      return [];
    }

    final savedByMessage = <String, Map<String, dynamic>>{};

    for (final filter in userFilters) {
      for (final messageColumn in messageColumns) {
        final selectParts = <String>[messageColumn];
        if (schema.hasRoomId) selectParts.add('room_id');
        if (schema.hasCreatedAt) selectParts.add('created_at');

        try {
          final rows = schema.hasCreatedAt
              ? await _client
                    .from('saved_posts')
                    .select(selectParts.join(', '))
                    .eq(filter.column, filter.value)
                    .order('created_at', ascending: false)
              : await _client
                    .from('saved_posts')
                    .select(selectParts.join(', '))
                    .eq(filter.column, filter.value);
          for (final row in List<Map<String, dynamic>>.from(rows)) {
            final messageId = row[messageColumn]?.toString().trim() ?? '';
            if (messageId.isEmpty) continue;

            final savedAt = row['created_at']?.toString();
            final existing = savedByMessage[messageId];
            if (existing == null) {
              savedByMessage[messageId] = {
                'message_id': messageId,
                'room_id': row['room_id']?.toString(),
                'created_at': savedAt,
              };
              continue;
            }

            final existingTime = DateTime.tryParse(
              existing['created_at']?.toString() ?? '',
            );
            final currentTime = DateTime.tryParse(savedAt ?? '');
            if (existingTime == null ||
                (currentTime != null && currentTime.isAfter(existingTime))) {
              savedByMessage[messageId] = {
                'message_id': messageId,
                'room_id': row['room_id']?.toString(),
                'created_at': savedAt,
              };
            }
          }
        } catch (e) {
          final ignoreMissing =
              _isMissingColumnError(e, filter.column) ||
              _isMissingColumnError(e, messageColumn);
          if (!ignoreMissing) {
            debugPrint(
              'saved_posts direct list fetch failed for '
              '${filter.column}/$messageColumn: $e',
            );
          }
        }
      }
    }

    if (savedByMessage.isEmpty) return [];

    final messageIds = savedByMessage.keys.toList();
    final messageResponse = await _client
        .from('room_messages')
        .select('*, comment_count:room_post_comments(count)')
        .inFilter('id', messageIds);

    final messagesById = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(messageResponse)) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      row['comment_count'] = _normalizeCount(row['comment_count']);
      messagesById[id] = row;
    }

    final savedRows = savedByMessage.values.toList()
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '');
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

    final ordered = <Map<String, dynamic>>[];
    for (final saved in savedRows) {
      final id = saved['message_id']?.toString();
      if (id == null || id.isEmpty) continue;
      final message = messagesById[id];
      if (message == null) continue;
      ordered.add({
        ...message,
        '_saved_at': saved['created_at'],
        '_saved_room_id': saved['room_id']?.toString().trim().isNotEmpty == true
            ? saved['room_id']
            : message['room_id'],
      });
    }

    return ordered;
  }

  Future<void> _savePostDirect(
    String postId,
    String userEmail, {
    String? roomId,
  }) async {
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) {
      throw Exception('Post ID is required');
    }

    final schema = await _getSavedPostsSchema();
    final messageColumns = _savedPostMessageColumns(schema);
    if (messageColumns.isEmpty) {
      throw Exception('saved_posts schema missing message identifier columns');
    }

    final existingRowIds = await _collectSavedPostRowIdsDirect(
      normalizedPostId,
      userEmail,
    );
    if (existingRowIds.isNotEmpty) {
      return;
    }

    final payload = <String, dynamic>{messageColumns.first: normalizedPostId};
    final normalizedEmail = _normalizeEmail(userEmail);
    if (schema.hasUserEmail && normalizedEmail.isNotEmpty) {
      payload['user_email'] = normalizedEmail;
    }

    if (schema.hasUserId) {
      final resolvedIds = _resolveSavedPostUserIds();
      if (resolvedIds.isNotEmpty) {
        payload['user_id'] = resolvedIds.first;
      }
    }

    if (!payload.containsKey('user_email') && !payload.containsKey('user_id')) {
      throw Exception('Unable to resolve saved_posts user identifier');
    }

    if (schema.hasRoomId && roomId != null && roomId.trim().isNotEmpty) {
      payload['room_id'] = roomId.trim();
    }

    try {
      await _client.from('saved_posts').insert(payload);
    } catch (e) {
      if (_isDuplicateKeyError(e)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _unsavePostDirect(String postId, String userEmail) async {
    final existingRowIds = await _collectSavedPostRowIdsDirect(
      postId,
      userEmail,
    );
    if (existingRowIds.isEmpty) {
      return;
    }
    await _client
        .from('saved_posts')
        .delete()
        .inFilter('id', existingRowIds.toList());
  }

  Future<String> _resolveRoomIdForMessage(String messageId) async {
    final msg = await _client
        .from('room_messages')
        .select('room_id')
        .eq('id', messageId)
        .single();
    final roomId = msg['room_id']?.toString();
    if (roomId == null || roomId.isEmpty) {
      throw Exception('Unable to resolve room for message');
    }
    return roomId;
  }

  /// Save a post
  Future<void> savePost(
    String postId,
    String userEmail, {
    String? roomId,
  }) async {
    final normalizedEmail = _normalizeEmail(userEmail);

    try {
      await _savePostDirect(postId, normalizedEmail, roomId: roomId);
      return;
    } catch (directError) {
      debugPrint('Direct save_post failed, trying backend: $directError');
    }

    try {
      final resolvedRoomId = roomId ?? await _resolveRoomIdForMessage(postId);

      await _api.toggleSaveChatMessage(
        messageId: postId,
        roomId: resolvedRoomId,
      );
    } catch (e) {
      debugPrint('Error saving post: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _normalizeSavedPostFromBackend(
    Map<String, dynamic> raw,
  ) {
    final messageId =
        (raw['messageId'] ??
                raw['message_id'] ??
                raw['postId'] ??
                raw['post_id'] ??
                '')
            .toString()
            .trim();
    final savedRecordId = (raw['savedId'] ?? raw['saved_id'] ?? raw['id'] ?? '')
        .toString()
        .trim();
    final hasExplicitMessageField =
        raw.containsKey('messageId') ||
        raw.containsKey('message_id') ||
        raw.containsKey('postId') ||
        raw.containsKey('post_id');
    final effectiveMessageId = messageId.isNotEmpty
        ? messageId
        : (!hasExplicitMessageField ? savedRecordId : '');
    final roomId = (raw['roomId'] ?? raw['room_id'] ?? '').toString().trim();
    final savedAt = raw['savedAt'] ?? raw['saved_at'] ?? raw['created_at'];
    final postedAt = raw['postedAt'] ?? raw['posted_at'] ?? raw['created_at'];
    final content = (raw['content'] ?? raw['message'] ?? '').toString();
    final authorName = (raw['authorName'] ?? raw['author_name'] ?? 'Unknown')
        .toString();
    final authorEmail = (raw['authorEmail'] ?? raw['author_email'])?.toString();
    final imageUrl = (raw['imageUrl'] ?? raw['image_url'])?.toString();
    final upvotesRaw = raw['upvotes'] ?? raw['up_votes'];
    final downvotesRaw = raw['downvotes'] ?? raw['down_votes'];
    final commentCountRaw = raw['commentCount'] ?? raw['comment_count'];

    return {
      'id': effectiveMessageId,
      'message_id': effectiveMessageId,
      'content': content,
      'image_url': imageUrl,
      'author_name': authorName,
      'author_email': authorEmail,
      'created_at': postedAt,
      'upvotes': upvotesRaw is num ? upvotesRaw.toInt() : 0,
      'downvotes': downvotesRaw is num ? downvotesRaw.toInt() : 0,
      'comment_count': commentCountRaw is num ? commentCountRaw.toInt() : 0,
      'room_id': roomId,
      'room_name': raw['roomName'] ?? raw['room_name'],
      '_saved_at': savedAt,
      '_saved_room_id': roomId,
      '_saved_post_id': savedRecordId.isNotEmpty ? savedRecordId : null,
    };
  }

  Future<List<Map<String, dynamic>>> _getSavedPostsFromBackend() async {
    final saved = await _api.getSavedPosts();
    return saved
        .map(_normalizeSavedPostFromBackend)
        .where((row) => (row['id']?.toString().trim().isNotEmpty ?? false))
        .toList();
  }

  /// Check if a post is saved
  Future<bool> isPostSaved(String postId, String userEmail) async {
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) return false;

    try {
      final directSavedIds = await _getSavedPostIdsDirect(userEmail);
      if (directSavedIds.contains(normalizedPostId)) {
        return true;
      }
    } catch (e) {
      debugPrint('Direct isPostSaved lookup failed: $e');
    }

    try {
      final savedPosts = await _getSavedPostsFromBackend();
      return savedPosts.any((row) => row['id']?.toString() == normalizedPostId);
    } catch (_) {
      // Fallback to direct Supabase read for compatibility.
    }

    try {
      final response = await _client
          .from('saved_posts')
          .select('id')
          .eq('message_id', normalizedPostId)
          .eq('user_email', _normalizeEmail(userEmail))
          .maybeSingle();
      return response != null;
    } catch (e) {
      // Try checking if it's saved by message_id directly if legacy schema
      try {
        final response = await _client
            .from('saved_posts')
            .select('id')
            .eq('post_id', normalizedPostId)
            .eq('user_email', _normalizeEmail(userEmail))
            .maybeSingle();
        return response != null;
      } catch (e2) {
        return false;
      }
    }
  }

  /// Unsave a post
  Future<void> unsavePost(
    String postId,
    String userEmail, {
    String? roomId,
  }) async {
    final normalizedEmail = _normalizeEmail(userEmail);

    try {
      await _unsavePostDirect(postId, normalizedEmail);
      return;
    } catch (directError) {
      debugPrint('Direct unsave_post failed, trying backend: $directError');
    }

    try {
      final resolvedRoomId = roomId ?? await _resolveRoomIdForMessage(postId);

      await _api.toggleSaveChatMessage(
        messageId: postId,
        roomId: resolvedRoomId,
      );
    } catch (e) {
      debugPrint('Error unsaving post: $e');
      rethrow;
    }
  }

  /// Get all saved post IDs for a user (Batch Optimization)
  Future<Set<String>> getSavedPostIds(String userEmail) async {
    final combinedIds = <String>{};
    var hasAuthoritativeSource = false;

    try {
      final directIds = await _getSavedPostIdsDirect(userEmail);
      combinedIds.addAll(directIds);
      hasAuthoritativeSource = true;
    } catch (e) {
      debugPrint('Direct getSavedPostIds failed: $e');
    }

    try {
      final savedPosts = await _getSavedPostsFromBackend();
      combinedIds.addAll(
        savedPosts
            .map((row) => row['id']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>(),
      );
      hasAuthoritativeSource = true;
    } catch (_) {
      // Continue with legacy Supabase fallback.
    }

    if (hasAuthoritativeSource) {
      return combinedIds;
    }

    try {
      final normalizedEmail = _normalizeEmail(userEmail);
      final response = await _client
          .from('saved_posts')
          .select('message_id')
          .eq('user_email', normalizedEmail);

      return (response as List<dynamic>)
          .map((e) => e['message_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet();
    } catch (e) {
      try {
        final normalizedEmail = _normalizeEmail(userEmail);
        final fallback = await _client
            .from('saved_posts')
            .select('post_id')
            .eq('user_email', normalizedEmail);
        return (fallback as List<dynamic>)
            .map((e) => e['post_id']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>()
            .toSet();
      } catch (fallbackError) {
        debugPrint('Error fetching saved post IDs: $e | $fallbackError');
        return {};
      }
    }
  }

  /// Get all saved posts for a user
  Future<List<Map<String, dynamic>>> getSavedPosts(String userEmail) async {
    final merged = <String, Map<String, dynamic>>{};
    DateTime? parseSavedAt(Map<String, dynamic> row) => DateTime.tryParse(
      (row['_saved_at'] ?? row['savedAt'] ?? row['created_at'] ?? '')
          .toString(),
    );
    void mergeRows(List<Map<String, dynamic>> rows) {
      for (final row in rows) {
        final id = (row['id'] ?? row['message_id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final existing = merged[id];
        if (existing == null) {
          merged[id] = row;
          continue;
        }
        final existingTime = parseSavedAt(existing);
        final nextTime = parseSavedAt(row);
        if (existingTime == null ||
            (nextTime != null && nextTime.isAfter(existingTime))) {
          merged[id] = row;
        }
      }
    }

    try {
      mergeRows(await _getSavedPostsDirect(userEmail));
    } catch (e) {
      debugPrint('Direct getSavedPosts failed: $e');
    }

    try {
      final backendPosts = await _getSavedPostsFromBackend();
      mergeRows(backendPosts);
    } catch (_) {
      // Continue with legacy Supabase fallback.
    }

    if (merged.isNotEmpty) {
      final rows = merged.values.toList()
        ..sort((a, b) {
          final aTime = parseSavedAt(a);
          final bTime = parseSavedAt(b);
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });
      return rows;
    }

    try {
      final normalizedEmail = _normalizeEmail(userEmail);
      final savedRows = await _client
          .from('saved_posts')
          .select('message_id, room_id, created_at')
          .eq('user_email', normalizedEmail)
          .order('created_at', ascending: false);

      final rows = (savedRows as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      final messageIds = rows
          .map((row) => row['message_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();
      if (messageIds.isEmpty) return [];

      final messageResponse = await _client
          .from('room_messages')
          .select('*, comment_count:room_post_comments(count)')
          .inFilter('id', messageIds);

      final messagesById = <String, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(messageResponse)) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        row['comment_count'] = _normalizeCount(row['comment_count']);
        messagesById[id] = row;
      }

      final ordered = <Map<String, dynamic>>[];
      for (final saved in rows) {
        final id = saved['message_id']?.toString();
        if (id == null || id.isEmpty) continue;
        final msg = messagesById[id];
        if (msg == null) continue;
        ordered.add({
          ...msg,
          '_saved_at': saved['created_at'],
          '_saved_room_id': saved['room_id'],
        });
      }

      return ordered;
    } catch (e) {
      try {
        final normalizedEmail = _normalizeEmail(userEmail);
        final legacyRows = await _client
            .from('saved_posts')
            .select('post_id, room_id, created_at')
            .eq('user_email', normalizedEmail)
            .order('created_at', ascending: false);

        final rows = (legacyRows as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        final postIds = rows
            .map((row) => row['post_id']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>()
            .toList();
        if (postIds.isEmpty) return [];

        final messageResponse = await _client
            .from('room_messages')
            .select('*, comment_count:room_post_comments(count)')
            .inFilter('id', postIds);
        final messagesById = <String, Map<String, dynamic>>{};
        for (final row in List<Map<String, dynamic>>.from(messageResponse)) {
          final id = row['id']?.toString();
          if (id == null || id.isEmpty) continue;
          row['comment_count'] = _normalizeCount(row['comment_count']);
          messagesById[id] = row;
        }

        final ordered = <Map<String, dynamic>>[];
        for (final saved in rows) {
          final id = saved['post_id']?.toString();
          if (id == null || id.isEmpty) continue;
          final msg = messagesById[id];
          if (msg == null) continue;
          ordered.add({
            ...msg,
            '_saved_at': saved['created_at'],
            '_saved_room_id': saved['room_id'],
          });
        }
        return ordered;
      } catch (fallbackError) {
        debugPrint('Error fetching saved posts: $e | $fallbackError');
        return [];
      }
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
    Future<List<Map<String, dynamic>>> queryByDepartmentColumn(
      String departmentColumn,
    ) async {
      var query = _client
          .from('syllabus')
          .select()
          .eq('college_id', collegeId)
          .eq(departmentColumn, department);

      if (semester != null && semester.isNotEmpty && semester != 'All') {
        query = query.eq('semester', semester);
      }

      if (subject != null && subject.isNotEmpty && subject != 'All') {
        query = query.eq('subject', subject);
      }

      final response = await query.order('semester');
      return List<Map<String, dynamic>>.from(response);
    }

    try {
      final branchRows = await queryByDepartmentColumn('branch');
      if (branchRows.isNotEmpty) {
        return branchRows;
      }
    } catch (branchError) {
      if (_isMissingColumnError(branchError, 'college_id')) {
        debugPrint(
          'Syllabus table missing `college_id`; '
          'refusing unscoped syllabus query for security.',
        );
        return [];
      }
      debugPrint(
        'Syllabus query with `branch` failed, trying `department`: '
        '$branchError',
      );
    }

    // Legacy fallback for older schemas still using `department`.
    try {
      final departmentRows = await queryByDepartmentColumn('department');
      return departmentRows;
    } catch (departmentError) {
      if (_isMissingColumnError(departmentError, 'college_id')) {
        debugPrint(
          'Syllabus table missing `college_id`; '
          'refusing unscoped syllabus query for security.',
        );
        return [];
      }
      debugPrint('Error fetching syllabus with `department`: $departmentError');
      return [];
    }
  }

  Future<void> uploadSyllabus({
    required String collegeId,
    required String department,
    required String semester,
    required String subject,
    required String title,
    required String fileUrl,
    String? description,
  }) async {
    String adminKey = '';
    try {
      final profile = await getCurrentUserProfile(maxAttempts: 1);
      adminKey = profile['admin_key']?.toString().trim() ?? '';
    } catch (profileError) {
      debugPrint(
        'Unable to load profile for admin syllabus upload path; '
        'using direct insert fallback: $profileError',
      );
    }

    if (adminKey.isNotEmpty) {
      const maxAttempts = 2;
      var attempt = 0;
      while (attempt < maxAttempts) {
        attempt++;
        try {
          await _api.uploadSyllabusAsAdmin(
            adminKey: adminKey,
            collegeId: collegeId,
            semester: semester,
            branch: department,
            subject: subject,
            title: title,
            pdfUrl: fileUrl,
          );
          return;
        } catch (adminUploadError) {
          final isAuthError = _isAdminUploadAuthError(adminUploadError);
          final isTransientError = _isAdminUploadTransientError(
            adminUploadError,
          );
          final isServerError = _isAdminUploadServerError(adminUploadError);

          if (isAuthError) {
            debugPrint(
              'Admin syllabus upload auth failure (invalid/expired admin key); '
              'falling back to direct insert: $adminUploadError',
            );
            break;
          }

          if (isTransientError && attempt < maxAttempts) {
            debugPrint(
              'Transient admin syllabus upload error on attempt '
              '$attempt/$maxAttempts; retrying: $adminUploadError',
            );
            await Future.delayed(const Duration(milliseconds: 600));
            continue;
          }

          if (isTransientError) {
            debugPrint(
              'Transient admin syllabus upload error after retries; '
              'falling back to direct insert: $adminUploadError',
            );
            break;
          }

          if (isServerError) {
            debugPrint(
              'Admin syllabus upload server-side error; '
              'not falling back automatically: $adminUploadError',
            );
            rethrow;
          }

          debugPrint(
            'Admin syllabus upload failed with non-fallback error; rethrowing: '
            '$adminUploadError',
          );
          rethrow;
        }
      }
    }

    final payload = <String, dynamic>{
      'college_id': collegeId,
      'branch': department,
      'semester': semester,
      'subject': subject,
      'title': title,
      'description': description,
      'pdf_url': fileUrl,
      'file_url': fileUrl,
      'url': fileUrl,
      'created_by': _normalizeEmail(currentUserEmail),
    };

    try {
      await _client.from('syllabus').insert(payload);
      return;
    } catch (primaryError) {
      // Legacy schema fallback that uses `department` and may not have `pdf_url`.
      final fallback = <String, dynamic>{
        'college_id': collegeId,
        'department': department,
        'semester': semester,
        'subject': subject,
        'title': title,
        'description': description,
        'file_url': fileUrl,
        'url': fileUrl,
        'created_by': _normalizeEmail(currentUserEmail),
      };
      try {
        await _client.from('syllabus').insert(fallback);
        return;
      } catch (fallbackError) {
        debugPrint('Error uploading syllabus: $primaryError | $fallbackError');
        rethrow;
      }
    }
  }

  Future<List<Resource>> getPendingResourcesForTeacher({
    required String collegeId,
    String? branch,
    List<String> statuses = const ['pending'],
  }) async {
    try {
      var query = _client
          .from('resources')
          .select()
          .eq('college_id', collegeId);

      final normalizedStatuses = statuses
          .map((status) => status.trim().toLowerCase())
          .where((status) => status.isNotEmpty)
          .toSet()
          .toList();
      if (normalizedStatuses.isNotEmpty) {
        query = query.inFilter('status', normalizedStatuses);
      }

      if (branch != null && branch.trim().isNotEmpty) {
        query = query.eq('branch', branch.trim());
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List)
          .map((json) => Resource.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching pending resources: $e');
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
    final normalizedEmail = _normalizeEmail(userEmail);

    try {
      // Sync with users target array
      await _client.rpc(
        'add_followed_department',
        params: {'user_email': normalizedEmail, 'dept_id': departmentId},
      );
    } catch (e) {
      debugPrint('Error syncing followed_departments array: $e');
    }

    final userId = currentUserId;
    final payloads = <Map<String, dynamic>>[
      if (userId != null && userId.isNotEmpty)
        {
          'department_id': departmentId,
          'college_id': collegeId,
          'user_id': userId,
          'follower_email': normalizedEmail,
        },
      if (userId != null && userId.isNotEmpty)
        {
          'department_id': departmentId,
          'college_id': collegeId,
          'follower_id': userId,
          'follower_email': normalizedEmail,
        },
      if (userId != null && userId.isNotEmpty)
        {
          'department_id': departmentId,
          'college_id': collegeId,
          'user_id': userId,
          'user_email': normalizedEmail,
        },
      if (userId != null && userId.isNotEmpty)
        {
          'department_id': departmentId,
          'college_id': collegeId,
          'follower_id': userId,
          'user_email': normalizedEmail,
        },
      {
        'department_id': departmentId,
        'college_id': collegeId,
        'follower_email': normalizedEmail,
      },
      {'department_id': departmentId, 'follower_email': normalizedEmail},
      {
        'department_id': departmentId,
        'college_id': collegeId,
        'user_email': normalizedEmail,
      },
      {'department_id': departmentId, 'user_email': normalizedEmail},
      if (userId != null && userId.isNotEmpty)
        {'department_id': departmentId, 'user_id': userId},
      if (userId != null && userId.isNotEmpty)
        {'department_id': departmentId, 'follower_id': userId},
    ];

    Object? lastError;
    for (final payload in payloads) {
      try {
        await _client.from('department_followers').insert(payload);
        return;
      } catch (e) {
        if (_isDuplicateKeyError(e)) return;
        lastError = e;

        final hasSchemaMismatch = payload.keys.any(
          (key) => key != 'department_id' && _isMissingColumnError(e, key),
        );
        if (hasSchemaMismatch) {
          continue;
        }

        if (_isRowLevelSecurityError(e)) {
          continue;
        }

        debugPrint('Error following department: $e');
        rethrow;
      }
    }

    debugPrint('Error following department: $lastError');
    if (lastError != null) throw Exception(lastError.toString());
    throw Exception('Could not follow department.');
  }

  /// Unfollow a department
  Future<void> unfollowDepartment(
    String departmentId,
    String userEmail, {
    String? collegeId,
  }) async {
    final normalizedEmail = _normalizeEmail(userEmail);

    try {
      // Sync with users target array
      await _client.rpc(
        'remove_followed_department',
        params: {'user_email': normalizedEmail, 'dept_id': departmentId},
      );
    } catch (e) {
      debugPrint('Error syncing followed_departments array: $e');
    }

    final userId = currentUserId;
    final filters = <Map<String, String>>[
      if (userId != null && userId.isNotEmpty)
        {'column': 'user_id', 'value': userId},
      if (userId != null && userId.isNotEmpty)
        {'column': 'follower_id', 'value': userId},
      if (normalizedEmail.isNotEmpty)
        {'column': 'follower_email', 'value': normalizedEmail},
      if (normalizedEmail.isNotEmpty)
        {'column': 'user_email', 'value': normalizedEmail},
    ];
    final attempts = <Map<String, dynamic>>[
      for (final filter in filters)
        {
          'column': filter['column']!,
          'value': filter['value']!,
          'useCollegeFilter': true,
        },
      for (final filter in filters)
        {
          'column': filter['column']!,
          'value': filter['value']!,
          'useCollegeFilter': false,
        },
    ];

    if (attempts.isEmpty) return;

    Object? lastError;
    for (final attempt in attempts) {
      final column = attempt['column'] as String;
      final value = attempt['value'] as String;
      final useCollegeFilter = attempt['useCollegeFilter'] == true;
      try {
        var query = _client
            .from('department_followers')
            .delete()
            .eq('department_id', departmentId)
            .eq(column, value);
        if (useCollegeFilter &&
            collegeId != null &&
            collegeId.trim().isNotEmpty) {
          query = query.eq('college_id', collegeId);
        }
        await query;
        return;
      } catch (e) {
        lastError = e;
        final schemaMismatch =
            _isMissingColumnError(e, column) ||
            (useCollegeFilter && _isMissingColumnError(e, 'college_id'));
        if (schemaMismatch || _isRowLevelSecurityError(e)) {
          continue;
        }

        debugPrint('Error unfollowing department: $e');
        rethrow;
      }
    }

    debugPrint('Error unfollowing department: $lastError');
    if (lastError != null) {
      throw Exception(lastError.toString());
    }
  }

  /// Check if following department
  Future<bool> isFollowingDepartment(
    String departmentId,
    String userEmail, {
    String? collegeId,
  }) async {
    final normalizedEmail = _normalizeEmail(userEmail);
    final userId = currentUserId;
    final filters = <Map<String, String>>[
      if (userId != null && userId.isNotEmpty)
        {'column': 'user_id', 'value': userId},
      if (userId != null && userId.isNotEmpty)
        {'column': 'follower_id', 'value': userId},
      if (normalizedEmail.isNotEmpty)
        {'column': 'follower_email', 'value': normalizedEmail},
      if (normalizedEmail.isNotEmpty)
        {'column': 'user_email', 'value': normalizedEmail},
    ];
    final attempts = <Map<String, dynamic>>[
      for (final filter in filters)
        {
          'column': filter['column']!,
          'value': filter['value']!,
          'useCollegeFilter': true,
        },
      for (final filter in filters)
        {
          'column': filter['column']!,
          'value': filter['value']!,
          'useCollegeFilter': false,
        },
    ];

    if (attempts.isEmpty) return false;

    for (final attempt in attempts) {
      final column = attempt['column'] as String;
      final value = attempt['value'] as String;
      final useCollegeFilter = attempt['useCollegeFilter'] == true;
      try {
        var query = _client
            .from('department_followers')
            .select('id')
            .eq('department_id', departmentId)
            .eq(column, value);
        if (useCollegeFilter &&
            collegeId != null &&
            collegeId.trim().isNotEmpty) {
          query = query.eq('college_id', collegeId);
        }
        final response = await query.maybeSingle();
        return response != null;
      } catch (e) {
        final schemaMismatch =
            _isMissingColumnError(e, column) ||
            (useCollegeFilter && _isMissingColumnError(e, 'college_id'));
        if (!schemaMismatch && !_isRowLevelSecurityError(e)) {
          debugPrint('Error checking department follow: $e');
          return false;
        }
      }
    }

    return false;
  }

  /// Get department follower count
  Future<int> getDepartmentFollowerCount(
    String departmentId,
    String collegeId,
  ) async {
    try {
      var query = _client
          .from('department_followers')
          .count(CountOption.exact)
          .eq('department_id', departmentId);
      if (collegeId.trim().isNotEmpty) {
        query = query.eq('college_id', collegeId);
      }
      final response = await query;
      return response;
    } catch (e) {
      if (_isMissingColumnError(e, 'college_id')) {
        try {
          final response = await _client
              .from('department_followers')
              .count(CountOption.exact)
              .eq('department_id', departmentId);
          return response;
        } catch (fallbackError) {
          debugPrint(
            'Error getting department follower count: $e | $fallbackError',
          );
          return 0;
        }
      }
      debugPrint('Error getting department follower count: $e');
      return 0;
    }
  }

  /// Get followed department IDs
  Future<List<String>> getFollowedDepartmentIds(
    String collegeId,
    String userEmail,
  ) async {
    final normalizedEmail = _normalizeEmail(userEmail);
    final userId = currentUserId;
    final filters = <Map<String, String>>[
      if (userId != null && userId.isNotEmpty)
        {'column': 'user_id', 'value': userId},
      if (userId != null && userId.isNotEmpty)
        {'column': 'follower_id', 'value': userId},
      if (normalizedEmail.isNotEmpty)
        {'column': 'follower_email', 'value': normalizedEmail},
      if (normalizedEmail.isNotEmpty)
        {'column': 'user_email', 'value': normalizedEmail},
    ];
    final attempts = <Map<String, dynamic>>[
      for (final filter in filters)
        {
          'column': filter['column']!,
          'value': filter['value']!,
          'useCollegeFilter': true,
        },
      for (final filter in filters)
        {
          'column': filter['column']!,
          'value': filter['value']!,
          'useCollegeFilter': false,
        },
    ];

    if (attempts.isEmpty) return [];

    final finalSet = <String>{};

    for (final attempt in attempts) {
      final column = attempt['column'] as String;
      final value = attempt['value'] as String;
      final useCollegeFilter = attempt['useCollegeFilter'] == true;
      try {
        var query = _client
            .from('department_followers')
            .select('department_id')
            .eq(column, value);
        if (useCollegeFilter && collegeId.trim().isNotEmpty) {
          query = query.eq('college_id', collegeId);
        }
        final response = await query;
        final fetchedIds = (response as List)
            .map((e) => e['department_id']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>()
            .toList();
        finalSet.addAll(fetchedIds);
        break; // Stop falling back if query succeeds
      } catch (e) {
        final schemaMismatch =
            _isMissingColumnError(e, column) ||
            (useCollegeFilter && _isMissingColumnError(e, 'college_id'));
        if (!schemaMismatch && !_isRowLevelSecurityError(e)) {
          debugPrint('Error getting followed departments: $e');
          return [];
        }
      }
    }

    // Merge with user profile followed_departments
    try {
      final userRes = await _client
          .from('users')
          .select('followed_departments')
          .eq('email', normalizedEmail)
          .maybeSingle();
      if (userRes != null) {
        final profileFollows =
            userRes['followed_departments'] as List<dynamic>? ?? [];
        for (final id in profileFollows) {
          if (id != null) finalSet.add(id.toString());
        }
      }
    } catch (e) {
      debugPrint('Error getting profile followed_departments: $e');
    }

    return finalSet.toList();
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
      final data = await _api.getCommentReactions(
        commentId: commentId,
        commentType: commentType,
      );

      final raw = data['reactions'];
      final Map<String, List<String>> grouped = {};
      if (raw is Map) {
        raw.forEach((key, value) {
          final emoji = key.toString();
          if (value is List) {
            grouped[emoji] = value.map((e) => e.toString()).toList();
          } else {
            grouped[emoji] = [];
          }
        });
      }

      final total = data['total'];
      return {
        'reactions': grouped,
        'total': total is int
            ? total
            : grouped.values.fold<int>(0, (sum, list) => sum + list.length),
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
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');
      final added = await _api.toggleCommentReaction(
        commentId: commentId,
        commentType: commentType,
        emoji: emoji,
        context: ctx,
      );
      return added;
    } catch (e) {
      debugPrint('Error toggling reaction: $e');
      rethrow;
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

      final cacheKey = _resourceStateKey(resourceId, userEmail: userEmail);
      final isMarked =
          _bookmarkStateCache[cacheKey] ?? await _api.checkBookmark(resourceId);
      if (isMarked) {
        await _api.removeBookmarkByItem(itemId: resourceId, context: ctx);
        _bookmarkStateCache[cacheKey] = false;
        return false;
      }

      await _api.addBookmark(
        itemId: resourceId,
        type: 'resource',
        context: ctx,
      );
      _bookmarkStateCache[cacheKey] = true;
      return true;
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      rethrow;
    }
  }

  /// Check if a resource is bookmarked by the user
  Future<bool> isBookmarked(String userEmail, String resourceId) async {
    final cacheKey = _resourceStateKey(resourceId, userEmail: userEmail);
    final cached = _bookmarkStateCache[cacheKey];
    if (cached != null) return cached;
    try {
      final value = await _api.checkBookmark(resourceId);
      _bookmarkStateCache[cacheKey] = value;
      return value;
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
