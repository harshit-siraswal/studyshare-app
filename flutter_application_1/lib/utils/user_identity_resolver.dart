class ResolvedUserType {
  final String type;
  final String? role;
  final String? department;
  final List<String> capabilities;
  final String? collegeName;
  final String? collegeId;

  const ResolvedUserType({
    required this.type,
    this.role,
    this.department,
    this.capabilities = const <String>[],
    this.collegeName,
    this.collegeId,
  });

  static const ResolvedUserType unauthenticated = ResolvedUserType(
    type: 'unauthenticated',
  );

  bool get isAdmin => type == 'admin';
  bool get isCollegeUser => type == 'college_user';

  bool get canUploadResources => isAdmin || isCollegeUser;

  bool get canPostNotices {
    if (isAdmin) return true;
    final normalizedRole = role?.trim().toLowerCase() ?? '';
    return normalizedRole == 'teacher' || normalizedRole == 'moderator';
  }
}

List<String> _extractCapabilities(dynamic raw) {
  if (raw is List) {
    return raw
        .map((entry) => entry?.toString().trim().toLowerCase() ?? '')
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  if (raw is Map) {
    final capabilities = <String>[];
    raw.forEach((key, value) {
      final enabled = value == true ||
          value == 1 ||
          (value is String &&
              (value.trim().toLowerCase() == 'true' ||
                  value.trim() == '1'));
      if (!enabled) return;
      final capability = key.toString().trim().toLowerCase();
      if (capability.isNotEmpty) {
        capabilities.add(capability);
      }
    });
    return capabilities.toSet().toList(growable: false);
  }

  return const <String>[];
}

ResolvedUserType resolveUserType(Map<String, dynamic>? identity) {
  if (identity == null || identity.isEmpty) {
    return ResolvedUserType.unauthenticated;
  }

  final adminRole = identity['admin_role']?.toString().trim() ?? '';
  final adminDepartment =
      identity['admin_department']?.toString().trim().isNotEmpty == true
      ? identity['admin_department'].toString().trim()
      : null;
  final adminCapabilities = _extractCapabilities(identity['admin_capabilities']);

  if (adminRole.isNotEmpty || adminCapabilities.isNotEmpty) {
    return ResolvedUserType(
      type: 'admin',
      role: adminRole.isEmpty ? null : adminRole,
      department: adminDepartment,
      capabilities: adminCapabilities,
      collegeName: identity['college_name']?.toString(),
      collegeId: identity['college_id']?.toString(),
    );
  }

  final userRole =
      (identity['user_role'] ?? identity['role'])?.toString().trim() ?? '';
  final normalizedRole = userRole.toLowerCase();
  final collegeId = identity['college_id']?.toString().trim() ?? '';

  final hasCollegeContext = collegeId.isNotEmpty;
  final isCollegeRole =
      normalizedRole == 'full' ||
      normalizedRole == 'college_user' ||
      normalizedRole == 'teacher' ||
      normalizedRole == 'moderator' ||
      normalizedRole == 'admin';

  if (hasCollegeContext && isCollegeRole) {
    return ResolvedUserType(
      type: 'college_user',
      role: userRole.isEmpty ? null : userRole,
      collegeName: identity['college_name']?.toString(),
      collegeId: collegeId,
    );
  }

  return ResolvedUserType(type: 'readonly', role: userRole.isEmpty ? null : userRole);
}
