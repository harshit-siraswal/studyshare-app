const String appRoleReadOnly = 'READ_ONLY';
const String appRoleAdmin = 'ADMIN';
const String appRoleModerator = 'MODERATOR';
const String appRoleCollegeUser = 'COLLEGE_USER';
const String appRoleTeacher = 'TEACHER';

const List<String> _capabilityKeys = <String>[
  'upload_syllabus',
  'upload_resource',
  'upload_notice',
  'ban_user',
  'unban_user',
  'push_college',
  'push_user',
  'push_global',
  'manage_reports',
  'manage_ai_prompts',
  'all_colleges',
];

const Map<String, bool> _defaultAdminCapabilities = <String, bool>{
  'upload_syllabus': true,
  'upload_resource': true,
  'upload_notice': true,
  'ban_user': true,
  'unban_user': true,
  'push_college': true,
  'push_user': true,
  'push_global': false,
  'manage_reports': false,
  'manage_ai_prompts': false,
  'all_colleges': false,
};

bool _isTruthy(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'y' ||
        normalized == 'on';
  }
  return false;
}

Map<String, dynamic> _asStringKeyedMap(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    return Map<String, dynamic>.from(raw);
  }
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

Map<String, bool> _extractExplicitCapabilities(dynamic raw) {
  if (raw is Iterable && raw is! String) {
    return <String, bool>{
      for (final value in raw)
        if (value?.toString().trim().isNotEmpty ?? false)
          value.toString().trim().toLowerCase(): true,
    };
  }

  final rawMap = _asStringKeyedMap(raw);
  if (rawMap.isEmpty) return const <String, bool>{};

  return <String, bool>{
    for (final entry in rawMap.entries)
      entry.key.trim().toLowerCase(): _isTruthy(entry.value),
  };
}

bool _hasNonEmptyText(dynamic value) {
  return value?.toString().trim().isNotEmpty ?? false;
}

String normalizeProfileRoleValue(String? role) {
  final raw = role?.trim().toUpperCase() ?? '';
  switch (raw) {
    case 'ADMIN':
      return appRoleAdmin;
    case 'MODERATOR':
      return appRoleModerator;
    case 'COLLEGE_USER':
      return appRoleCollegeUser;
    case 'TEACHER':
      return appRoleTeacher;
    case 'READ_ONLY':
      return appRoleReadOnly;
    case 'STUDENT':
      return appRoleCollegeUser;
    default:
      return appRoleReadOnly;
  }
}

bool hasAdminContext(Map<String, dynamic> profile) {
  final role = normalizeProfileRoleValue(profile['role']?.toString());
  final adminRole = normalizeProfileRoleValue(
    profile['admin_role']?.toString(),
  );
  return _extractExplicitCapabilities(
        profile['admin_capabilities'],
      ).isNotEmpty ||
      _isTruthy(profile['scope_all_colleges']) ||
      _hasNonEmptyText(profile['admin_college_id']) ||
      role == appRoleAdmin ||
      adminRole == appRoleAdmin;
}

Map<String, bool> extractAdminCapabilities(Map<String, dynamic> profile) {
  final explicit = _extractExplicitCapabilities(profile['admin_capabilities']);
  final role = normalizeProfileRoleValue(profile['role']?.toString());
  final adminRole = normalizeProfileRoleValue(
    profile['admin_role']?.toString(),
  );
  final isSuperAdmin =
      profile['role']?.toString().trim().toLowerCase() == 'super_admin' ||
      profile['admin_role']?.toString().trim().toLowerCase() == 'super_admin';
  final getsDefaultAdminCapabilities =
      isSuperAdmin || role == appRoleAdmin || adminRole == appRoleAdmin;

  if (!getsDefaultAdminCapabilities && explicit.isEmpty) {
    if (_isTruthy(profile['scope_all_colleges'])) {
      return const <String, bool>{'all_colleges': true};
    }
    return const <String, bool>{};
  }

  final base = isSuperAdmin
      ? <String, bool>{for (final key in _capabilityKeys) key: true}
      : getsDefaultAdminCapabilities
      ? <String, bool>{..._defaultAdminCapabilities}
      : <String, bool>{};

  for (final key in _capabilityKeys) {
    if (explicit.containsKey(key)) {
      base[key] = explicit[key] == true;
    }
  }

  if (_isTruthy(profile['scope_all_colleges'])) {
    base['all_colleges'] = true;
  }

  return base;
}

bool hasAdminCapability(Map<String, dynamic> profile, String capability) {
  final normalizedCapability = capability.trim().toLowerCase();
  if (normalizedCapability.isEmpty) return false;
  return extractAdminCapabilities(profile)[normalizedCapability] == true;
}

bool hasAnyAdminCapability(
  Map<String, dynamic> profile, {
  Iterable<String>? capabilities,
}) {
  final resolved = extractAdminCapabilities(profile);
  if (resolved.isEmpty) return false;

  if (capabilities == null) {
    return resolved.values.any((value) => value);
  }

  for (final capability in capabilities) {
    if (resolved[capability.trim().toLowerCase()] == true) {
      return true;
    }
  }
  return false;
}

String resolveEffectiveProfileRole(Map<String, dynamic> profile) {
  final normalizedRole = normalizeProfileRoleValue(profile['role']?.toString());
  final hasCollegeContext =
      (profile['college_id']?.toString().trim().isNotEmpty ?? false) ||
      (profile['college']?.toString().trim().isNotEmpty ?? false);
  final hasElevatedAccess =
      hasAdminContext(profile) &&
      (hasAnyAdminCapability(profile) ||
          _isTruthy(profile['scope_all_colleges']) ||
          (profile['admin_college_id']?.toString().trim().isNotEmpty ?? false));

  switch (normalizedRole) {
    case appRoleAdmin:
      return appRoleAdmin;
    case appRoleModerator:
      return hasElevatedAccess ? appRoleTeacher : appRoleModerator;
    case appRoleTeacher:
      return appRoleTeacher;
    case appRoleCollegeUser:
      return hasElevatedAccess ? appRoleTeacher : appRoleCollegeUser;
    case appRoleReadOnly:
      if (hasElevatedAccess) return appRoleTeacher;
      return hasCollegeContext ? appRoleCollegeUser : appRoleReadOnly;
    default:
      return hasElevatedAccess ? appRoleTeacher : appRoleCollegeUser;
  }
}

bool isTeacherOrAdminProfile(Map<String, dynamic> profile) {
  final resolvedRole = resolveEffectiveProfileRole(profile);
  return resolvedRole == appRoleTeacher || resolvedRole == appRoleAdmin;
}

bool canManageAdminResourcesProfile(Map<String, dynamic> profile) {
  return hasAdminCapability(profile, 'upload_resource') ||
      isTeacherOrAdminProfile(profile);
}

bool canBanUsersProfile(Map<String, dynamic> profile) {
  return hasAdminCapability(profile, 'ban_user');
}

bool canUploadSyllabusProfile(Map<String, dynamic> profile) {
  return hasAdminCapability(profile, 'upload_syllabus') ||
      hasAdminCapability(profile, 'upload_resource');
}
