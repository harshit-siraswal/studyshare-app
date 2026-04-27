import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/college.dart';
import '../models/resource.dart';
import '../models/user.dart';
import 'backend_api_service.dart';
import '../models/department_account.dart';
import '../models/department_option.dart';
import '../data/department_catalog.dart';
import '../utils/admin_access.dart';
import '../utils/user_identity_resolver.dart';

class RoomLimitException implements Exception {
  final String message;
  RoomLimitException(this.message);
  @override
  String toString() => message;
}

enum FollowStatus { notFollowing, pending, following }

class SupabaseService {
  factory SupabaseService() => _instance;
  SupabaseService._internal();
  static final SupabaseService _instance = SupabaseService._internal();

  static const int kUnlimitedDuration = -1;
  static const int kDefaultExpiryDays = 7;
  static const Duration _currentUserProfileCacheTtl = Duration(minutes: 2);
  static const Duration _resourcesCacheTtl = Duration(seconds: 20);
  static const Duration _filterValuesCacheTtl = Duration(minutes: 5);
  static const Duration _noticeDepartmentsCacheTtl = Duration(minutes: 10);
  static const Duration _userInfoCacheTtl = Duration(minutes: 5);
  static const int _maxResourceListCacheEntries = 24;
  static const int _maxFilterValuesCacheEntries = 24;
  static const int _maxUserInfoCacheEntries = 256;
  static final ValueNotifier<int> aiTokenRefreshNotifier = ValueNotifier<int>(
    0,
  );

  SupabaseClient get _client => Supabase.instance.client;
  final BackendApiService _api = BackendApiService();
  static Map<String, dynamic>? _cachedCurrentUserProfile;
  static String? _cachedCurrentUserProfileEmail;
  static DateTime? _cachedCurrentUserProfileAt;
  static Future<Map<String, dynamic>>? _currentUserProfileFetchFuture;
  static Map<String, dynamic>? _cachedCurrentUserIdentity;
  static String? _cachedCurrentUserIdentityEmail;
  static String? _cachedCurrentUserIdentityUserId;
  static Future<Map<String, dynamic>>? _currentUserIdentityFetchFuture;
  static ResolvedUserType _cachedResolvedUserType =
      ResolvedUserType.unauthenticated;
  static List<College>? _cachedColleges;
  static ({DateTime cachedAt, List<DepartmentOption> data})?
  _noticeDepartmentsCache;
  static final Map<String, ({DateTime cachedAt, List<Resource> data})>
  _resourceListCache = <String, ({DateTime cachedAt, List<Resource> data})>{};
  static final Map<String, Future<List<Resource>>> _resourceListInFlight =
      <String, Future<List<Resource>>>{};
  static final Map<String, ({DateTime cachedAt, List<String> data})>
  _uniqueValuesCache = <String, ({DateTime cachedAt, List<String> data})>{};
  static final Map<String, ({DateTime cachedAt, Map<String, dynamic> data})>
  _userInfoCache = <String, ({DateTime cachedAt, Map<String, dynamic> data})>{};
  static final Map<String, Future<Map<String, dynamic>?>> _userInfoInFlight =
      <String, Future<Map<String, dynamic>?>>{};
  static final Map<String, bool> _bookmarkStateCache = <String, bool>{};
  static final Map<String, Future<bool>> _bookmarkStateInFlight =
      <String, Future<bool>>{};
  static final Map<String, DateTime> _bookmarkRateLimitUntil =
      <String, DateTime>{};
  static final Map<String, ({int? userVote, int upvotes, int downvotes})>
  _voteStateCache = <String, ({int? userVote, int upvotes, int downvotes})>{};
  static final Map<
    String,
    Future<({int? userVote, int upvotes, int downvotes})>
  >
  _voteStateInFlight =
      <String, Future<({int? userVote, int upvotes, int downvotes})>>{};
  static final Map<String, DateTime> _voteRateLimitUntil = <String, DateTime>{};
  static bool? _usersTableHasFirebaseUid;
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

  /// A BuildContext is required to run reCAPTCHA (invisible WebView) before
  /// privileged writes.
  BuildContext? _ctx;

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

  Future<String> _resolveDepartmentFollowEmail({String? claimedEmail}) async {
    final sessionEmail = _currentSessionEmail();
    final normalizedClaimed = _normalizeEmail(claimedEmail);

    if (sessionEmail.isNotEmpty) {
      if (normalizedClaimed.isNotEmpty && normalizedClaimed != sessionEmail) {
        throw Exception('Authenticated user mismatch. Please sign in again.');
      }
      return sessionEmail;
    }

    if (_cachedCurrentUserIdentityEmail != null &&
        _cachedCurrentUserIdentityEmail!.isNotEmpty) {
      return _normalizeEmail(_cachedCurrentUserIdentityEmail);
    }

    if (normalizedClaimed.isNotEmpty) {
      return normalizedClaimed;
    }

    try {
      final identity = await getCurrentUserIdentity();
      final resolvedEmail = _normalizeEmail(identity['email']?.toString());
      if (resolvedEmail.isNotEmpty) {
        return resolvedEmail;
      }
    } catch (e) {
      debugPrint('Error resolving department follow email: $e');
    }

    return '';
  }

  String _normalizeEmail(String? email) => email?.trim().toLowerCase() ?? '';

  String _requireCurrentSessionEmail({
    String? claimedEmail,
    required String action,
  }) {
    final sessionEmail = _currentSessionEmail();
    if (sessionEmail.isEmpty) {
      throw Exception('Please sign in to continue.');
    }

    final normalizedClaimed = _normalizeEmail(claimedEmail);
    if (normalizedClaimed.isNotEmpty && normalizedClaimed != sessionEmail) {
      developer.log(
        'action=$action ownership_mismatch=true claimed_present=true session_present=true',
        name: 'security.ownership_mismatch',
        level: 1000,
      );
      throw Exception('Authenticated user mismatch. Please sign in again.');
    }

    return sessionEmail;
  }

  void _pruneExpiredRateLimits() {
    final now = DateTime.now();
    _bookmarkRateLimitUntil.removeWhere((_, until) => !until.isAfter(now));
    _voteRateLimitUntil.removeWhere((_, until) => !until.isAfter(now));
  }

  String _escapeLikePattern(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  String _normalizeCollegeScopeValue(String? value) {
    return value?.trim().toLowerCase() ?? '';
  }

  bool _looksLikeDomainScope(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('@', '');
    if (normalized.isEmpty) return false;
    return normalized.contains('.') && !normalized.contains(' ');
  }

  bool _matchesCollegeScope(
    Map<String, dynamic> user, {
    required String collegeId,
    required String college,
  }) {
    final normalizedCollegeId = _normalizeCollegeScopeValue(collegeId);
    final normalizedCollege = _normalizeCollegeScopeValue(college);
    if (normalizedCollegeId.isEmpty && normalizedCollege.isEmpty) {
      return true;
    }

    final userCollegeId = _normalizeCollegeScopeValue(
      user['college_id']?.toString(),
    );
    final userCollegeRaw = user['college'];
    // college may be stored as a JSON map or a plain string
    String userCollegeName = '';
    if (userCollegeRaw is Map) {
      userCollegeName = _normalizeCollegeScopeValue(
        (userCollegeRaw['name'] ?? userCollegeRaw['id'])?.toString(),
      );
    } else {
      // Try to extract name from JSON-encoded string
      final rawStr = _normalizeCollegeScopeValue(userCollegeRaw?.toString());
      final nameMatch = RegExp(r'"name"\s*:\s*"([^"]+)"').firstMatch(rawStr);
      userCollegeName = nameMatch != null
          ? nameMatch.group(1)!.toLowerCase()
          : rawStr;
    }
    final userEmail = _normalizeEmail(user['email']?.toString());

    // ① College-ID exact match (most authoritative)
    if (normalizedCollegeId.isNotEmpty &&
        userCollegeId.isNotEmpty &&
        userCollegeId == normalizedCollegeId) {
      return true;
    }

    // ② Domain-scope: check email domain only
    if (normalizedCollegeId.isEmpty &&
        _looksLikeDomainScope(normalizedCollege)) {
      final scopeDomain = normalizedCollege.replaceAll('@', '');
      return userEmail.isNotEmpty && userEmail.endsWith('@$scopeDomain');
    }

    // ③ College name fuzzy match (used when scope is name-based)
    if (normalizedCollege.isNotEmpty &&
        userCollegeName.isNotEmpty &&
        (userCollegeName == normalizedCollege ||
            userCollegeName.contains(normalizedCollege) ||
            normalizedCollege.contains(userCollegeName))) {
      return true;
    }

    return false;
  }

  String _resourceStateKey(String resourceId, {String? userEmail}) {
    final normalizedInputEmail = _normalizeEmail(userEmail);
    final scopedEmail = normalizedInputEmail.isNotEmpty
        ? normalizedInputEmail
        : _currentSessionEmail();
    return '$scopedEmail::$resourceId';
  }

  bool _hasFreshCurrentUserProfileCacheFor(String email) {
    if (email.isEmpty) return false;
    return _cachedCurrentUserProfile != null &&
        _cachedCurrentUserProfileEmail == email &&
        _cachedCurrentUserProfileAt != null &&
        DateTime.now().difference(_cachedCurrentUserProfileAt!) <
            _currentUserProfileCacheTtl;
  }

  void _cacheCurrentUserProfile(String email, Map<String, dynamic> profile) {
    if (email.isEmpty || profile.isEmpty) return;
    _cachedCurrentUserProfile = Map<String, dynamic>.from(profile);
    _cachedCurrentUserProfileEmail = email;
    _cachedCurrentUserProfileAt = DateTime.now();
    _cacheUserInfo(
      email,
      _normalizeReadableUserRecord(<String, dynamic>{
        ...profile,
        'email': email,
      }),
    );

    final identity = _mapProfileToIdentity(profile);
    if (identity.isNotEmpty) {
      _cachedCurrentUserIdentity = identity;
      _cachedCurrentUserIdentityEmail = _normalizeEmail(
        identity['email']?.toString(),
      );
      _cachedCurrentUserIdentityUserId =
          identity['id']?.toString().trim().isNotEmpty == true
          ? identity['id'].toString().trim()
          : null;
      _cachedResolvedUserType = resolveUserType(identity);
    }
  }

  void invalidateCurrentUserProfileCache() {
    final cachedEmail = _cachedCurrentUserProfileEmail;
    _cachedCurrentUserProfile = null;
    _cachedCurrentUserProfileEmail = null;
    _cachedCurrentUserProfileAt = null;
    _currentUserProfileFetchFuture = null;
    if (cachedEmail != null && cachedEmail.isNotEmpty) {
      _userInfoCache.remove(cachedEmail);
      _userInfoInFlight.remove(cachedEmail);
    }
  }

  void invalidateCurrentUserIdentityCache() {
    _cachedCurrentUserIdentity = null;
    _cachedCurrentUserIdentityEmail = null;
    _cachedCurrentUserIdentityUserId = null;
    _currentUserIdentityFetchFuture = null;
    _cachedResolvedUserType = ResolvedUserType.unauthenticated;
  }

  void clearSessionCachesOnSignOut() {
    invalidateCurrentUserProfileCache();
    invalidateCurrentUserIdentityCache();
    _userInfoCache.clear();
    _userInfoInFlight.clear();
  }

  Map<String, dynamic>? get cachedCurrentUserIdentity {
    final cached = _cachedCurrentUserIdentity;
    if (cached == null || cached.isEmpty) return null;
    return Map<String, dynamic>.from(cached);
  }

  ResolvedUserType get cachedResolvedUserType => _cachedResolvedUserType;

  bool _hasFreshCurrentUserIdentityCacheFor({
    required String userId,
    required String email,
  }) {
    if (_cachedCurrentUserIdentity == null) return false;
    if (userId.isNotEmpty && _cachedCurrentUserIdentityUserId == userId) {
      return true;
    }
    return email.isNotEmpty && _cachedCurrentUserIdentityEmail == email;
  }

  Map<String, dynamic> _normalizeIdentityPayload(Map<String, dynamic> raw) {
    final identity = Map<String, dynamic>.from(raw);

    if ((identity['profile_photo_url']?.toString().trim().isEmpty ?? true) &&
        (identity['photo_url']?.toString().trim().isNotEmpty ?? false)) {
      identity['profile_photo_url'] = identity['photo_url'];
    }

    final role = identity['user_role']?.toString().trim() ?? '';
    if (role.isEmpty &&
        (identity['role']?.toString().trim().isNotEmpty ?? false)) {
      identity['user_role'] = identity['role'];
    }

    return identity;
  }

  Map<String, dynamic> _mapProfileToIdentity(Map<String, dynamic> profile) {
    if (profile.isEmpty) return <String, dynamic>{};

    final normalized = Map<String, dynamic>.from(profile);
    final resolvedRole = resolveEffectiveProfileRole(normalized);
    final normalizedEmail = _normalizeEmail(normalized['email']?.toString());

    final hasElevatedRole =
        resolvedRole == AppRoles.admin ||
        resolvedRole == AppRoles.teacher ||
        resolvedRole == AppRoles.moderator;

    return _normalizeIdentityPayload(<String, dynamic>{
      'id': normalized['id'],
      'email': normalizedEmail,
      'display_name': normalized['display_name'],
      'profile_photo_url':
          normalized['profile_photo_url'] ?? normalized['photo_url'],
      'user_role':
          normalized['user_role'] ?? normalized['role'] ?? resolvedRole,
      'college_id': normalized['college_id'],
      'branch': normalized['branch'],
      'semester': normalized['semester'],
      'subscription_tier': normalized['subscription_tier'],
      'premium_until':
          normalized['premium_until'] ?? normalized['subscription_end_date'],
      'college_name': normalized['college_name'] ?? normalized['college'],
      'college_domain': normalized['college_domain'],
      'college_logo':
          normalized['college_logo'] ?? normalized['college_logo_url'],
      'admin_role':
          normalized['admin_role'] ?? (hasElevatedRole ? resolvedRole : null),
      'admin_department':
          normalized['admin_department'] ?? normalized['department'],
      'admin_capabilities':
          normalized['admin_capabilities'] ?? const <String, dynamic>{},
    });
  }

  Future<Map<String, dynamic>> getCurrentUserIdentity({
    bool forceRefresh = false,
  }) async {
    final userId = currentUserId?.trim() ?? '';
    final email = _currentSessionEmail();

    if (forceRefresh) {
      invalidateCurrentUserIdentityCache();
    }

    if (!forceRefresh &&
        _hasFreshCurrentUserIdentityCacheFor(userId: userId, email: email)) {
      return Map<String, dynamic>.from(_cachedCurrentUserIdentity!);
    }

    if (_currentUserIdentityFetchFuture != null) {
      return _currentUserIdentityFetchFuture!;
    }

    _currentUserIdentityFetchFuture = () async {
      Map<String, dynamic> identity = <String, dynamic>{};

      if (_hasConfiguredSupabaseAnonKey) {
        try {
          Map<String, dynamic>? identityRow;

          if (userId.isNotEmpty) {
            final byId = await _client
                .from('user_identity')
                .select()
                .eq('id', userId)
                .maybeSingle();
            if (byId != null) {
              identityRow = Map<String, dynamic>.from(byId);
            }
          }

          if (identityRow == null && email.isNotEmpty) {
            final byEmail = await _client
                .from('user_identity')
                .select()
                .eq('email', email)
                .maybeSingle();
            if (byEmail != null) {
              identityRow = Map<String, dynamic>.from(byEmail);
            }
          }

          if (identityRow != null) {
            identity = _normalizeIdentityPayload(identityRow);
          }
        } catch (e) {
          debugPrint('user_identity view lookup failed, falling back: $e');
        }
      }

      if (identity.isEmpty) {
        final profile = await getCurrentUserProfile(
          maxAttempts: 2,
          forceRefresh: forceRefresh,
        );
        if (profile.isNotEmpty) {
          identity = _mapProfileToIdentity(profile);
        }
      }

      if (identity.isNotEmpty) {
        _cachedCurrentUserIdentity = Map<String, dynamic>.from(identity);
        _cachedCurrentUserIdentityEmail = _normalizeEmail(
          identity['email']?.toString(),
        );
        _cachedCurrentUserIdentityUserId =
            identity['id']?.toString().trim().isNotEmpty == true
            ? identity['id'].toString().trim()
            : null;
        _cachedResolvedUserType = resolveUserType(identity);
      }

      return identity;
    }();

    try {
      return await _currentUserIdentityFetchFuture!;
    } finally {
      _currentUserIdentityFetchFuture = null;
    }
  }

  Future<void> warmCurrentUserIdentity({bool forceRefresh = false}) async {
    try {
      await getCurrentUserIdentity(forceRefresh: forceRefresh);
    } catch (e) {
      debugPrint('Failed to warm current user identity: $e');
    }
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

  bool get _hasConfiguredSupabaseAnonKey {
    final key = AppConfig.supabaseAnonKey.trim();
    return key.isNotEmpty &&
        key.toLowerCase() != 'your-anon-key' &&
        key.toUpperCase() != 'YOUR_SUPABASE_ANON_KEY';
  }

  bool get hasConfiguredSupabaseAnonKey => _hasConfiguredSupabaseAnonKey;

  List<Map<String, dynamic>> _extractResourceRowsFromBackendPayload(
    Map<String, dynamic> payload,
  ) {
    final rowsRaw =
        payload['resources'] ??
        payload['items'] ??
        payload['data'] ??
        payload['results'];
    if (rowsRaw is! List) return const <Map<String, dynamic>>[];

    return rowsRaw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
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

  void _pruneUserInfoCacheIfNeeded() {
    while (_userInfoCache.length > _maxUserInfoCacheEntries) {
      final oldest = _userInfoCache.entries.reduce(
        (a, b) => a.value.cachedAt.isBefore(b.value.cachedAt) ? a : b,
      );
      _userInfoCache.remove(oldest.key);
    }
  }

  Map<String, dynamic>? _getCachedUserInfo(String email) {
    final cached = _userInfoCache[email];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.cachedAt) >= _userInfoCacheTtl) {
      _userInfoCache.remove(email);
      return null;
    }
    return Map<String, dynamic>.from(cached.data);
  }

  void _cacheUserInfo(String email, Map<String, dynamic> userInfo) {
    if (email.isEmpty || userInfo.isEmpty) return;
    _userInfoCache[email] = (
      cachedAt: DateTime.now(),
      data: Map<String, dynamic>.from(userInfo),
    );
    _pruneUserInfoCacheIfNeeded();
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
    final resolvedRole = resolveEffectiveProfileRole(profile);
    return _normalizeRoleValue(resolvedRole);
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

  bool _isOnConflictTargetMissingError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('on conflict') &&
        (message.contains('42p10') ||
            message.contains('no unique or exclusion constraint'));
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

  bool _isRateLimitError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('rate limit') ||
        message.contains('too many requests') ||
        message.contains('http 429') ||
        message.contains('statuscode: 429');
  }

  bool _isNoRowsSingleObjectMessage(String message) {
    return message.contains('pgrst116') ||
        (message.contains('0 rows') &&
            message.contains('single json object')) ||
        message.contains('cannot coerce the result to a single json object');
  }

  bool _isNoRowsSingleObjectError(Object error) {
    return _isNoRowsSingleObjectMessage(error.toString().toLowerCase());
  }

  bool _isNoRowsMutationResult(Object error) {
    final message = error.toString().toLowerCase();
    return _isNoRowsSingleObjectMessage(message) ||
        message.contains('the result contains 0 rows');
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
    String resourceId, {
    String? userEmail,
  }) async {
    _pruneExpiredRateLimits();
    final key = _resourceStateKey(resourceId, userEmail: userEmail);
    final cached = _voteStateCache[key];
    if (cached != null) {
      return cached;
    }

    final cooldownUntil = _voteRateLimitUntil[key];
    if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil)) {
      return (userVote: null, upvotes: 0, downvotes: 0);
    }

    final inFlight = _voteStateInFlight[key];
    if (inFlight != null) {
      return inFlight;
    }

    final future = () async {
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
        _voteRateLimitUntil.remove(key);
        return resolved;
      } catch (e) {
        final fallback = (userVote: null, upvotes: 0, downvotes: 0);
        if (_isRateLimitError(e)) {
          _voteRateLimitUntil[key] = DateTime.now().add(
            const Duration(seconds: 20),
          );
          _voteStateCache[key] = fallback;
        }
        debugPrint('Error fetching resource vote status: $e');
        return fallback;
      } finally {
        _voteStateInFlight.remove(key);
      }
    }();

    _voteStateInFlight[key] = future;
    return future;
  }

  ({int? userVote, int upvotes, int downvotes})? getCachedVoteState(
    String resourceId, {
    String? userEmail,
  }) {
    final cacheKey = _resourceStateKey(resourceId, userEmail: userEmail);
    return _voteStateCache[cacheKey];
  }

  Future<void> prefetchVotesForResources({
    required String userEmail,
    required Iterable<String> resourceIds,
    int maxConcurrent = 8,
  }) async {
    final normalizedEmail = _normalizeEmail(userEmail);
    if (normalizedEmail.isEmpty) return;

    final ids = resourceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    final safeMaxConcurrent = maxConcurrent < 1
        ? 1
        : (maxConcurrent > 20 ? 20 : maxConcurrent);

    for (var i = 0; i < ids.length; i += safeMaxConcurrent) {
      final end = (i + safeMaxConcurrent) > ids.length
          ? ids.length
          : (i + safeMaxConcurrent);
      final batch = ids.sublist(i, end);
      await Future.wait(
        batch.map((id) async {
          await getResourceVoteStatus(id, userEmail: normalizedEmail);
        }),
      );
    }
  }

  Future<void> prefetchResourceStatesFromBulkEndpoint({
    required String userEmail,
    required Iterable<String> resourceIds,
  }) async {
    final normalizedEmail = _normalizeEmail(userEmail);
    if (normalizedEmail.isEmpty) return;

    final ids = resourceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    final response = await _api.getBulkResourceStates(resourceIds: ids);
    final rawStates =
        (response['states'] ?? response['items'] ?? response['resourceStates'])
            as List? ??
        const [];

    for (final item in rawStates) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);

      final resourceId =
          (row['resourceId'] ??
                  row['resource_id'] ??
                  row['id'] ??
                  row['itemId'])
              ?.toString()
              .trim() ??
          '';
      if (resourceId.isEmpty) continue;
      final cacheKey = _resourceStateKey(
        resourceId,
        userEmail: normalizedEmail,
      );

      final rawBookmarked =
          row['isBookmarked'] ?? row['bookmarked'] ?? row['is_bookmarked'];
      if (rawBookmarked is bool) {
        _bookmarkStateCache[cacheKey] = rawBookmarked;
      }

      final rawVote = row['userVote'] ?? row['user_vote'];
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

      final upvotesRaw = row['upvotes'] ?? row['up_votes'] ?? 0;
      final downvotesRaw = row['downvotes'] ?? row['down_votes'] ?? 0;
      _voteStateCache[cacheKey] = (
        userVote: userVote,
        upvotes: upvotesRaw is num ? upvotesRaw.toInt() : 0,
        downvotes: downvotesRaw is num ? downvotesRaw.toInt() : 0,
      );
    }

    for (final id in ids) {
      final cacheKey = _resourceStateKey(id, userEmail: normalizedEmail);
      _bookmarkStateCache.putIfAbsent(cacheKey, () => false);
      _voteStateCache.putIfAbsent(
        cacheKey,
        () => (userVote: null, upvotes: 0, downvotes: 0),
      );
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
      Map<String, dynamic>? user;
      if (_usersTableHasFirebaseUid == false) {
        user = await _client
            .from('users_safe')
            .select('id')
            .eq('email', email)
            .maybeSingle();
      } else {
        try {
          user = await _client
              .from('users_safe')
              .select('id, firebase_uid')
              .eq('email', email)
              .maybeSingle();
          _usersTableHasFirebaseUid = true;
        } catch (e) {
          if (_isMissingColumnError(e, 'firebase_uid')) {
            _usersTableHasFirebaseUid = false;
            user = await _client
                .from('users_safe')
                .select('id')
                .eq('email', email)
                .maybeSingle();
          } else {
            rethrow;
          }
        }
      }
      if (user == null) return [];

      final ids = <String>{};
      final id = user['id'];
      if (id != null) ids.add(id.toString());
      if (_usersTableHasFirebaseUid != false) {
        final firebaseUid = user['firebase_uid'];
        if (firebaseUid != null) ids.add(firebaseUid.toString());
      }

      return ids.toList();
    } catch (e) {
      debugPrint('Error resolving user identifiers: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUsersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    if (!_hasConfiguredSupabaseAnonKey) {
      return const <Map<String, dynamic>>[];
    }

    try {
      // Run both queries in parallel to fetch users by id or firebase_uid
      final results = await Future.wait([
        _client
            .from('users_safe')
            .select('id, email, display_name, profile_photo_url, username')
            .inFilter('id', ids)
            .catchError((e) {
              debugPrint('Error fetching users by id: $e');
              return [];
            }),
        _client
            .from('users_safe')
            .select('id, email, display_name, profile_photo_url, username')
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
            deduped[userId] = _normalizeReadableUserRecord(
              Map<String, dynamic>.from(user),
            );
          }
        }
      }

      return deduped.values.toList();
    } catch (e) {
      debugPrint('Error fetching users by ids: $e');
      return [];
    }
  }

  String _firstNonEmptyValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final raw = map[key];
      if (raw == null) continue;
      final text = raw.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  Map<String, dynamic> _normalizeReadableUserRecord(Map<String, dynamic> raw) {
    final normalized = Map<String, dynamic>.from(raw);
    final resolvedEmail = _firstNonEmptyValue(normalized, const ['email']);
    if (resolvedEmail.isNotEmpty) {
      normalized['email'] = resolvedEmail;
    }

    final existingUsername = _firstNonEmptyValue(normalized, const [
      'username',
    ]);
    if (existingUsername.isNotEmpty) {
      normalized['username'] = existingUsername;
    } else if (resolvedEmail.contains('@')) {
      final fallbackUsername = resolvedEmail
          .split('@')
          .first
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9._-]'), '')
          .replaceAll(RegExp(r'^[._-]+'), '')
          .replaceAll(RegExp(r'[._-]+$'), '');
      if (fallbackUsername.isNotEmpty) {
        normalized['username'] = fallbackUsername;
      }
    }

    final resolvedPhoto = _firstNonEmptyValue(normalized, const [
      'photo_url',
      'profile_photo_url',
      'avatar_url',
    ]);
    if (resolvedPhoto.isNotEmpty) {
      normalized['photo_url'] = resolvedPhoto;
      normalized['profile_photo_url'] = resolvedPhoto;
      normalized['avatar_url'] = resolvedPhoto;
    }
    return normalized;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchUsersByEmails(
    Iterable<String> rawEmails,
  ) async {
    final emails = rawEmails
        .map(_normalizeEmail)
        .where((email) => email.isNotEmpty)
        .toSet()
        .toList();
    if (emails.isEmpty) return const {};

    final usersByEmail = <String, Map<String, dynamic>>{};
    final missingEmails = <String>[];
    for (final email in emails) {
      final cached = _getCachedUserInfo(email);
      if (cached != null) {
        usersByEmail[email] = cached;
      } else {
        missingEmails.add(email);
      }
    }

    if (missingEmails.isEmpty) {
      return usersByEmail;
    }

    if (!_hasConfiguredSupabaseAnonKey) {
      await Future.wait(
        missingEmails.map((email) async {
          try {
            final userInfo = await getUserInfo(email);
            if (userInfo != null && userInfo.isNotEmpty) {
              usersByEmail[email] = userInfo;
            }
          } catch (e) {
            debugPrint('Backend user lookup failed for $email: $e');
          }
        }),
      );
      return usersByEmail;
    }

    try {
      final filters = missingEmails
          .map(
            (email) =>
                'email.ilike.${email.replaceAll('%', '\\%').replaceAll('_', '\\_')}',
          )
          .join(',');
      final rows = await _client
          .from('users_safe')
          .select(
            'email, display_name, username, profile_photo_url, role, admin_capabilities, scope_all_colleges, admin_college_id',
          )
          .or(filters);
      final map = <String, Map<String, dynamic>>{};
      for (final row in (rows as List).whereType<Map>()) {
        final entry = _normalizeReadableUserRecord(
          Map<String, dynamic>.from(row),
        );
        final email = _normalizeEmail(entry['email']?.toString());
        if (email.isEmpty) continue;
        _cacheUserInfo(email, entry);
        map[email] = entry;
      }
      return <String, Map<String, dynamic>>{...usersByEmail, ...map};
    } catch (e) {
      debugPrint('Error fetching users by emails: $e');
      return usersByEmail;
    }
  }

  bool _isTeacherLikeUploaderProfile(Map<String, dynamic> profile) {
    final effectiveRole = _resolveEffectiveRole(profile);
    return effectiveRole == AppRoles.teacher || effectiveRole == AppRoles.admin;
  }

  Future<List<Map<String, dynamic>>> enrichResourceRowsWithUploaderProfiles(
    Iterable<Map<String, dynamic>> rawRows,
  ) async {
    final rows = rawRows.map((row) => Map<String, dynamic>.from(row)).toList();
    if (rows.isEmpty) return rows;

    final usersByEmail = await _fetchUsersByEmails(
      rows.map((row) => row['uploaded_by_email']?.toString() ?? ''),
    );

    for (final row in rows) {
      _applyProfileToRecord(
        record: row,
        emailKey: 'uploaded_by_email',
        outputNameKey: 'uploaded_by_name',
        outputPhotoKey: 'profile_photo_url',
        usersByEmail: usersByEmail,
        existingNameKeys: const ['display_name', 'uploader_name'],
        existingPhotoKeys: const ['photo_url', 'avatar_url'],
      );

      final email = _normalizeEmail(row['uploaded_by_email']?.toString());
      final uploaderProfile = usersByEmail[email];
      if (uploaderProfile == null) continue;

      if (_isTeacherLikeUploaderProfile(uploaderProfile)) {
        row['uploader_role'] = 'TEACHER';
        row['is_teacher_upload'] = true;
        row['source'] = 'teacher';
      }
    }

    return rows;
  }

  void _applyProfileToRecord({
    required Map<String, dynamic> record,
    required String emailKey,
    required String outputNameKey,
    required String outputPhotoKey,
    required Map<String, Map<String, dynamic>> usersByEmail,
    List<String> existingNameKeys = const [],
    List<String> existingPhotoKeys = const [],
  }) {
    final email = _normalizeEmail(record[emailKey]?.toString());
    if (email.isEmpty) return;
    final user = usersByEmail[email];
    if (user == null) return;

    final resolvedName = _firstNonEmptyValue(record, [
      outputNameKey,
      ...existingNameKeys,
    ]);
    if (resolvedName.isEmpty) {
      final fallbackName = _firstNonEmptyValue(user, const [
        'display_name',
        'username',
      ]);
      if (fallbackName.isNotEmpty) {
        record[outputNameKey] = fallbackName;
      }
    }

    final resolvedPhoto = _firstNonEmptyValue(record, [
      outputPhotoKey,
      ...existingPhotoKeys,
    ]);
    if (resolvedPhoto.isNotEmpty) {
      record[outputPhotoKey] = resolvedPhoto;
      return;
    }

    final fallbackPhoto = _firstNonEmptyValue(user, const [
      'profile_photo_url',
      'photo_url',
      'avatar_url',
    ]);
    if (fallbackPhoto.isEmpty) return;
    record[outputPhotoKey] = fallbackPhoto;
  }

  // ============ COLLEGES ============

  /// Get all active colleges
  Future<List<College>> getColleges() async {
    final cachedColleges = _cachedColleges;
    if (cachedColleges != null && cachedColleges.isNotEmpty) {
      return List<College>.from(cachedColleges);
    }

    try {
      final response = await _client
          .from('colleges')
          .select()
          .eq('is_active', true)
          .order('name');

      final colleges = (response as List)
          .whereType<Map<String, dynamic>>()
          .map(College.fromJson)
          .where(
            (college) =>
                college.id.isNotEmpty &&
                college.name.isNotEmpty &&
                college.domain.isNotEmpty,
          )
          .toList();

      if (colleges.isNotEmpty) {
        _cachedColleges = List<College>.unmodifiable(colleges);
      }
      return colleges;
    } catch (e) {
      if (_isMissingColumnError(e, 'is_active')) {
        final response = await _client.from('colleges').select().order('name');
        final colleges = (response as List)
            .whereType<Map<String, dynamic>>()
            .map(College.fromJson)
            .where(
              (college) =>
                  college.id.isNotEmpty &&
                  college.name.isNotEmpty &&
                  college.domain.isNotEmpty,
            )
            .toList();
        if (colleges.isNotEmpty) {
          _cachedColleges = List<College>.unmodifiable(colleges);
        }
        return colleges;
      }
      debugPrint('Error fetching colleges: $e');
      rethrow;
    }
  }

  /// Search colleges by name
  Future<List<College>> searchColleges(String query) async {
    try {
      final escapedQuery = _escapeLikePattern(query.trim());
      final response = await _client
          .from('colleges')
          .select()
          .eq('is_active', true)
          .ilike('name', '%$escapedQuery%')
          .order('name')
          .limit(10);

      return (response as List)
          .whereType<Map<String, dynamic>>()
          .map(College.fromJson)
          .where(
            (college) =>
                college.id.isNotEmpty &&
                college.name.isNotEmpty &&
                college.domain.isNotEmpty,
          )
          .toList();
    } catch (e) {
      if (_isMissingColumnError(e, 'is_active')) {
        final escapedQuery = _escapeLikePattern(query.trim());
        final response = await _client
            .from('colleges')
            .select()
            .ilike('name', '%$escapedQuery%')
            .order('name')
            .limit(10);
        return (response as List)
            .whereType<Map<String, dynamic>>()
            .map(College.fromJson)
            .where(
              (college) =>
                  college.id.isNotEmpty &&
                  college.name.isNotEmpty &&
                  college.domain.isNotEmpty,
            )
            .toList();
      }
      debugPrint('Error searching colleges: $e');
      rethrow;
    }
  }

  // ============ RESOURCES ============

  Future<List<Resource>> _fetchResourcesViaBackend({
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
      final page = limit > 0 ? ((offset ~/ limit) + 1) : 1;
      final payload = await _api.listResources(
        collegeId: collegeId,
        branch: branch,
        semester: semester,
        subject: subject,
        type: type,
        search: searchQuery,
        sortBy: sortBy,
        page: page,
        limit: limit,
      );

      final extractedRows = _extractResourceRowsFromBackendPayload(payload);
      final rows = extractedRows.where((row) {
        final rowCollegeId =
            (row['college_id'] ?? row['collegeId'])?.toString().trim() ?? '';
        return rowCollegeId.isEmpty || rowCollegeId == collegeId;
      }).toList();
      final effectiveRows = rows.isNotEmpty ? rows : extractedRows;

      final enrichedRows = await enrichResourceRowsWithUploaderProfiles(
        effectiveRows,
      );
      final resources = <Resource>[];
      for (final row in enrichedRows) {
        try {
          resources.add(Resource.fromJson(row));
        } catch (parseError) {
          debugPrint('Skipping malformed backend resource row: $parseError');
        }
      }

      if (sortBy == 'teacher') {
        resources.sort((a, b) {
          if (a.isTeacherUpload != b.isTeacherUpload) {
            return a.isTeacherUpload ? -1 : 1;
          }
          return b.createdAt.compareTo(a.createdAt);
        });
      } else if (sortBy == 'upvotes') {
        resources.sort((a, b) => b.upvotes.compareTo(a.upvotes));
      } else {
        resources.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }

      return resources;
    } catch (e) {
      debugPrint('Backend resources fallback failed: $e');
      return const <Resource>[];
    }
  }

  Future<List<String>> _getUniqueValuesFromBackend({
    required String column,
    required String collegeId,
    String? branch,
  }) async {
    final resources = await _fetchResourcesViaBackend(
      collegeId: collegeId,
      branch: branch,
      limit: 120,
      offset: 0,
    );

    Iterable<String> values;
    switch (column.toLowerCase()) {
      case 'branch':
        values = resources.map((resource) => resource.branch ?? '');
        break;
      case 'semester':
        values = resources.map((resource) => resource.semester ?? '');
        break;
      case 'subject':
        values = resources.map((resource) => resource.subject ?? '');
        break;
      case 'type':
        values = resources.map((resource) => resource.type);
        break;
      default:
        values = const <String>[];
    }

    final normalized = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    normalized.sort();
    return normalized;
  }

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
    final escapedBranch = normalizedBranch == null
        ? null
        : _escapeLikePattern(normalizedBranch);
    final escapedSubject = normalizedSubject == null
        ? null
        : _escapeLikePattern(normalizedSubject);
    final escapedType = normalizedType == null
        ? null
        : _escapeLikePattern(normalizedType);
    final escapedSearch = _escapeLikePattern(normalizedSearch);
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
      if ((sortBy?.trim().toLowerCase() ?? '') == 'teacher') {
        final backendTeacherRows = await _fetchResourcesViaBackend(
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

        if (backendTeacherRows.isNotEmpty) {
          if (shouldUseCache) {
            _resourceListCache[cacheKey] = (
              cachedAt: DateTime.now(),
              data: List<Resource>.unmodifiable(backendTeacherRows),
            );
            _pruneResourceListCacheIfNeeded();
          }
          return backendTeacherRows;
        }
      }

      if (!_hasConfiguredSupabaseAnonKey) {
        debugPrint(
          'Supabase anon key missing; using backend resources fallback directly.',
        );
        final fallbackRows = await _fetchResourcesViaBackend(
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

        if (shouldUseCache) {
          _resourceListCache[cacheKey] = (
            cachedAt: DateTime.now(),
            data: List<Resource>.unmodifiable(fallbackRows),
          );
          _pruneResourceListCacheIfNeeded();
        }

        return fallbackRows;
      }

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
        if (escapedBranch != null && escapedBranch.isNotEmpty) {
          query = query.ilike('branch', '%$escapedBranch%');
        }
        if (escapedSubject != null && escapedSubject.isNotEmpty) {
          query = query.ilike('subject', '%$escapedSubject%');
        }
        if (escapedType != null && escapedType.isNotEmpty) {
          query = query.ilike('type', escapedType);
        }
        if (normalizedSearch.isNotEmpty) {
          query = query.ilike('title', '%$escapedSearch%');
        }

        final orderedQuery = sortBy == 'upvotes'
            ? query
                  .order('upvotes', ascending: false)
                  .order('created_at', ascending: false)
            : query.order('created_at', ascending: false);

        final response = await orderedQuery.range(offset, offset + limit - 1);
        final rawRows = (response as List)
            .whereType<Map>()
            .map((json) => Map<String, dynamic>.from(json))
            .toList();
        final enrichedRows = await enrichResourceRowsWithUploaderProfiles(
          rawRows,
        );
        final rows = enrichedRows
            .whereType<Map>()
            .map((json) => Resource.fromJson(Map<String, dynamic>.from(json)))
            .toList();

        if (sortBy == 'teacher') {
          rows.sort((a, b) {
            if (a.isTeacherUpload != b.isTeacherUpload) {
              return a.isTeacherUpload ? -1 : 1;
            }
            return b.createdAt.compareTo(a.createdAt);
          });
        }

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
        debugPrint('Error fetching resources via Supabase: $e');
        final fallbackRows = await _fetchResourcesViaBackend(
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

        if (fallbackRows.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
          if (shouldUseCache) {
            _resourceListCache[cacheKey] = (
              cachedAt: DateTime.now(),
              data: List<Resource>.unmodifiable(fallbackRows),
            );
            _pruneResourceListCacheIfNeeded();
          }
          return fallbackRows;
        }

        return const <Resource>[];
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
  Future<List<Resource>> _fetchApprovedResourcesByUploaderEmailsViaBackend(
    List<String> uploaderEmails, {
    int limit = 20,
    int offset = 0,
  }) async {
    final normalizedEmails = uploaderEmails
        .map(_normalizeEmail)
        .where((email) => email.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedEmails.isEmpty) return const <Resource>[];

    debugPrint(
      '[FollowingFeed] Fetching resources for ${normalizedEmails.length} '
      'followed users via backend.',
    );

    final fetchPerUser = (limit + offset).clamp(20, 120);
    final results = await Future.wait(
      normalizedEmails.map((email) async {
        try {
          final payload = await _api.getPublicUserResources(
            email: email,
            approvedOnly: true,
            limit: fetchPerUser,
            offset: 0,
          );
          final resourcesRaw = payload['resources'];
          if (resourcesRaw is! List) {
            debugPrint(
              '[FollowingFeed] No resources list in payload for $email '
              '(keys: ${payload.keys.toList()})',
            );
            return const <Resource>[];
          }
          final parsed = resourcesRaw
              .whereType<Map>()
              .map((row) => Resource.fromJson(Map<String, dynamic>.from(row)))
              .toList();
          debugPrint(
            '[FollowingFeed] Got ${parsed.length} resources for $email.',
          );
          return parsed;
        } catch (e) {
          debugPrint('[FollowingFeed] Backend lookup failed for $email: $e');
          return const <Resource>[];
        }
      }),
    );

    final mergedById = <String, Resource>{};
    for (final bucket in results) {
      for (final resource in bucket) {
        final id = resource.id.trim();
        if (id.isEmpty) continue;
        final existing = mergedById[id];
        if (existing == null ||
            resource.createdAt.isAfter(existing.createdAt)) {
          mergedById[id] = resource;
        }
      }
    }

    final merged = mergedById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    debugPrint(
      '[FollowingFeed] Merged total: ${merged.length} unique resources.',
    );
    final safeOffset = offset < 0 ? 0 : offset;
    if (safeOffset >= merged.length) return const <Resource>[];
    final end = (safeOffset + limit).clamp(0, merged.length);
    return merged.sublist(safeOffset, end);
  }

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
      var query = _client
          .from('resources')
          .select()
          .eq('status', 'approved')
          .inFilter('uploaded_by_email', normalizedEmails);
      if (collegeId.trim().isNotEmpty) {
        query = query.eq('college_id', collegeId.trim());
      }
      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final enrichedRows = await enrichResourceRowsWithUploaderProfiles(
        (response as List).whereType<Map>().map(
          (json) => Map<String, dynamic>.from(json),
        ),
      );
      final rows = enrichedRows.map((json) => Resource.fromJson(json)).toList();
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
      var query = _client.from('resources').select().eq('status', 'approved');
      if (collegeId.trim().isNotEmpty) {
        query = query.eq('college_id', collegeId.trim());
      }
      final raw = await query
          .order('created_at', ascending: false)
          .range(0, offset + fetchWindow - 1);
      final emailSet = normalizedEmails.toSet();
      final filteredRows = (raw as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where(
            (row) => emailSet.contains(
              _normalizeEmail(row['uploaded_by_email']?.toString()),
            ),
          )
          .skip(offset)
          .take(limit)
          .toList();
      final enrichedRows = await enrichResourceRowsWithUploaderProfiles(
        filteredRows,
      );
      return enrichedRows.map(Resource.fromJson).toList();
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

    final page = ((offset ~/ limit) + 1).clamp(1, 100000);

    // Primary path: aggregated backend endpoint already handles follow schema
    // variants and uploader metadata in one pass.
    try {
      final feedPayload = await _api.getFollowingFeed(
        collegeId: collegeId,
        page: page,
        limit: limit,
      );
      final rawResources = List<Map<String, dynamic>>.from(
        feedPayload['resources'] ?? const [],
      );
      if (rawResources.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
        return rawResources
            .map((row) => Resource.fromJson(Map<String, dynamic>.from(row)))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching aggregated following feed via backend: $e');
    }

    // Compatibility fallback for older backends.
    try {
      final followingPayload = await _api.getFollowing(email: activeUserEmail);
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
        final backendResources =
            await _fetchApprovedResourcesByUploaderEmailsViaBackend(
              followingEmails,
              limit: limit,
              offset: offset,
            );
        if (backendResources.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
          return backendResources;
        }
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

      await _api.sendFollowRequest(targetEmail, context: ctx);
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
      final ctx = _ctx;

      final status = await _api.checkFollowStatus(followingEmail);
      final isPending = status['status'] == 'pending';
      final requestId =
          status['requestId']?.toString() ?? status['request_id']?.toString();

      if (!isPending || requestId == null || requestId.isEmpty) {
        throw Exception('No pending follow request to cancel');
      }

      final parsedRequestId = int.tryParse(requestId);
      if (parsedRequestId == null) {
        throw Exception('Invalid follow request id');
      }

      await _api.cancelFollowRequest(parsedRequestId, context: ctx);
    } catch (e) {
      debugPrint('Error cancelling follow request: $e');
      rethrow;
    }
  }

  /// Accept follow request
  Future<void> acceptFollowRequest(int requestId) async {
    try {
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');
      if (!ctx.mounted) {
        throw Exception('Security context is no longer active');
      }
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
      if (ctx == null) throw Exception('Security context not initialized');
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
      await _api.deleteChatRoom(roomId);
      return;
    } catch (e) {
      debugPrint('Backend deleteRoom failed, trying RPC fallback: $e');
    }

    try {
      final response = await _client.rpc(
        'delete_room',
        params: {'room_id_input': roomId},
      );

      if (response != null && response['success'] == false) {
        throw Exception(response['error']?.toString() ?? 'Unknown error');
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
          .from('users_safe')
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
          .from('users_safe')
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
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail.isEmpty) return null;

    final cached = _getCachedUserInfo(normalizedEmail);
    if (cached != null) {
      return cached;
    }

    final inFlight = _userInfoInFlight[normalizedEmail];
    if (inFlight != null) {
      return inFlight;
    }

    final future = () async {
      final currentEmail = _currentSessionEmail();
      if (normalizedEmail == currentEmail) {
        try {
          final profile = await getCurrentUserProfile(maxAttempts: 1);
          if (profile.isNotEmpty) {
            final normalized = _normalizeReadableUserRecord(<String, dynamic>{
              ...profile,
              'email': normalizedEmail,
            });
            _cacheUserInfo(normalizedEmail, normalized);
            return normalized;
          }
        } catch (_) {}
      }

      try {
        final payload = await _api.getPublicProfile(email: normalizedEmail);
        final profilePayload = payload['profile'];
        final profile = profilePayload is Map
            ? Map<String, dynamic>.from(profilePayload)
            : Map<String, dynamic>.from(payload);
        if (profile.isNotEmpty) {
          final normalized = _normalizeReadableUserRecord(profile);
          _cacheUserInfo(normalizedEmail, normalized);
          return normalized;
        }
      } catch (e) {
        debugPrint('Backend public profile lookup failed: $e');
        if (!_hasConfiguredSupabaseAnonKey) {
          return null;
        }
      }

      try {
        final res = await _client
            .from('users_safe')
            .select(
              'id, email, display_name, profile_photo_url, username, bio, semester, branch, subject, role, admin_capabilities, scope_all_colleges, admin_college_id',
            )
            .eq('email', normalizedEmail)
            .maybeSingle();
        if (res == null) {
          return null;
        }
        final normalized = _normalizeReadableUserRecord(
          Map<String, dynamic>.from(res),
        );
        _cacheUserInfo(normalizedEmail, normalized);
        return normalized;
      } catch (e) {
        debugPrint('Error fetching user info: $e');
        return null;
      }
    }();

    _userInfoInFlight[normalizedEmail] = future;
    try {
      return await future;
    } finally {
      _userInfoInFlight.remove(normalizedEmail);
    }
  }

  Future<Map<String, dynamic>> updateCurrentUserProfileDirect({
    String? displayName,
    String? username,
    String? bio,
    String? profilePhotoUrl,
    String? semester,
    String? branch,
    String? subject,
  }) async {
    final email = _currentSessionEmail();
    final userId = (currentUserId ?? '').trim();
    if (email.isEmpty) {
      throw Exception('Please sign in to update your profile.');
    }

    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
      if (displayName != null) 'display_name': displayName.trim(),
      if (username != null) 'username': username.trim(),
      if (bio != null) 'bio': bio.trim(),
      if (profilePhotoUrl != null) 'profile_photo_url': profilePhotoUrl.trim(),
      if (semester != null) 'semester': semester.trim(),
      if (branch != null) 'branch': branch.trim(),
      if (subject != null) 'subject': subject.trim(),
    };

    var selectColumns = <String>[
      'id',
      'email',
      'display_name',
      'profile_photo_url',
      'username',
      'bio',
      'semester',
      'branch',
      'subject',
    ];

    final lookupAttempts = <({String column, String value})>[
      if (userId.isNotEmpty) (column: 'id', value: userId),
      (column: 'email', value: email),
    ];

    Future<Map<String, dynamic>?> runUpdate(String column, String value) async {
      try {
        return await _client
            .from('users')
            .update(updates)
            .eq(column, value)
            .select(selectColumns.join(', '))
            .maybeSingle()
            .then(
              (value) => value == null
                  ? null
                  : _normalizeReadableUserRecord(
                      Map<String, dynamic>.from(value),
                    ),
            );
      } catch (e) {
        if (_isNoRowsSingleObjectError(e)) {
          return null;
        }
        rethrow;
      }
    }

    Future<Map<String, dynamic>?> runSelect(String column, String value) async {
      try {
        return await _client
            .from('users')
            .select(selectColumns.join(', '))
            .eq(column, value)
            .maybeSingle()
            .then(
              (value) => value == null
                  ? null
                  : _normalizeReadableUserRecord(
                      Map<String, dynamic>.from(value),
                    ),
            );
      } catch (e) {
        if (_isNoRowsSingleObjectError(e)) {
          return null;
        }
        rethrow;
      }
    }

    while (true) {
      try {
        Map<String, dynamic>? profile;
        for (final attempt in lookupAttempts) {
          profile = await runUpdate(attempt.column, attempt.value);
          if (profile != null) break;
        }

        if (profile == null) {
          for (final attempt in lookupAttempts) {
            profile = await runSelect(attempt.column, attempt.value);
            if (profile != null) break;
          }

          final upsertPayload = <String, dynamic>{'email': email, ...updates};
          try {
            await _client
                .from('users')
                .upsert(upsertPayload, onConflict: 'email')
                .select();
          } catch (e) {
            if (!_isOnConflictTargetMissingError(e)) {
              rethrow;
            }
            final insertPayload = <String, dynamic>{
              if (userId.isNotEmpty) 'id': userId,
              'email': email,
              ...updates,
            };
            await _client.from('users').insert(insertPayload).select();
          }

          profile = await runSelect('email', email);
          if (profile == null && userId.isNotEmpty) {
            profile = await runSelect('id', userId);
          }
        }

        final resolvedProfile =
            profile ??
            <String, dynamic>{
              if (userId.isNotEmpty) 'id': userId,
              'email': email,
              ...updates,
            };
        invalidateCurrentUserProfileCache();
        return resolvedProfile;
      } catch (e) {
        String? missingColumn;
        for (final candidate in const [
          'username',
          'subject',
          'semester',
          'branch',
          'bio',
        ]) {
          if (_isMissingColumnError(e, candidate)) {
            missingColumn = candidate;
            break;
          }
        }

        if (missingColumn == null) {
          debugPrint('Direct profile update failed: $e');
          rethrow;
        }

        updates.remove(missingColumn);
        selectColumns.remove(missingColumn);
        if (selectColumns.isEmpty) {
          debugPrint('Direct profile update failed: $e');
          rethrow;
        }
      }
    }
  }

  // ignore: unused_element
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
      await _api.markNotificationRead(notificationId);
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
    final cachedType = _cachedResolvedUserType;
    if (cachedType.type != ResolvedUserType.unauthenticated.type) {
      final cachedRole = cachedType.role?.trim();
      if (cachedRole != null && cachedRole.isNotEmpty) {
        return _normalizeRoleValue(cachedRole);
      }
      if (cachedType.isAdmin) return AppRoles.admin;
      if (cachedType.isCollegeUser) return AppRoles.collegeUser;
    }

    try {
      final identity = await getCurrentUserIdentity();
      if (identity.isNotEmpty) {
        final identityRole =
            (identity['user_role'] ??
                    identity['role'] ??
                    identity['admin_role'])
                ?.toString()
                .trim();
        if (identityRole != null && identityRole.isNotEmpty) {
          return _normalizeRoleValue(identityRole);
        }

        final resolvedType = resolveUserType(identity);
        if (resolvedType.isAdmin) return AppRoles.admin;
        if (resolvedType.isCollegeUser) return AppRoles.collegeUser;
      }
    } catch (e) {
      debugPrint('Failed to resolve role from user_identity cache: $e');
    }

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
    String? fileUrl,
    String? fileType,
  }) async {
    final normalizedImageUrl = imageUrl?.trim() ?? '';
    final normalizedFileUrl = fileUrl?.trim() ?? '';
    final normalizedFileType = fileType?.trim().toLowerCase() ?? '';
    final normalizedDepartment = normalizeDepartmentCode(department);
    if (normalizedDepartment.isEmpty) {
      throw Exception('Please select a valid department');
    }

    Object? backendError;
    StackTrace? backendStackTrace;
    try {
      await _api.createNotice(
        collegeId: collegeId,
        title: title,
        content: content,
        department: normalizedDepartment,
        imageUrl: normalizedImageUrl.isEmpty ? null : normalizedImageUrl,
        fileUrl: normalizedFileUrl.isEmpty ? null : normalizedFileUrl,
        fileType: normalizedFileType.isEmpty ? null : normalizedFileType,
      );
      return;
    } catch (e, stackTrace) {
      backendError = e;
      backendStackTrace = stackTrace;
      debugPrint('Backend notice post failed, retrying via Supabase: $e');
    }

    final hasAttachment =
        normalizedImageUrl.isNotEmpty || normalizedFileUrl.isNotEmpty;
    if (hasAttachment) {
      Error.throwWithStackTrace(backendError, backendStackTrace);
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
      'department': normalizedDepartment,
      'created_by': email,
      'created_by_name': displayName,
      if (normalizedImageUrl.isNotEmpty) 'image_url': normalizedImageUrl,
      if (normalizedFileUrl.isNotEmpty) 'file_url': normalizedFileUrl,
      if (normalizedFileType.isNotEmpty) 'file_type': normalizedFileType,
    };

    try {
      await _client.from('notices').insert(payload);
      try {
        await _notifyDepartmentFollowersForNotice(
          collegeId: collegeId,
          departmentId: normalizedDepartment,
          noticeTitle: title,
          noticeContent: content,
        );
      } catch (notifyError) {
        debugPrint(
          'Fallback department notification dispatch failed: $notifyError',
        );
      }
    } catch (e) {
      debugPrint('Error posting notice: $e');
      rethrow;
    }
  }

  Future<void> _notifyDepartmentFollowersForNotice({
    required String collegeId,
    required String departmentId,
    required String noticeTitle,
    required String noticeContent,
  }) async {
    final normalizedDepartmentId = normalizeDepartmentCode(departmentId);
    if (normalizedDepartmentId.isEmpty) return;

    final normalizedCollegeId = collegeId.trim();
    final senderUserId = currentUserId?.trim() ?? '';
    final senderEmail = _normalizeEmail(currentUserEmail);

    Future<List<Map<String, dynamic>>> fetchFollowers({
      required bool applyCollegeScope,
    }) async {
      var query = _client
          .from('department_followers')
          .select('user_id, follower_id, user_email, follower_email')
          .eq('department_id', normalizedDepartmentId);
      if (applyCollegeScope && normalizedCollegeId.isNotEmpty) {
        query = query.eq('college_id', normalizedCollegeId);
      }
      final response = await query;
      return List<Map<String, dynamic>>.from(response);
    }

    List<Map<String, dynamic>> followerRows = const [];
    try {
      followerRows = await fetchFollowers(applyCollegeScope: true);
      if (followerRows.isEmpty && normalizedCollegeId.isNotEmpty) {
        followerRows = await fetchFollowers(applyCollegeScope: false);
      }
    } catch (e) {
      if (_isMissingColumnError(e, 'college_id')) {
        try {
          followerRows = await fetchFollowers(applyCollegeScope: false);
        } catch (fallbackError) {
          debugPrint(
            'Error loading department followers for notifications: '
            '$e | $fallbackError',
          );
          return;
        }
      } else {
        debugPrint('Error loading department followers for notifications: $e');
        return;
      }
    }

    if (followerRows.isEmpty) return;

    final recipientUserIds = <String>{};
    final recipientEmails = <String>{};

    void addRecipientId(String? rawValue) {
      final value = rawValue?.trim() ?? '';
      if (value.isEmpty || value == senderUserId) return;
      recipientUserIds.add(value);
    }

    void addRecipientEmail(String? rawValue) {
      final value = _normalizeEmail(rawValue);
      if (value.isEmpty || value == senderEmail) return;
      recipientEmails.add(value);
    }

    for (final row in followerRows) {
      addRecipientId(row['user_id']?.toString());
      addRecipientId(row['follower_id']?.toString());
      addRecipientEmail(row['user_email']?.toString());
      addRecipientEmail(row['follower_email']?.toString());
    }

    if (recipientUserIds.isEmpty && recipientEmails.isEmpty) return;

    final departmentAccount = departmentAccountFromCode(normalizedDepartmentId);
    final notificationTitle = 'New notice from ${departmentAccount.name}';
    final rawMessage = noticeContent.trim().isNotEmpty
        ? noticeContent.trim()
        : noticeTitle.trim();
    final resolvedMessage = rawMessage.isNotEmpty
        ? rawMessage
        : 'A new notice is available.';
    final notificationMessage = resolvedMessage.length > 180
        ? '${resolvedMessage.substring(0, 177)}...'
        : resolvedMessage;

    final metadata = <String, dynamic>{
      'department_id': normalizedDepartmentId,
      if (normalizedCollegeId.isNotEmpty) 'college_id': normalizedCollegeId,
      'notice_title': noticeTitle.trim(),
    };

    for (final userId in recipientUserIds) {
      await _insertDepartmentNoticeNotification(
        userId: userId,
        title: notificationTitle,
        message: notificationMessage,
        metadata: metadata,
      );
    }

    for (final userEmail in recipientEmails) {
      await _insertDepartmentNoticeNotification(
        userEmail: userEmail,
        title: notificationTitle,
        message: notificationMessage,
        metadata: metadata,
      );
    }
  }

  Future<void> _insertDepartmentNoticeNotification({
    String? userId,
    String? userEmail,
    required String title,
    required String message,
    required Map<String, dynamic> metadata,
  }) async {
    final recipientPayloads = <Map<String, dynamic>>[
      if (userId != null && userId.trim().isNotEmpty)
        {'user_id': userId.trim()},
      if (userId != null && userId.trim().isNotEmpty)
        {'recipient_id': userId.trim()},
      if (userEmail != null && userEmail.trim().isNotEmpty)
        {'user_email': _normalizeEmail(userEmail)},
      if (userEmail != null && userEmail.trim().isNotEmpty)
        {'recipient_email': _normalizeEmail(userEmail)},
    ];

    if (recipientPayloads.isEmpty) return;

    final basePayloads = <Map<String, dynamic>>[
      {
        'type': 'department_notice',
        'title': title,
        'message': message,
        'is_read': false,
        'metadata': metadata,
      },
      {
        'type': 'department_notice',
        'title': title,
        'message': message,
        'is_read': false,
        'data': metadata,
      },
      {
        'type': 'department_notice',
        'title': title,
        'message': message,
        'is_read': false,
      },
    ];

    for (final recipient in recipientPayloads) {
      for (final basePayload in basePayloads) {
        try {
          await _client.from('notifications').insert({
            ...recipient,
            ...basePayload,
          });
          return;
        } catch (e) {
          final schemaIssue =
              _isMissingColumnError(e, 'user_id') ||
              _isMissingColumnError(e, 'recipient_id') ||
              _isMissingColumnError(e, 'user_email') ||
              _isMissingColumnError(e, 'recipient_email') ||
              _isMissingColumnError(e, 'metadata') ||
              _isMissingColumnError(e, 'data') ||
              _isMissingColumnError(e, 'is_read');
          if (!schemaIssue && !_isRowLevelSecurityError(e)) {
            debugPrint('Error creating department notice notification: $e');
          }
        }
      }
    }
  }

  Future<void> setNoticeVisibility({
    required String noticeId,
    required bool isActive,
  }) async {
    if (noticeId.trim().isEmpty) {
      throw Exception('Notice ID is required');
    }
    try {
      await _api.setNoticeVisibility(noticeId: noticeId, isActive: isActive);
    } catch (e) {
      debugPrint('Error updating notice visibility: $e');
      rethrow;
    }
  }

  Future<void> deleteNotice({required String noticeId}) async {
    if (noticeId.trim().isEmpty) {
      throw Exception('Notice ID is required');
    }
    try {
      await _api.deleteNotice(noticeId: noticeId);
    } catch (e) {
      debugPrint('Error deleting notice: $e');
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

  Future<List<Map<String, dynamic>>> discoverUsers({
    String? query,
    int limit = 50,
    String? collegeId,
    String? college,
  }) async {
    var effectiveCollegeId = collegeId?.trim() ?? '';
    var effectiveCollege = college?.trim() ?? '';

    if (effectiveCollegeId.isEmpty && effectiveCollege.isEmpty) {
      try {
        final profile = await getCurrentUserProfile(maxAttempts: 1);
        effectiveCollegeId = profile['college_id']?.toString().trim() ?? '';
        effectiveCollege = profile['college']?.toString().trim() ?? '';
      } catch (e) {
        debugPrint('Error deriving discover scope from profile: $e');
      }
    }

    if (effectiveCollegeId.isEmpty && effectiveCollege.isEmpty) {
      final sessionEmail = _currentSessionEmail();
      if (sessionEmail.contains('@')) {
        effectiveCollege = sessionEmail.split('@').last.trim();
      }
    }

    if (effectiveCollegeId.isEmpty && effectiveCollege.isEmpty) {
      debugPrint('Skipping discoverUsers due to missing college scope.');
      return const <Map<String, dynamic>>[];
    }

    final normalizedScopeCollege = _normalizeCollegeScopeValue(
      effectiveCollege,
    );
    final scopeLooksLikeDomain = _looksLikeDomainScope(normalizedScopeCollege);

    try {
      final users = await _api.discoverUsers(
        query: query,
        limit: limit,
        collegeId: effectiveCollegeId,
        college: effectiveCollege,
      );
      // Backend already scopes by college — trust its result.
      // A second client-side filter caused false negatives when API responses
      // didn't carry college_id in the exact shape _matchesCollegeScope needs.
      final normalizedUsers = users.map(_normalizeReadableUserRecord).toList();
      if (normalizedUsers.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
        return normalizedUsers;
      }
    } catch (e) {
      debugPrint('Error discovering users via backend: $e');
      if (!_hasConfiguredSupabaseAnonKey) {
        return const <Map<String, dynamic>>[];
      }
    }

    try {
      // Build a clean query. For college_id scope we also fetch users whose
      // college JSON contains the same college but who may have college_id=null
      // (legacy accounts). Both result sets are merged and deduplicated.
      final List<Map<String, dynamic>> allRows = [];
      final allEmails = <String>{};

      Future<void> runAndMerge(Future<List<dynamic>> Function() queryFn) async {
        try {
          final rows = await queryFn();
          for (final r in rows) {
            final rec = _normalizeReadableUserRecord(
              Map<String, dynamic>.from(r as Map),
            );
            final email = _normalizeEmail(rec['email']?.toString());
            if (email.isNotEmpty && !allEmails.contains(email)) {
              allEmails.add(email);
              allRows.add(rec);
            }
          }
        } catch (e) {
          debugPrint('discoverUsers sub-query failed: $e');
        }
      }

      String? safeSearchFilter; // built once if there is a text query
      if (query != null && query.isNotEmpty) {
        final nq = query
            .replaceAll(RegExp(r'[^a-zA-Z0-9@\s._-]'), ' ')
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');
        if (nq.isNotEmpty) {
          final sq = _escapeLikePattern(nq);
          safeSearchFilter = sq;
        }
      }

      if (effectiveCollegeId.isNotEmpty) {
        // Query 1: Users with exact college_id match
        await runAndMerge(() async {
          var q = _client
              .from('users_safe')
              .select(
                'id, email, display_name, username, profile_photo_url, college, college_id, bio',
              )
              .eq('college_id', effectiveCollegeId);
          if (safeSearchFilter != null) {
            q = q.or(
              'display_name.ilike.%$safeSearchFilter%,username.ilike.%$safeSearchFilter%,email.ilike.%$safeSearchFilter%',
            );
          }
          return q.limit(limit.clamp(1, 100));
        });
      } else if (effectiveCollege.isNotEmpty) {
        await runAndMerge(() async {
          var q = _client
              .from('users_safe')
              .select(
                'id, email, display_name, username, profile_photo_url, college, college_id, bio',
              );
          if (safeSearchFilter != null) {
            q = q.or(
              'display_name.ilike.%$safeSearchFilter%,username.ilike.%$safeSearchFilter%,email.ilike.%$safeSearchFilter%,college.ilike.%$safeSearchFilter%',
            );
          }
          if (scopeLooksLikeDomain) {
            final safeDomain = normalizedScopeCollege
                .replaceAll(RegExp(r'[%*,]'), '')
                .replaceAll('_', r'\_')
                .replaceAll('@', '');
            q = q.ilike('email', '%@$safeDomain');
          } else {
            q = q.ilike('college', '%${_escapeLikePattern(effectiveCollege)}%');
          }
          return q.limit(limit.clamp(1, 100));
        });
      }

      return allRows
          .where(
            (user) => _matchesCollegeScope(
              user,
              collegeId: effectiveCollegeId,
              college: effectiveCollege,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('Error discovering users: $e');
      return const <Map<String, dynamic>>[];
    }
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
          .from('users_safe')
          .select(
            'id, email, display_name, username, profile_photo_url, college, bio',
          )
          .ilike('email', '%@$safeDomain');

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final normalizedQuery = searchQuery
            .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');
        if (normalizedQuery.isNotEmpty) {
          final safeQuery = _escapeLikePattern(normalizedQuery);
          dbQuery = dbQuery.or(
            'display_name.ilike.%$safeQuery%,username.ilike.%$safeQuery%',
          );
        }
      }

      final response = await dbQuery.limit(50);
      return List<Map<String, dynamic>>.from(
        response,
      ).map(_normalizeReadableUserRecord).toList();
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
      final res = await _api.getFollowers(
        email:
            normalizedTarget.isNotEmpty && normalizedTarget != normalizedCurrent
            ? normalizedTarget
            : null,
      );
      final normalized = _normalizeSocialUsers(res['followers']);
      if (normalized.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
        return normalized;
      }
    } catch (e) {
      debugPrint('Backend followers lookup failed: $e');
      if (!_hasConfiguredSupabaseAnonKey) {
        return [];
      }
    }

    try {
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
          .from('users_safe')
          .select('email, display_name, profile_photo_url, username')
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
      final res = await _api.getFollowing(
        email:
            normalizedTarget.isNotEmpty && normalizedTarget != normalizedCurrent
            ? normalizedTarget
            : null,
      );
      final normalized = _normalizeSocialUsers(res['following']);
      if (normalized.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
        return normalized;
      }
    } catch (e) {
      debugPrint('Backend following lookup failed: $e');
      if (!_hasConfiguredSupabaseAnonKey) {
        return [];
      }
    }

    try {
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
          .from('users_safe')
          .select('email, display_name, profile_photo_url, username')
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
    final normalizedFollower = _requireCurrentSessionEmail(
      claimedEmail: followerEmail,
      action: 'is_following',
    );
    try {
      final response = await _client.from('follows').select().match({
        'follower_email': normalizedFollower,
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
      final results = await Future.wait<dynamic>([
        getFollowersCount(userEmail),
        getFollowingCount(userEmail),
        // Fetch resources via backend — we use the payload's `total`/`count`
        // field so the contributions number is correct even when the backend
        // paginates and only returns a slice.
        _api.getPublicUserResources(
          email: _normalizeEmail(userEmail),
          approvedOnly: true,
          limit: 1, // We only need the count metadata, not every resource.
          offset: 0,
        ),
      ]);
      final followers = (results[0] as num?)?.toInt() ?? 0;
      final following = (results[1] as num?)?.toInt() ?? 0;

      // Prefer the authoritative total count from the backend response.
      final payload = results[2] as Map<String, dynamic>;
      int fetchedTotal = 0;
      if (_normalizeCount(payload['total']) > 0) {
        fetchedTotal = _normalizeCount(payload['total']);
      } else if (_normalizeCount(payload['count']) > 0) {
        fetchedTotal = _normalizeCount(payload['count']);
      } else {
        final resources = payload['resources'];
        final isList = resources is List;
        final listLength = isList ? resources.length : 0;

        if (listLength <= 1) {
          try {
            final retryPayload = await _api.getPublicUserResources(
              email: _normalizeEmail(userEmail),
              approvedOnly: true,
              limit: 50,
              offset: 0,
            );
            if (_normalizeCount(retryPayload['total']) > 0) {
              fetchedTotal = _normalizeCount(retryPayload['total']);
            } else if (_normalizeCount(retryPayload['count']) > 0) {
              fetchedTotal = _normalizeCount(retryPayload['count']);
            } else {
              final retryResources = retryPayload['resources'];
              fetchedTotal = retryResources is List ? retryResources.length : 0;
            }
          } catch (_) {
            fetchedTotal = listLength;
          }
        } else {
          fetchedTotal = listLength;
        }
      }

      final contributions = _normalizeCount(fetchedTotal);

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
      final normalizedTarget = _normalizeEmail(userEmail);
      final normalizedCurrent = _currentSessionEmail();
      try {
        final res = await _api.getFollowers(
          email:
              normalizedTarget.isNotEmpty &&
                  normalizedTarget != normalizedCurrent
              ? normalizedTarget
              : null,
        );
        final count = _normalizeCount(res['count'] ?? res['followers']);
        if (res.containsKey('count') ||
            count > 0 ||
            !_hasConfiguredSupabaseAnonKey) {
          return count;
        }
      } catch (e) {
        debugPrint('Backend followers count lookup failed: $e');
        if (!_hasConfiguredSupabaseAnonKey) {
          return 0;
        }
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
      final normalizedTarget = _normalizeEmail(userEmail);
      final normalizedCurrent = _currentSessionEmail();
      try {
        final res = await _api.getFollowing(
          email:
              normalizedTarget.isNotEmpty &&
                  normalizedTarget != normalizedCurrent
              ? normalizedTarget
              : null,
        );
        final count = _normalizeCount(res['count'] ?? res['following']);
        if (res.containsKey('count') ||
            count > 0 ||
            !_hasConfiguredSupabaseAnonKey) {
          return count;
        }
      } catch (e) {
        debugPrint('Backend following count lookup failed: $e');
        if (!_hasConfiguredSupabaseAnonKey) {
          return 0;
        }
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
          .whereType<Map>()
          .map((row) => row[column]?.toString().trim())
          .where((v) => v != null && v.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();

      values.sort();
      _uniqueValuesCache[cacheKey] = (
        cachedAt: DateTime.now(),
        data: List<String>.unmodifiable(values),
      );
      _pruneUniqueValuesCacheIfNeeded();
      return values;
    } catch (e) {
      debugPrint('Error fetching unique values for $column: $e');
      final backendValues = await _getUniqueValuesFromBackend(
        column: column,
        collegeId: collegeId,
        branch: branch,
      );
      if (backendValues.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
        _uniqueValuesCache[cacheKey] = (
          cachedAt: DateTime.now(),
          data: List<String>.unmodifiable(backendValues),
        );
        _pruneUniqueValuesCacheIfNeeded();
        return backendValues;
      }
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
      final payload = await _api.getChatRoomInfo(roomId);
      final roomRaw = payload['room'];
      if (roomRaw is Map) {
        final room = Map<String, dynamic>.from(roomRaw);
        room['isMember'] = payload['isMember'] == true;
        room['isAdmin'] = payload['isAdmin'] == true;
        if (room['created_by_email'] == null && room['created_by'] != null) {
          room['created_by_email'] = room['created_by'];
        }
        return room;
      }
    } catch (e) {
      debugPrint('Backend getRoomInfo failed, using direct fallback: $e');
    }

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

  Future<Map<String, dynamic>?> getRoomPostById(
    String roomId,
    String postId,
  ) async {
    Future<Map<String, dynamic>> normalizePost(
      Map<String, dynamic> rawPost,
    ) async {
      final post = Map<String, dynamic>.from(rawPost);
      post['comment_count'] = _normalizeCount(post['comment_count']);
      post['upvotes'] = _normalizeCount(post['upvotes']);
      post['downvotes'] = _normalizeCount(post['downvotes']);

      if ((post['author_email']?.toString().trim().isEmpty ?? true) &&
          (post['user_email']?.toString().trim().isNotEmpty ?? false)) {
        post['author_email'] = post['user_email'];
      }

      final usersByEmail = await _fetchUsersByEmails(<String>[
        post['author_email']?.toString() ??
            post['user_email']?.toString() ??
            '',
      ]);
      final hasAuthorEmail =
          post['author_email']?.toString().trim().isNotEmpty ?? false;
      _applyProfileToRecord(
        record: post,
        emailKey: hasAuthorEmail ? 'author_email' : 'user_email',
        outputNameKey: 'author_name',
        outputPhotoKey: 'author_photo_url',
        usersByEmail: usersByEmail,
        existingNameKeys: const ['user_name', 'display_name'],
        existingPhotoKeys: const [
          'profile_photo_url',
          'photo_url',
          'avatar_url',
        ],
      );

      final resolvedPhoto = _firstNonEmptyValue(post, const [
        'author_photo_url',
        'profile_photo_url',
        'photo_url',
        'avatar_url',
      ]);
      if (resolvedPhoto.isNotEmpty) {
        post['author_photo_url'] = resolvedPhoto;
        post['profile_photo_url'] = resolvedPhoto;
      }

      return post;
    }

    try {
      final post = await _api.getChatRoomPost(roomId, postId);
      return normalizePost(post);
    } catch (e) {
      debugPrint('Backend getRoomPostById failed: $e');
      return null;
    }
  }

  Future<DateTime?> extendRoomExpiry(String roomId, {int days = 7}) async {
    try {
      final payload = await _api.extendRoomExpiry(roomId: roomId, days: days);
      final expiryRaw = payload['expiry_date']?.toString();
      if (expiryRaw == null || expiryRaw.trim().isEmpty) {
        return null;
      }
      return DateTime.tryParse(expiryRaw.trim());
    } catch (e) {
      debugPrint('Error extending room expiry: $e');
      rethrow;
    }
  }

  /// Get total posts and today's posts for a room.
  Future<({int total, int today})> getRoomPostCounts(String roomId) async {
    try {
      final total = await _client
          .from('room_messages')
          .count(CountOption.exact)
          .eq('room_id', roomId);

      final now = DateTime.now();
      final startOfDayLocal = DateTime(now.year, now.month, now.day);
      final startOfDayUtc = startOfDayLocal.toUtc();

      final today = await _client
          .from('room_messages')
          .count(CountOption.exact)
          .eq('room_id', roomId)
          .gte('created_at', startOfDayUtc.toIso8601String());

      return (total: total, today: today);
    } catch (e) {
      debugPrint('Error fetching room post counts: $e');
      return (total: 0, today: 0);
    }
  }

  /// Check if user is room admin
  Future<bool> isRoomAdmin(String roomId, String userEmail) async {
    try {
      final payload = await _api.getChatRoomInfo(roomId);
      if (payload['isAdmin'] == true) {
        return true;
      }
    } catch (_) {}

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
      final members = await _api.getChatRoomMembers(roomId);
      if (members.isNotEmpty) {
        return members.map((entry) {
          final normalized = Map<String, dynamic>.from(entry);
          final email = _normalizeEmail(
            normalized['user_email']?.toString() ??
                normalized['email']?.toString() ??
                '',
          );
          normalized['user_email'] = email;
          normalized['role'] = (normalized['role'] ?? 'member')
              .toString()
              .toLowerCase();
          final resolvedPhoto = _firstNonEmptyValue(normalized, const [
            'profile_photo_url',
            'photo_url',
            'avatar_url',
          ]);
          if (resolvedPhoto.isNotEmpty) {
            normalized['profile_photo_url'] = resolvedPhoto;
            normalized['photo_url'] = resolvedPhoto;
            normalized['avatar_url'] = resolvedPhoto;
          }
          final fallbackName = email.contains('@')
              ? email.split('@').first
              : 'Member';
          final displayName = _firstNonEmptyValue(normalized, const [
            'display_name',
            'user_name',
            'full_name',
            'name',
          ]);
          normalized['display_name'] = displayName.isEmpty
              ? fallbackName
              : displayName;
          return normalized;
        }).toList();
      }
    } catch (e) {
      debugPrint('Backend getRoomMembers failed, using direct fallback: $e');
    }

    try {
      final response = await _client
          .from('room_members')
          .select('*')
          .eq('room_id', roomId)
          .order('created_at', ascending: true);
      final members = List<Map<String, dynamic>>.from(response);
      final usersByEmail = await _fetchUsersByEmails(
        members.map((member) => member['user_email']?.toString() ?? ''),
      );

      for (final member in members) {
        _applyProfileToRecord(
          record: member,
          emailKey: 'user_email',
          outputNameKey: 'display_name',
          outputPhotoKey: 'profile_photo_url',
          usersByEmail: usersByEmail,
          existingNameKeys: const ['user_name', 'full_name', 'name'],
          existingPhotoKeys: const ['photo_url', 'avatar_url'],
        );

        final resolvedPhoto = _firstNonEmptyValue(member, const [
          'profile_photo_url',
          'photo_url',
          'avatar_url',
        ]);
        if (resolvedPhoto.isNotEmpty) {
          member['profile_photo_url'] = resolvedPhoto;
          member['photo_url'] = resolvedPhoto;
          member['avatar_url'] = resolvedPhoto;
        }
      }

      return members;
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
    int limit = 20,
    int offset = 0,
    String sortBy = 'recent',
  }) async {
    Future<List<Map<String, dynamic>>> normalizePosts(
      List<Map<String, dynamic>> rawPosts,
    ) async {
      final posts = rawPosts.map((entry) {
        final data = Map<String, dynamic>.from(entry);
        data['comment_count'] = _normalizeCount(data['comment_count']);
        data['upvotes'] = _normalizeCount(data['upvotes']);
        data['downvotes'] = _normalizeCount(data['downvotes']);
        return data;
      }).toList();

      final needsEnrichment = posts.any((post) {
        final authorName = _firstNonEmptyValue(post, const [
          'author_name',
          'user_name',
          'display_name',
        ]);
        final authorPhoto = _firstNonEmptyValue(post, const [
          'author_photo_url',
          'profile_photo_url',
          'photo_url',
          'avatar_url',
        ]);
        return authorName.isEmpty || authorPhoto.isEmpty;
      });

      final usersByEmail = needsEnrichment
          ? await _fetchUsersByEmails(
              posts.map(
                (post) =>
                    post['author_email']?.toString() ??
                    post['user_email']?.toString() ??
                    '',
              ),
            )
          : const <String, Map<String, dynamic>>{};

      for (final post in posts) {
        if ((post['author_email']?.toString().trim().isEmpty ?? true) &&
            (post['user_email']?.toString().trim().isNotEmpty ?? false)) {
          post['author_email'] = post['user_email'];
        }

        final hasAuthorEmail =
            post['author_email']?.toString().trim().isNotEmpty ?? false;
        _applyProfileToRecord(
          record: post,
          emailKey: hasAuthorEmail ? 'author_email' : 'user_email',
          outputNameKey: 'author_name',
          outputPhotoKey: 'author_photo_url',
          usersByEmail: usersByEmail,
          existingNameKeys: const ['user_name', 'display_name'],
          existingPhotoKeys: const [
            'profile_photo_url',
            'photo_url',
            'avatar_url',
          ],
        );
        final resolvedPhoto = _firstNonEmptyValue(post, const [
          'author_photo_url',
          'profile_photo_url',
          'photo_url',
          'avatar_url',
        ]);
        if (resolvedPhoto.isNotEmpty) {
          post['author_photo_url'] = resolvedPhoto;
          post['profile_photo_url'] = resolvedPhoto;
        }
      }

      return posts;
    }

    try {
      final backendPosts = await _api.getChatRoomPosts(
        roomId,
        limit: limit + (offset < 0 ? 0 : offset),
        sortBy: sortBy,
      );
      final safeOffset = offset < 0 ? 0 : offset;
      if (safeOffset >= backendPosts.length) {
        return const <Map<String, dynamic>>[];
      }
      final end = (safeOffset + limit).clamp(0, backendPosts.length);
      return normalizePosts(backendPosts.sublist(safeOffset, end));
    } catch (backendError) {
      debugPrint(
        'Backend getRoomPosts failed, falling back to Supabase: $backendError',
      );
    }

    if (!_hasConfiguredSupabaseAnonKey) {
      return const <Map<String, dynamic>>[];
    }

    try {
      final String orderColumn = sortBy == 'top' ? 'upvotes' : 'created_at';
      final response = await _client
          .from('room_messages')
          .select('*, comment_count:room_post_comments(count)')
          .eq('room_id', roomId)
          .order(orderColumn, ascending: false)
          .range(
            offset < 0 ? 0 : offset,
            (offset < 0 ? 0 : offset) + limit - 1,
          );
      return normalizePosts(
        (response as List)
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList(),
      );
    } catch (e) {
      debugPrint('Error fetching room posts via Supabase: $e');
      try {
        final backendPosts = await _api.getChatRoomPosts(
          roomId,
          limit: limit + (offset < 0 ? 0 : offset),
          sortBy: sortBy,
        );
        final safeOffset = offset < 0 ? 0 : offset;
        if (safeOffset >= backendPosts.length) {
          return const <Map<String, dynamic>>[];
        }
        final end = (safeOffset + limit).clamp(0, backendPosts.length);
        final sliced = backendPosts.sublist(safeOffset, end);
        if (sliced.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
          return normalizePosts(sliced);
        }
      } catch (backendError) {
        debugPrint('Backend getRoomPosts fallback failed: $backendError');
      }
      return [];
    }
  }

  /// Get posts authored by a user across all rooms.
  Future<List<Map<String, dynamic>>> getUserPostsAcrossRooms(
    String userEmail, {
    int limit = 100,
  }) async {
    final normalizedEmail = _normalizeEmail(userEmail);
    if (normalizedEmail.isEmpty) return [];

    final merged = <String, Map<String, dynamic>>{};

    void mergeRows(List<dynamic> rows) {
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        row['comment_count'] = _normalizeCount(row['comment_count']);
        merged[id] = row;
      }
    }

    try {
      final authorRows = await _client
          .from('room_messages')
          .select('*, comment_count:room_post_comments(count)')
          .eq('author_email', normalizedEmail)
          .order('created_at', ascending: false)
          .range(0, limit - 1);
      mergeRows(authorRows as List<dynamic>);
    } catch (e) {
      debugPrint('getUserPostsAcrossRooms author_email lookup failed: $e');
    }

    try {
      final userRows = await _client
          .from('room_messages')
          .select('*, comment_count:room_post_comments(count)')
          .eq('user_email', normalizedEmail)
          .order('created_at', ascending: false)
          .range(0, limit - 1);
      mergeRows(userRows as List<dynamic>);
    } catch (e) {
      debugPrint('getUserPostsAcrossRooms user_email lookup failed: $e');
    }

    final posts = merged.values.toList();
    if (posts.isEmpty) return [];

    final usersByEmail = await _fetchUsersByEmails(
      posts.map(
        (post) =>
            post['author_email']?.toString() ??
            post['user_email']?.toString() ??
            '',
      ),
    );

    for (final post in posts) {
      if ((post['author_email']?.toString().trim().isEmpty ?? true) &&
          (post['user_email']?.toString().trim().isNotEmpty ?? false)) {
        post['author_email'] = post['user_email'];
      }

      _applyProfileToRecord(
        record: post,
        emailKey: 'author_email',
        outputNameKey: 'author_name',
        outputPhotoKey: 'author_photo_url',
        usersByEmail: usersByEmail,
        existingNameKeys: const ['user_name', 'display_name'],
        existingPhotoKeys: const [
          'profile_photo_url',
          'photo_url',
          'avatar_url',
        ],
      );
    }

    final roomIds = posts
        .map((post) => post['room_id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final roomNameById = <String, String>{};
    if (roomIds.isNotEmpty) {
      try {
        final roomRows = await _client
            .from('chat_rooms')
            .select('id, name')
            .inFilter('id', roomIds);
        for (final raw in (roomRows as List<dynamic>)) {
          final room = Map<String, dynamic>.from(raw as Map);
          final id = room['id']?.toString().trim() ?? '';
          final name = room['name']?.toString().trim() ?? '';
          if (id.isEmpty || name.isEmpty) continue;
          roomNameById[id] = name;
        }
      } catch (e) {
        debugPrint('getUserPostsAcrossRooms room lookup failed: $e');
      }
    }

    for (final post in posts) {
      final roomId = post['room_id']?.toString().trim() ?? '';
      if (roomId.isEmpty) continue;
      final roomName = roomNameById[roomId];
      if (roomName != null && roomName.isNotEmpty) {
        post['room_name'] = roomName;
      }
    }

    posts.sort((a, b) {
      final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '');
      final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '');
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return posts;
  }

  /// Get comments for a post
  Future<List<Map<String, dynamic>>> getPostComments(String postId) async {
    List<Map<String, dynamic>> allComments = [];

    try {
      allComments = await _api.getChatComments(postId);
    } catch (backendError) {
      debugPrint(
        'Backend comment fetch failed, falling back to Supabase: $backendError',
      );
    }

    if (allComments.isEmpty && _hasConfiguredSupabaseAnonKey) {
      try {
        final response = await _client
            .from('room_post_comments')
            .select('*')
            .eq('message_id', postId)
            .order('created_at', ascending: true);

        allComments = List<Map<String, dynamic>>.from(
          response,
        ).map((row) => Map<String, dynamic>.from(row)).toList();
      } catch (directError) {
        debugPrint(
          'Error fetching post comments (backend + direct failed): $directError',
        );
        return [];
      }
    }

    try {
      final needsEnrichment = allComments.any((comment) {
        final authorName = _firstNonEmptyValue(comment, const [
          'author_name',
          'user_name',
          'display_name',
        ]);
        final authorPhoto = _firstNonEmptyValue(comment, const [
          'author_photo_url',
          'profile_photo_url',
          'photo_url',
          'avatar_url',
        ]);
        return authorName.isEmpty || authorPhoto.isEmpty;
      });

      final usersByEmail = needsEnrichment
          ? await _fetchUsersByEmails(
              allComments.map(
                (comment) =>
                    comment['author_email']?.toString() ??
                    comment['user_email']?.toString() ??
                    '',
              ),
            )
          : const <String, Map<String, dynamic>>{};

      for (final comment in allComments) {
        if ((comment['author_email']?.toString().trim().isEmpty ?? true) &&
            (comment['user_email']?.toString().trim().isNotEmpty ?? false)) {
          comment['author_email'] = comment['user_email'];
        }

        _applyProfileToRecord(
          record: comment,
          emailKey: 'author_email',
          outputNameKey: 'author_name',
          outputPhotoKey: 'author_photo_url',
          usersByEmail: usersByEmail,
          existingNameKeys: const ['user_name', 'display_name'],
          existingPhotoKeys: const [
            'profile_photo_url',
            'photo_url',
            'avatar_url',
          ],
        );

        final resolvedPhoto = _firstNonEmptyValue(comment, const [
          'author_photo_url',
          'profile_photo_url',
          'photo_url',
          'avatar_url',
        ]);
        if (resolvedPhoto.isNotEmpty) {
          comment['author_photo_url'] = resolvedPhoto;
          comment['profile_photo_url'] = resolvedPhoto;
        }
      }

      // Build thread structure (Client-side threading)
      final Map<String, List<Map<String, dynamic>>> commentMap = {};
      final List<Map<String, dynamic>> topLevelComments = [];

      // First pass: organize comments by parent_id
      for (var comment in allComments) {
        final parentIdRaw = comment['parentId'] ?? comment['parent_id'];
        final parentId = parentIdRaw?.toString().trim();
        // Ensure replies list exists
        comment['replies'] = <Map<String, dynamic>>[];

        if (parentId == null || parentId.isEmpty) {
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
    String? imageFileId,
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
        imageFileId: imageFileId,
        authorName: userName,
        context: ctx,
      );
    } catch (e) {
      debugPrint('Error creating post: $e');
      rethrow;
    }
  }

  Future<void> updatePost({
    required String postId,
    required String content,
  }) async {
    try {
      await _api.updateChatMessage(messageId: postId, content: content);
    } catch (e) {
      debugPrint('Error updating post: $e');
      rethrow;
    }
  }

  Future<void> deletePost(String postId) async {
    try {
      await _api.deleteChatMessage(messageId: postId);
    } catch (e) {
      debugPrint('Error deleting post: $e');
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

  String? _extractMissingColumnName(Object error) {
    final match = RegExp(
      r'column\s+"([^"]+)"\s+does\s+not\s+exist',
      caseSensitive: false,
    ).firstMatch(error.toString());
    return match?.group(1);
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

    const columns = <String>[
      'user_email',
      'user_id',
      'message_id',
      'post_id',
      'room_id',
      'created_at',
    ];
    final checksByColumn = <String, bool>{
      for (final column in columns) column: true,
    };

    var shouldFallbackToPerColumnChecks = false;
    try {
      await _client.from('saved_posts').select(columns.join(',')).limit(1);
    } catch (error) {
      final missingColumn = _extractMissingColumnName(error);
      if (missingColumn != null && checksByColumn.containsKey(missingColumn)) {
        checksByColumn[missingColumn] = false;
      } else {
        shouldFallbackToPerColumnChecks = true;
      }
    }

    if (shouldFallbackToPerColumnChecks) {
      for (final column in columns) {
        checksByColumn[column] = await _savedPostsColumnExists(column);
      }
    } else {
      for (final column in columns) {
        if (checksByColumn[column] == false) continue;
        checksByColumn[column] = await _savedPostsColumnExists(column);
      }
    }

    final schema = (
      hasUserEmail: checksByColumn['user_email'] ?? false,
      hasUserId: checksByColumn['user_id'] ?? false,
      hasMessageId: checksByColumn['message_id'] ?? false,
      hasPostId: checksByColumn['post_id'] ?? false,
      hasRoomId: checksByColumn['room_id'] ?? false,
      hasCreatedAt: checksByColumn['created_at'] ?? false,
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
    final normalizedEmail = _requireCurrentSessionEmail(
      claimedEmail: userEmail,
      action: 'save_post',
    );

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
    final normalizedEmail = _requireCurrentSessionEmail(
      claimedEmail: userEmail,
      action: 'is_post_saved',
    );
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) return false;

    try {
      final directSavedIds = await _getSavedPostIdsDirect(normalizedEmail);
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
          .eq('user_email', normalizedEmail)
          .maybeSingle();
      return response != null;
    } catch (e) {
      // Try checking if it's saved by message_id directly if legacy schema
      try {
        final response = await _client
            .from('saved_posts')
            .select('id')
            .eq('post_id', normalizedPostId)
            .eq('user_email', normalizedEmail)
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
    final normalizedEmail = _requireCurrentSessionEmail(
      claimedEmail: userEmail,
      action: 'unsave_post',
    );

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
    final normalizedEmail = _requireCurrentSessionEmail(
      claimedEmail: userEmail,
      action: 'get_saved_post_ids',
    );

    if (!_hasConfiguredSupabaseAnonKey) {
      try {
        final savedPosts = await _getSavedPostsFromBackend();
        return savedPosts
            .map((row) => row['id']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>()
            .toSet();
      } catch (e) {
        debugPrint('Backend saved post lookup failed: $e');
        return <String>{};
      }
    }

    final combinedIds = <String>{};
    var hasAuthoritativeSource = false;

    try {
      final directIds = await _getSavedPostIdsDirect(normalizedEmail);
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
    final normalizedEmail = _requireCurrentSessionEmail(
      claimedEmail: userEmail,
      action: 'get_saved_posts',
    );
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
      mergeRows(await _getSavedPostsDirect(normalizedEmail));
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
    const maxAttempts = 2;
    var attempt = 0;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        await _api.uploadSyllabusAsAdmin(
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
        final isTransientError = _isAdminUploadTransientError(adminUploadError);
        final isServerError = _isAdminUploadServerError(adminUploadError);

        if (isAuthError) {
          debugPrint(
            'Admin syllabus upload auth failure; '
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

  Map<String, dynamic> _buildDirectResourcePayload(Map<String, dynamic> input) {
    final payload = Map<String, dynamic>.from(input);
    final type = (payload['type']?.toString() ?? 'notes').trim();
    final normalizedType = type.toLowerCase();
    final fileUrl =
        <dynamic>[
              payload['file_url'],
              payload['fileUrl'],
              payload['pdf_url'],
              payload['pdfUrl'],
              payload['video_url'],
              payload['videoUrl'],
              payload['url'],
            ]
            .map((value) => value?.toString().trim() ?? '')
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    if (fileUrl.isNotEmpty) {
      if (normalizedType == 'video') {
        payload.remove('file_url');
        payload.remove('fileUrl');
        payload['video_url'] ??= fileUrl;
      } else {
        payload['file_url'] = fileUrl;
        payload['pdf_url'] ??= fileUrl;
      }
    }

    payload.remove('url');

    payload.removeWhere((key, value) {
      if (value == null) return true;
      if (value is String && value.trim().isEmpty) return true;
      return false;
    });

    return payload;
  }

  Future<void> createResourceWithFallback(
    Map<String, dynamic> input, {
    required BuildContext context,
  }) async {
    final payload = _buildDirectResourcePayload(input);
    final uploaderEmail = _requireCurrentSessionEmail(
      claimedEmail: payload['uploaded_by_email']?.toString(),
      action: 'create_resource',
    );
    payload['uploaded_by_email'] = uploaderEmail;

    try {
      await _api.createResource(payload, context: context);
      invalidateResourceListCache();
      return;
    } catch (backendError) {
      debugPrint(
        'Backend resource create failed; falling back to direct insert: '
        '$backendError',
      );
    }

    final directPayload = Map<String, dynamic>.from(payload);
    try {
      await _client.from('resources').insert(directPayload);
      invalidateResourceListCache();
      return;
    } catch (primaryError) {
      final fallbackPayload =
          <String, dynamic>{
            'college_id': payload['college_id'],
            'title': payload['title'],
            'type': payload['type'],
            'semester': payload['semester'],
            'branch': payload['branch'],
            'subject': payload['subject'],
            'description': payload['description'],
            'uploaded_by_email': payload['uploaded_by_email'],
            'uploaded_by_name': payload['uploaded_by_name'],
            if (payload['file_url'] != null) 'file_url': payload['file_url'],
            if (payload['video_url'] != null) 'video_url': payload['video_url'],
            if (payload['status'] != null) 'status': payload['status'],
            if (payload['chapter'] != null) 'chapter': payload['chapter'],
            if (payload['topic'] != null) 'topic': payload['topic'],
          }..removeWhere((key, value) {
            if (value == null) return true;
            if (value is String && value.trim().isEmpty) return true;
            return false;
          });

      try {
        await _client.from('resources').insert(fallbackPayload);
        invalidateResourceListCache();
        return;
      } catch (legacyError) {
        debugPrint(
          'Direct resource insert failed: $primaryError | $legacyError',
        );
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

  Future<void> updateResourceStatusWithFallback({
    required String resourceId,
    required String status,
    required BuildContext context,
  }) async {
    Object? backendError;
    try {
      await _api.updateResourceStatus(
        resourceId: resourceId,
        status: status,
        context: context,
      );
      invalidateResourceListCache();
      return;
    } catch (error) {
      backendError = error;
      debugPrint(
        'Backend resource moderation failed; falling back to direct update: '
        '$error',
      );
    }

    try {
      final updated = await _client
          .from('resources')
          .update(<String, dynamic>{
            'status': status,
            'is_approved': status.trim().toLowerCase() == 'approved',
          })
          .eq('id', resourceId)
          .select('id, status, is_approved')
          .maybeSingle();
      if (updated == null) {
        throw Exception(
          'Resource moderation did not update any row for $resourceId.',
        );
      }
    } catch (error) {
      if (_isNoRowsMutationResult(error)) {
        debugPrint(
          'No-rows mutation result while updating resource status: '
          '${backendError.toString()}',
        );
        throw Exception('Operation failed; please try again.');
      }
      rethrow;
    }
    invalidateResourceListCache();
  }

  Future<void> deleteResourceAsAdminWithFallback({
    required String resourceId,
  }) async {
    await _api.deleteResourceAsAdmin(resourceId: resourceId);
    invalidateResourceListCache();
  }

  Future<void> deleteOwnedResource({
    required Resource resource,
    String? ownerEmail,
  }) async {
    final activeOwner = _requireCurrentSessionEmail(
      claimedEmail: ownerEmail,
      action: 'delete_owned_resource',
    );

    Object? backendError;
    try {
      await _api.deleteOwnedResource(resourceId: resource.id);
      invalidateResourceListCache();
      return;
    } catch (error) {
      backendError = error;
      debugPrint(
        'Backend owned resource delete failed; falling back to direct delete: '
        '$error',
      );
    }

    final row = await _client
        .from('resources')
        .select('id, uploaded_by_email')
        .eq('id', resource.id)
        .maybeSingle();

    if (row == null) {
      throw Exception(
        'Contribution not found for ${resource.id}: '
        '${backendError.toString()}',
      );
    }

    final rowMap = Map<String, dynamic>.from(row);
    final rowOwner = _normalizeEmail(
      rowMap['uploaded_by_email']?.toString() ?? resource.uploadedByEmail,
    );

    if (rowOwner.isNotEmpty && rowOwner == activeOwner) {
      // User is the canonical owner — delete the full resource record.
      try {
        final deleted = await _client
            .from('resources')
            .delete()
            .eq('id', resource.id)
            .select('id')
            .maybeSingle();
        if (deleted == null) {
          throw Exception(
            'Contribution delete did not affect any row for ${resource.id}.',
          );
        }
      } catch (error) {
        if (_isNoRowsMutationResult(error)) {
          throw Exception(error.toString());
        }
        rethrow;
      }
    } else {
      // User is not the canonical owner — check if they are a contributor and
      // remove only their contributor row so others keep access to the resource.
      final contributorRow = await _client
          .from('resource_contributors')
          .select('id')
          .eq('resource_id', resource.id)
          .eq('user_email', activeOwner)
          .maybeSingle();

      if (contributorRow == null) {
        throw Exception('You can delete only your own contributions.');
      }

      await _client
          .from('resource_contributors')
          .delete()
          .eq('resource_id', resource.id)
          .eq('user_email', activeOwner);
    }
    invalidateResourceListCache();
  }

  // ============ DEPARTMENT FOLLOWERS ============

  Future<String> _resolveDepartmentCollegeScope(String? collegeId) async {
    final normalizedInput = _normalizeCollegeScopeValue(collegeId);
    if (normalizedInput.isNotEmpty) {
      return normalizedInput;
    }

    try {
      final profile = await getCurrentUserProfile(maxAttempts: 1);
      final profileCollegeId = _normalizeCollegeScopeValue(
        profile['college_id']?.toString(),
      );
      if (profileCollegeId.isNotEmpty) {
        return profileCollegeId;
      }

      final profileCollege = _normalizeCollegeScopeValue(
        profile['college']?.toString(),
      );
      if (profileCollege.isNotEmpty) {
        return profileCollege;
      }
    } catch (e) {
      debugPrint('Error resolving department college scope: $e');
    }

    return '';
  }

  /// Follow a department
  Future<void> followDepartment(
    String departmentId,
    String collegeId,
    String userEmail,
  ) async {
    final normalizedDepartmentId = normalizeDepartmentCode(departmentId);
    final normalizedCollegeId = await _resolveDepartmentCollegeScope(collegeId);
    if (normalizedDepartmentId.isEmpty) {
      throw Exception('Department ID is required');
    }

    try {
      await _api.followDepartment(
        normalizedDepartmentId,
        collegeId: normalizedCollegeId.isNotEmpty ? normalizedCollegeId : null,
      );
    } catch (e) {
      debugPrint('Error following department via API: $e');
      rethrow;
    }
  }

  /// Unfollow a department
  Future<void> unfollowDepartment(
    String departmentId,
    String userEmail, {
    String? collegeId,
  }) async {
    final normalizedDepartmentId = normalizeDepartmentCode(departmentId);
    final normalizedCollegeId = await _resolveDepartmentCollegeScope(collegeId);
    if (normalizedDepartmentId.isEmpty) {
      throw Exception('Department ID is required');
    }

    try {
      await _api.unfollowDepartment(
        normalizedDepartmentId,
        collegeId: normalizedCollegeId.isNotEmpty ? normalizedCollegeId : null,
      );
    } catch (e) {
      debugPrint('Error unfollowing department via API: $e');
      rethrow;
    }
  }

  Future<List<DepartmentOption>> getNoticeDepartments() async {
    final cachedDepartments = _noticeDepartmentsCache;
    if (cachedDepartments != null &&
        DateTime.now().difference(cachedDepartments.cachedAt) <
            _noticeDepartmentsCacheTtl) {
      return List<DepartmentOption>.from(cachedDepartments.data);
    }

    try {
      final backendRows = await _api.getDepartments();
      final normalized = <String, DepartmentOption>{};
      for (final row in backendRows) {
        final id = normalizeDepartmentCode(row['code']?.toString());
        final name = row['name']?.toString().trim() ?? '';
        if (id.isEmpty || name.isEmpty) continue;
        normalized[id] = DepartmentOption(id: id, name: name);
      }
      if (normalized.isNotEmpty) {
        final resolved = normalized.values.toList(growable: false);
        _noticeDepartmentsCache = (
          cachedAt: DateTime.now(),
          data: List<DepartmentOption>.unmodifiable(resolved),
        );
        return resolved;
      }
    } catch (e) {
      debugPrint('Backend departments lookup failed, trying Supabase: $e');
    }

    try {
      final rows = await _client
          .from('departments')
          .select('code, name, is_active')
          .eq('is_active', true)
          .order('name', ascending: true);
      final normalized = <String, DepartmentOption>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final id = normalizeDepartmentCode(row['code']?.toString());
        final name = row['name']?.toString().trim() ?? '';
        if (id.isEmpty || name.isEmpty) continue;
        normalized[id] = DepartmentOption(id: id, name: name);
      }
      if (normalized.isNotEmpty) {
        final resolved = normalized.values.toList(growable: false);
        _noticeDepartmentsCache = (
          cachedAt: DateTime.now(),
          data: List<DepartmentOption>.unmodifiable(resolved),
        );
        return resolved;
      }
    } catch (e) {
      debugPrint('Supabase departments lookup failed: $e');
    }

    _noticeDepartmentsCache = (
      cachedAt: DateTime.now(),
      data: List<DepartmentOption>.unmodifiable(departmentOptions),
    );
    return departmentOptions;
  }

  /// Check if following department
  Future<bool> isFollowingDepartment(
    String departmentId,
    String userEmail, {
    String? collegeId,
  }) async {
    final normalizedDepartmentId = normalizeDepartmentCode(departmentId);
    if (normalizedDepartmentId.isEmpty) return false;
    final followedIds = await getFollowedDepartmentIds(
      collegeId ?? '',
      userEmail,
    );
    return followedIds.contains(normalizedDepartmentId);
  }

  Future<Map<String, int>> getDepartmentFollowerCounts(
    List<String> departmentIds,
    String collegeId,
  ) async {
    final normalizedDepartmentIds = departmentIds
        .map(normalizeDepartmentCode)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedDepartmentIds.isEmpty) {
      return const <String, int>{};
    }

    final normalizedCollegeId = await _resolveDepartmentCollegeScope(collegeId);
    try {
      final backendCounts = await _api.getDepartmentFollowerCounts(
        normalizedDepartmentIds,
        collegeId: normalizedCollegeId.isNotEmpty ? normalizedCollegeId : null,
      );
      if (backendCounts.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
        return Map<String, int>.fromEntries(
          normalizedDepartmentIds.map(
            (id) =>
                MapEntry(id, backendCounts[normalizeDepartmentCode(id)] ?? 0),
          ),
        );
      }
    } catch (e) {
      debugPrint(
        'Backend department follower counts lookup failed, falling back to Supabase: $e',
      );
      if (!_hasConfiguredSupabaseAnonKey) {
        return Map<String, int>.fromEntries(
          normalizedDepartmentIds.map((id) => MapEntry(id, 0)),
        );
      }
    }

    final counts = <String, int>{
      for (final departmentId in normalizedDepartmentIds) departmentId: 0,
    };

    try {
      var uniqueQuery = _client
          .from('department_followers')
          .select(
            'department_id, user_id, follower_id, user_email, follower_email',
          )
          .inFilter('department_id', normalizedDepartmentIds);
      if (normalizedCollegeId.isNotEmpty) {
        uniqueQuery = uniqueQuery.eq('college_id', normalizedCollegeId);
      }
      final uniqueResponse = await uniqueQuery;
      final uniqueFollowerKeysByDepartment = <String, Set<String>>{
        for (final departmentId in normalizedDepartmentIds)
          departmentId: <String>{},
      };
      for (final row in (uniqueResponse as List).whereType<Map>()) {
        final map = Map<String, dynamic>.from(row);
        final departmentId = normalizeDepartmentCode(
          map['department_id']?.toString(),
        );
        if (!uniqueFollowerKeysByDepartment.containsKey(departmentId)) continue;
        final keyCandidates = <String>[
          map['user_id']?.toString().trim() ?? '',
          map['follower_id']?.toString().trim() ?? '',
          _normalizeEmail(map['user_email']?.toString()),
          _normalizeEmail(map['follower_email']?.toString()),
        ];
        final key = keyCandidates.firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );
        if (key.isNotEmpty) {
          uniqueFollowerKeysByDepartment[departmentId]!.add(key);
        }
      }
      for (final entry in uniqueFollowerKeysByDepartment.entries) {
        counts[entry.key] = entry.value.length;
      }
    } catch (e) {
      if (_isMissingColumnError(e, 'college_id')) {
        try {
          final uniqueResponse = await _client
              .from('department_followers')
              .select(
                'department_id, user_id, follower_id, user_email, follower_email',
              )
              .inFilter('department_id', normalizedDepartmentIds);
          final uniqueFollowerKeysByDepartment = <String, Set<String>>{
            for (final departmentId in normalizedDepartmentIds)
              departmentId: <String>{},
          };
          for (final row in (uniqueResponse as List).whereType<Map>()) {
            final map = Map<String, dynamic>.from(row);
            final departmentId = normalizeDepartmentCode(
              map['department_id']?.toString(),
            );
            if (!uniqueFollowerKeysByDepartment.containsKey(departmentId)) {
              continue;
            }
            final keyCandidates = <String>[
              map['user_id']?.toString().trim() ?? '',
              map['follower_id']?.toString().trim() ?? '',
              _normalizeEmail(map['user_email']?.toString()),
              _normalizeEmail(map['follower_email']?.toString()),
            ];
            final key = keyCandidates.firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => '',
            );
            if (key.isNotEmpty) {
              uniqueFollowerKeysByDepartment[departmentId]!.add(key);
            }
          }
          for (final entry in uniqueFollowerKeysByDepartment.entries) {
            counts[entry.key] = entry.value.length;
          }
        } catch (fallbackError) {
          debugPrint(
            'Error getting department follower counts: $e | $fallbackError',
          );
        }
      } else {
        debugPrint('Error getting department follower counts: $e');
      }
    }

    return counts;
  }

  /// Get department follower count
  Future<int> getDepartmentFollowerCount(
    String departmentId,
    String collegeId,
  ) async {
    final normalizedDepartmentId = normalizeDepartmentCode(departmentId);
    if (normalizedDepartmentId.isEmpty) return 0;
    final counts = await getDepartmentFollowerCounts(<String>[
      normalizedDepartmentId,
    ], collegeId);
    return counts[normalizedDepartmentId] ?? 0;
  }

  /// Get followed department IDs
  Future<List<String>> getFollowedDepartmentIds(
    String collegeId,
    String userEmail,
  ) async {
    final normalizedCollegeId = await _resolveDepartmentCollegeScope(collegeId);
    try {
      // Prefer the backend-owned route because writes already go through the
      // backend, while direct client reads can be blocked by RLS or schema drift.
      final backendIds = await _api.getFollowedDepartments(
        collegeId: normalizedCollegeId.isNotEmpty ? normalizedCollegeId : null,
      );
      return backendIds
          .map(normalizeDepartmentCode)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
    } catch (e) {
      debugPrint(
        'Backend followed departments lookup failed, falling back to Supabase: $e',
      );
    }

    final normalizedEmail = await _resolveDepartmentFollowEmail(
      claimedEmail: userEmail,
    );
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
            .select('department_id');
        query = column.contains('email')
            ? query.ilike(column, value)
            : query.eq(column, value);
        if (useCollegeFilter && normalizedCollegeId.isNotEmpty) {
          query = query.ilike('college_id', normalizedCollegeId);
        }
        final response = await query;
        final fetchedIds = (response as List)
            .map((e) => normalizeDepartmentCode(e['department_id']?.toString()))
            .where((id) => id.isNotEmpty)
            .toList();
        finalSet.addAll(fetchedIds);
        if (fetchedIds.isNotEmpty) {
          break; // Stop falling back only when this schema variant has rows.
        }
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
      if (normalizedEmail.isEmpty) {
        return finalSet.toList();
      }
      final userRes = await _client
          .from('users_safe')
          .select('followed_departments')
          .ilike('email', normalizedEmail)
          .maybeSingle();
      if (userRes != null) {
        final profileFollows =
            userRes['followed_departments'] as List<dynamic>? ?? [];
        for (final id in profileFollows) {
          final normalizedId = normalizeDepartmentCode(id?.toString());
          if (normalizedId.isNotEmpty) {
            finalSet.add(normalizedId);
          }
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
      _requireCurrentSessionEmail(
        claimedEmail: userEmail,
        action: 'save_notice',
      );
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
      _requireCurrentSessionEmail(
        claimedEmail: userEmail,
        action: 'unsave_notice',
      );
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
      _requireCurrentSessionEmail(
        claimedEmail: userEmail,
        action: 'is_notice_saved',
      );
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
    String collegeId, {
    String? filter,
  }) async {
    Future<Set<String>> fetchJoinedRoomIds() async {
      try {
        if (_hasConfiguredSupabaseAnonKey) {
          final joined = await _client
              .from('room_members')
              .select('room_id')
              .eq('user_email', userEmail);
          return (joined as List)
              .map((entry) => entry['room_id']?.toString() ?? '')
              .where((value) => value.isNotEmpty)
              .toSet();
        }
      } catch (e) {
        debugPrint('Direct joined-room lookup failed: $e');
      }

      try {
        return (await getUserRoomIds(userEmail)).toSet();
      } catch (e) {
        debugPrint('Backend joined-room lookup failed: $e');
        return <String>{};
      }
    }

    List<Map<String, dynamic>> filterActiveRooms(
      List<Map<String, dynamic>> rooms,
    ) {
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
    }

    List<Map<String, dynamic>> filterMembershipState(
      List<Map<String, dynamic>> rooms,
      Set<String> joinedRoomIds,
    ) {
      final normalizedFilter = filter?.trim().toLowerCase();
      if (normalizedFilter == 'joined') {
        return rooms
            .where((room) => joinedRoomIds.contains(room['id']?.toString()))
            .toList();
      }
      if (normalizedFilter == 'discover') {
        return rooms.where((room) {
          final roomId = room['id']?.toString();
          final isPrivate = _normalizeBool(
            room['is_private'] ?? room['isPrivate'],
          );
          return !joinedRoomIds.contains(roomId) && !isPrivate;
        }).toList();
      }
      return rooms;
    }

    try {
      if (filter != null && filter.trim().isNotEmpty) {
        final joinedRoomIds = await fetchJoinedRoomIds();
        final backendRooms = await _api.listChatRooms(
          collegeId: collegeId,
          filter: filter.trim(),
        );
        return filterMembershipState(
          filterActiveRooms(
            backendRooms
                .map((entry) => _normalizeChatRoomRecord(entry))
                .toList(),
          ),
          joinedRoomIds,
        );
      }

      if (!_hasConfiguredSupabaseAnonKey) {
        debugPrint(
          'Supabase anon key missing; using backend room discovery directly.',
        );
        final backendRooms = await _api.listChatRooms(collegeId: collegeId);
        return filterActiveRooms(
          backendRooms.map((entry) => _normalizeChatRoomRecord(entry)).toList(),
        );
      }

      final response = await _client
          .from('chat_rooms')
          .select('*, member_count:room_members(count)')
          .eq('college_id', collegeId)
          .order('created_at', ascending: false);

      final rooms = (response as List)
          .map((e) => _normalizeChatRoomRecord(e))
          .toList();
      return filterActiveRooms(rooms);
    } catch (e) {
      debugPrint('Error fetching chat rooms via Supabase: $e');
      try {
        final backendRooms = await _api.listChatRooms(collegeId: collegeId);
        final normalized = backendRooms
            .map((entry) => _normalizeChatRoomRecord(entry))
            .toList();
        if (normalized.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
          final joinedRoomIds = await fetchJoinedRoomIds();
          return filterMembershipState(
            filterActiveRooms(normalized),
            joinedRoomIds,
          );
        }
      } catch (backendError) {
        debugPrint('Backend chat room fallback failed: $backendError');
      }
      if (_hasConfiguredSupabaseAnonKey) {
        try {
          final joinedRoomIds = await fetchJoinedRoomIds();
          final response = await _client
              .from('chat_rooms')
              .select('*, member_count:room_members(count)')
              .eq('college_id', collegeId)
              .order('created_at', ascending: false);
          final normalized = (response as List)
              .map((entry) => _normalizeChatRoomRecord(entry))
              .toList();
          return filterMembershipState(
            filterActiveRooms(normalized),
            joinedRoomIds,
          );
        } catch (directError) {
          debugPrint('Direct chat room fallback failed: $directError');
        }
      }
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
    String? department,
    bool includeHidden = false,
    int limit = 80,
    int offset = 0,
  }) async {
    List<Map<String, dynamic>> normalizeBackendRows(
      List<Map<String, dynamic>> rawRows,
    ) {
      final filtered = includeHidden
          ? List<Map<String, dynamic>>.from(rawRows)
          : rawRows.where((notice) => notice['is_active'] != false).toList();
      filtered.sort((a, b) {
        final aCreated = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final bCreated = DateTime.tryParse(b['created_at']?.toString() ?? '');
        if (aCreated == null && bCreated == null) return 0;
        if (aCreated == null) return 1;
        if (bCreated == null) return -1;
        return bCreated.compareTo(aCreated);
      });
      return filtered;
    }

    try {
      final safeLimit = limit < 1 ? 1 : (limit > 500 ? 500 : limit);
      final safeOffset = offset < 0 ? 0 : offset;
      final normalizedDepartment = normalizeDepartmentCode(department);
      if (!_hasConfiguredSupabaseAnonKey) {
        final backendRows = normalizeBackendRows(
          await _api.getNotices(
            collegeId,
            department: normalizedDepartment.isEmpty
                ? null
                : normalizedDepartment,
          ),
        );
        if (safeOffset >= backendRows.length) {
          return const <Map<String, dynamic>>[];
        }
        final end = (safeOffset + safeLimit).clamp(0, backendRows.length);
        return backendRows.sublist(safeOffset, end);
      }
      var query = _client.from('notices').select().eq('college_id', collegeId);
      if (normalizedDepartment.isNotEmpty) {
        query = query.eq('department', normalizedDepartment);
      }
      if (!includeHidden) {
        query = query.eq('is_active', true);
      }
      final response = await query
          .order('created_at', ascending: false)
          .range(safeOffset, safeOffset + safeLimit - 1);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting notices: $e');
      try {
        final safeLimit = limit < 1 ? 1 : (limit > 500 ? 500 : limit);
        final safeOffset = offset < 0 ? 0 : offset;
        final normalizedDepartment = normalizeDepartmentCode(department);
        final backendRows = normalizeBackendRows(
          await _api.getNotices(
            collegeId,
            department: normalizedDepartment.isEmpty
                ? null
                : normalizedDepartment,
          ),
        );
        if (safeOffset >= backendRows.length) {
          return const <Map<String, dynamic>>[];
        }
        final end = (safeOffset + safeLimit).clamp(0, backendRows.length);
        final sliced = backendRows.sublist(safeOffset, end);
        if (sliced.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
          return sliced;
        }
      } catch (backendError) {
        debugPrint('Backend notices fallback failed: $backendError');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getNoticeComments(String noticeId) async {
    try {
      // Fetch flat comments
      final rawComments = await _api.getNoticeComments(noticeId);
      final usersByEmail = await _fetchUsersByEmails(
        rawComments.map((comment) => comment['user_email']?.toString() ?? ''),
      );

      for (final comment in rawComments) {
        _applyProfileToRecord(
          record: comment,
          emailKey: 'user_email',
          outputNameKey: 'user_name',
          outputPhotoKey: 'user_photo_url',
          usersByEmail: usersByEmail,
          existingNameKeys: const ['display_name', 'author_name', 'name'],
          existingPhotoKeys: const [
            'author_photo_url',
            'profile_photo_url',
            'photo_url',
            'avatar_url',
          ],
        );

        final resolvedPhoto = _firstNonEmptyValue(comment, const [
          'user_photo_url',
          'author_photo_url',
          'profile_photo_url',
          'photo_url',
          'avatar_url',
        ]);
        if (resolvedPhoto.isNotEmpty) {
          comment['user_photo_url'] = resolvedPhoto;
          comment['author_photo_url'] = resolvedPhoto;
          comment['profile_photo_url'] = resolvedPhoto;
        }
      }

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
    final normalizedEmail = _requireCurrentSessionEmail(
      claimedEmail: userEmail,
      action: 'get_user_room_ids',
    );
    if (!_hasConfiguredSupabaseAnonKey) {
      try {
        return await _api.getJoinedRoomIds();
      } catch (e) {
        debugPrint('Backend joined rooms lookup failed: $e');
        return [];
      }
    }

    try {
      final res = await _client
          .from('room_members')
          .select('room_id')
          .eq('user_email', normalizedEmail);
      return (res as List).map((e) => e['room_id'] as String).toList();
    } catch (e) {
      debugPrint('Error getting joined rooms: $e');
      try {
        final backendIds = await _api.getJoinedRoomIds();
        if (backendIds.isNotEmpty || !_hasConfiguredSupabaseAnonKey) {
          return backendIds;
        }
      } catch (backendError) {
        debugPrint('Backend joined rooms fallback failed: $backendError');
      }
      return [];
    }
  }

  /// Toggle bookmark for a resource - returns new bookmark state
  Future<bool> toggleBookmark(String userEmail, String resourceId) async {
    final normalizedEmail = _requireCurrentSessionEmail(
      claimedEmail: userEmail,
      action: 'toggle_bookmark',
    );
    try {
      _pruneExpiredRateLimits();
      final ctx = _ctx;
      if (ctx == null) throw Exception('Security context not initialized');

      final cacheKey = _resourceStateKey(
        resourceId,
        userEmail: normalizedEmail,
      );
      final isMarked =
          _bookmarkStateCache[cacheKey] ?? await _api.checkBookmark(resourceId);
      if (!ctx.mounted) {
        throw Exception('Security context is no longer active');
      }
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
    final normalizedEmail = _requireCurrentSessionEmail(
      claimedEmail: userEmail,
      action: 'is_bookmarked',
    );
    _pruneExpiredRateLimits();
    final cacheKey = _resourceStateKey(resourceId, userEmail: normalizedEmail);
    final cached = _bookmarkStateCache[cacheKey];
    if (cached != null) return cached;

    final cooldownUntil = _bookmarkRateLimitUntil[cacheKey];
    if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil)) {
      return false;
    }

    final inFlight = _bookmarkStateInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final future = () async {
      try {
        final value = await _api.checkBookmark(resourceId);
        _bookmarkStateCache[cacheKey] = value;
        _bookmarkRateLimitUntil.remove(cacheKey);
        return value;
      } catch (e) {
        if (_isRateLimitError(e)) {
          _bookmarkRateLimitUntil[cacheKey] = DateTime.now().add(
            const Duration(seconds: 20),
          );
        }
        debugPrint('Error checking bookmark: $e');
        return false;
      } finally {
        _bookmarkStateInFlight.remove(cacheKey);
      }
    }();

    _bookmarkStateInFlight[cacheKey] = future;
    return future;
  }

  bool? getCachedBookmarkState(String userEmail, String resourceId) {
    final normalizedEmail = _currentSessionEmail();
    if (normalizedEmail.isEmpty) return null;
    final claimedEmail = _normalizeEmail(userEmail);
    if (claimedEmail.isNotEmpty && claimedEmail != normalizedEmail) {
      return null;
    }
    final cacheKey = _resourceStateKey(resourceId, userEmail: normalizedEmail);
    return _bookmarkStateCache[cacheKey];
  }

  Future<void> prefetchBookmarksForResources({
    required String userEmail,
    required Iterable<String> resourceIds,
  }) async {
    final normalizedEmail = _requireCurrentSessionEmail(
      claimedEmail: userEmail,
      action: 'prefetch_bookmarks',
    );

    final ids = resourceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
      final response = await _api.getBookmarks();
      final raw =
          (response['bookmarks'] ?? response['items']) as List? ?? const [];
      final bookmarkedIds = <String>{};

      for (final item in raw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final rawId =
            row['itemId'] ??
            row['item_id'] ??
            row['resourceId'] ??
            row['resource_id'] ??
            row['id'];
        final itemType = (row['type'] ?? row['itemType'] ?? row['item_type'])
            ?.toString()
            .trim()
            .toLowerCase();
        if (itemType != null && itemType.isNotEmpty && itemType != 'resource') {
          continue;
        }
        final id = rawId?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        bookmarkedIds.add(id);
      }

      for (final id in ids) {
        final cacheKey = _resourceStateKey(id, userEmail: normalizedEmail);
        _bookmarkStateCache[cacheKey] = bookmarkedIds.contains(id);
      }
    } catch (e) {
      debugPrint('Error prefetching resource bookmark states: $e');
    }
  }

  // ============ NOTICES ============

  Future<Map<String, dynamic>?> getNotice(
    String id, {
    String? collegeId,
  }) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return null;

    try {
      final response = await _client
          .from('notices')
          .select()
          .eq('id', normalizedId)
          .maybeSingle();
      if (response != null) {
        return response;
      }
    } catch (e) {
      debugPrint('Error fetching notice: $e');
    }

    try {
      return await _api.getNoticeById(normalizedId, collegeId: collegeId);
    } catch (e) {
      debugPrint('Backend notice lookup failed: $e');
      return null;
    }
  }

  Future<DepartmentAccount?> getDepartmentProfile(String departmentId) async {
    try {
      final catalogAccount = departmentAccountFromCode(departmentId);
      if (catalogAccount.id != 'unknown') {
        return catalogAccount;
      }

      final response = await _client
          .from('users_safe')
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
  Future<List<Resource>> _getUserResourcesViaBackend({
    required String userEmail,
    required bool approvedOnly,
    required int limit,
    required int offset,
  }) async {
    final normalizedEmail = _normalizeEmail(userEmail);
    final isCurrentUser = normalizedEmail == _currentSessionEmail();
    final payload = isCurrentUser
        ? await _api.getMyResources()
        : await _api.getPublicUserResources(
            email: normalizedEmail,
            approvedOnly: approvedOnly,
            limit: limit,
            offset: offset,
          );
    final rawRows = payload['resources'];
    if (rawRows is! List) return const <Resource>[];

    final resources =
        rawRows
            .whereType<Map>()
            .map((row) => Resource.fromJson(Map<String, dynamic>.from(row)))
            .where((resource) => !approvedOnly || resource.isApprovedStatus)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (!isCurrentUser) {
      return resources;
    }

    final safeOffset = offset < 0 ? 0 : offset;
    if (safeOffset >= resources.length) return const <Resource>[];

    final end = (safeOffset + limit).clamp(0, resources.length);
    return resources.sublist(safeOffset, end);
  }

  Future<List<Resource>> getUserResources(
    String userEmail, {
    bool approvedOnly = true,
    int limit = 50,
    int offset = 0,
  }) async {
    final rawEmail = userEmail.trim();
    final normalizedEmail = _normalizeEmail(userEmail);
    if (normalizedEmail.isEmpty) return [];
    if (limit <= 0) return [];
    try {
      return await _getUserResourcesViaBackend(
        userEmail: normalizedEmail,
        approvedOnly: approvedOnly,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      debugPrint('Backend user resources lookup failed: $e');
      if (!_hasConfiguredSupabaseAnonKey) {
        return const <Resource>[];
      }
    }

    try {
      var query = _client
          .from('resources')
          .select()
          .eq('uploaded_by_email', rawEmail);

      if (approvedOnly) {
        query = query.eq('status', 'approved');
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final rows = (response as List)
          .map((item) => Resource.fromJson(item as Map<String, dynamic>))
          .toList();
      if (rows.isNotEmpty) {
        return rows;
      }
    } catch (e) {
      debugPrint('Exact-email user resource query failed, trying fallback: $e');
    }

    try {
      final fetchWindow = (limit * 8).clamp(80, 240).toInt();
      var query = _client.from('resources').select();
      if (approvedOnly) {
        query = query.eq('status', 'approved');
      }

      final raw = await query
          .order('created_at', ascending: false)
          .range(0, offset + fetchWindow - 1);

      return (raw as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where(
            (row) =>
                normalizedEmail ==
                _normalizeEmail(row['uploaded_by_email']?.toString()),
          )
          .skip(offset)
          .take(limit)
          .map(Resource.fromJson)
          .toList();
    } catch (fallbackError) {
      debugPrint('Error fetching user resources: $fallbackError');
      return [];
    }
  }

  int _normalizeCount(dynamic countVal) {
    if (countVal is List && countVal.isNotEmpty) {
      final first = countVal[0];
      if (first is Map && first.containsKey('count')) {
        return _normalizeCount(first['count']);
      }
      // Many endpoints return full item arrays instead of an explicit count.
      return countVal.length;
    }
    if (countVal is Map && countVal.containsKey('count')) {
      return _normalizeCount(countVal['count']);
    }
    if (countVal is int) return countVal;
    if (countVal is num) return countVal.toInt();
    if (countVal is String) return int.tryParse(countVal.trim()) ?? 0;
    return 0;
  }

  Map<String, dynamic> _normalizeChatRoomRecord(dynamic raw) {
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final normalized = Map<String, dynamic>.from(data);

    normalized['id'] = _normalizeString(data['id']);
    normalized['name'] = _normalizeString(data['name'], fallback: 'Untitled');
    normalized['description'] = _normalizeString(data['description']);
    normalized['member_count'] = _normalizeCount(data['member_count']);
    normalized['is_private'] = _normalizeBool(
      data['is_private'] ?? data['isPrivate'],
    );
    normalized['is_active'] = _normalizeBool(
      data['is_active'] ?? data['isActive'],
      fallback: true,
    );
    normalized['created_at'] = _normalizeString(
      data['created_at'] ?? data['createdAt'],
    );
    normalized['updated_at'] = _normalizeString(
      data['updated_at'] ?? data['updatedAt'],
      fallback: normalized['created_at']?.toString() ?? '',
    );
    normalized['expiry_date'] = _normalizeString(
      data['expiry_date'] ?? data['expiryDate'],
    );
    normalized['tags'] = _normalizeStringList(data['tags']);
    return normalized;
  }

  String _normalizeString(dynamic value, {String fallback = ''}) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  bool _normalizeBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return fallback;
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'y';
  }

  List<String> _normalizeStringList(dynamic value) {
    if (value is List) {
      return value
          .map((entry) => entry?.toString().trim() ?? '')
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    final normalized = value?.toString().trim() ?? '';
    if (normalized.isEmpty) return const <String>[];
    if (normalized.contains(',')) {
      return normalized
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    return <String>[normalized];
  }
}
