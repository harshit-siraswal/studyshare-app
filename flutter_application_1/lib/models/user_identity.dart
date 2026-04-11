import 'user.dart';

class UserIdentity {
  final String id;
  final String email;
  final String? displayName;
  final String? profilePhotoUrl;
  final String userRole;
  final String? collegeId;
  final String? branch;
  final String? semester;
  final String? username;
  final String? subscriptionTier;
  final DateTime? premiumUntil;
  final int followersCount;
  final int followingCount;
  final String? collegeName;
  final String? collegeDomain;
  final String? collegeLogo;
  final String? adminRole;
  final String? adminDepartment;
  final List<String> adminCapabilities;

  const UserIdentity({
    required this.id,
    required this.email,
    required this.userRole,
    this.displayName,
    this.profilePhotoUrl,
    this.collegeId,
    this.branch,
    this.semester,
    this.username,
    this.subscriptionTier,
    this.premiumUntil,
    this.followersCount = 0,
    this.followingCount = 0,
    this.collegeName,
    this.collegeDomain,
    this.collegeLogo,
    this.adminRole,
    this.adminDepartment,
    this.adminCapabilities = const <String>[],
  });

  static String _normalizeRole(String? rawRole) {
    final role = rawRole?.trim().toLowerCase() ?? '';
    switch (role) {
      case 'admin':
        return AppRoles.admin;
      case 'moderator':
        return AppRoles.moderator;
      case 'teacher':
        return AppRoles.teacher;
      case 'college_user':
      case 'full':
      case 'student':
        return AppRoles.collegeUser;
      case 'readonly':
      case 'read_only':
      case 'read-only':
        return AppRoles.readOnly;
      default:
        return role.isEmpty ? AppRoles.readOnly : role.toUpperCase();
    }
  }

  static int _toSafeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<String> _extractCapabilities(dynamic raw) {
    if (raw is List) {
      return raw
          .map((value) => value?.toString().trim().toLowerCase() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }

    if (raw is Map) {
      final capabilities = <String>[];
      raw.forEach((key, value) {
        final enabled =
            value == true || value == 1 || value?.toString().toLowerCase() == 'true';
        if (!enabled) return;
        final normalizedKey = key.toString().trim().toLowerCase();
        if (normalizedKey.isNotEmpty) {
          capabilities.add(normalizedKey);
        }
      });
      return capabilities.toSet().toList(growable: false);
    }

    return const <String>[];
  }

  factory UserIdentity.fromJson(Map<String, dynamic> json) {
    final normalizedEmail =
        json['email']?.toString().trim().toLowerCase() ?? '';

    return UserIdentity(
      id: json['id']?.toString().trim() ?? '',
      email: normalizedEmail,
      displayName: json['display_name']?.toString(),
      profilePhotoUrl: json['profile_photo_url']?.toString(),
      userRole: _normalizeRole(
        (json['user_role'] ?? json['role'])?.toString(),
      ),
      collegeId: json['college_id']?.toString(),
      branch: json['branch']?.toString(),
      semester: json['semester']?.toString(),
      username: json['username']?.toString(),
      subscriptionTier: json['subscription_tier']?.toString(),
      premiumUntil: DateTime.tryParse(
        (json['premium_until'] ?? json['subscription_end_date'] ?? '')
            .toString(),
      ),
      followersCount: _toSafeInt(json['followers_count']),
      followingCount: _toSafeInt(json['following_count']),
      collegeName: json['college_name']?.toString(),
      collegeDomain: json['college_domain']?.toString(),
      collegeLogo: json['college_logo']?.toString(),
      adminRole: json['admin_role']?.toString(),
      adminDepartment: json['admin_department']?.toString(),
      adminCapabilities: _extractCapabilities(json['admin_capabilities']),
    );
  }

  bool get isAdmin =>
      (adminRole?.trim().isNotEmpty ?? false) || adminCapabilities.isNotEmpty;

  bool get canUploadResources =>
      isAdmin ||
      userRole == AppRoles.collegeUser ||
      userRole == AppRoles.teacher ||
      userRole == AppRoles.moderator ||
      userRole == AppRoles.admin;

  bool get canPostNotices {
    if (isAdmin) return true;
    return userRole == AppRoles.teacher ||
        userRole == AppRoles.moderator ||
        userRole == AppRoles.admin;
  }

  bool equivalentTo(UserIdentity other) {
    if (id != other.id) return false;
    if (email != other.email) return false;
    if (userRole != other.userRole) return false;
    if ((adminRole ?? '') != (other.adminRole ?? '')) return false;
    if ((collegeId ?? '') != (other.collegeId ?? '')) return false;
    if ((subscriptionTier ?? '') != (other.subscriptionTier ?? '')) return false;
    if ((premiumUntil?.toIso8601String() ?? '') !=
        (other.premiumUntil?.toIso8601String() ?? '')) {
      return false;
    }
    final thisCapabilities = adminCapabilities.toSet();
    final otherCapabilities = other.adminCapabilities.toSet();
    return thisCapabilities.length == otherCapabilities.length &&
        thisCapabilities.containsAll(otherCapabilities);
  }
}
