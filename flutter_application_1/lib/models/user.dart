class AppRoles {
  static const readOnly = 'READ_ONLY';
  static const admin = 'ADMIN';
  static const moderator = 'MODERATOR';
  static const collegeUser = 'COLLEGE_USER';
  static const teacher = 'TEACHER';
}

class AppUser {
  final String id;
  final String email;
  final String? displayName;
  final String? username;
  final String? profilePhotoUrl;
  final String? college;
  final String? bio;
  final String role; // READ_ONLY, COLLEGE_USER, MODERATOR, ADMIN, TEACHER
  final DateTime createdAt;

  AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.username,
    this.profilePhotoUrl,
    this.college,
    this.bio,
    this.role = AppRoles.readOnly,
    required this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      displayName: json['display_name'],
      username: json['username'],
      profilePhotoUrl: json['profile_photo_url'],
      college: json['college'],
      bio: json['bio'],
      role: json['role'] ?? AppRoles.readOnly,
      createdAt: () {
        if (json['created_at'] == null) return DateTime.now();
        final parsed = DateTime.tryParse(json['created_at'].toString());
        if (parsed == null) {
          throw FormatException('AppUser.fromJson: failed to parse created_at for id=${json['id']}');
        }
        return parsed;
      }(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'username': username,
      'profile_photo_url': profilePhotoUrl,
      'college': college,
      'bio': bio,
      'role': role,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Get display name or fallback to email
  String get name => displayName ?? email.split('@').first;

  /// Get initials for avatar
  String get initials {
    if (displayName != null && displayName!.isNotEmpty) {
      final parts = displayName!.trim().split(' ').where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else if (parts.isNotEmpty) {
        return parts[0][0].toUpperCase();
      }
    }
    return email.isNotEmpty ? email[0].toUpperCase() : '?';
  }

  /// Check permissions
  bool get canUpload => role != AppRoles.readOnly;
  bool get canComment => role != AppRoles.readOnly;
  bool get canVote => role != AppRoles.readOnly;
  bool get canJoinChatrooms => role != AppRoles.readOnly;
  bool get isAdmin => role == AppRoles.admin;
  bool get isModerator => role == AppRoles.moderator || role == AppRoles.admin;
  bool get isVerified => role == AppRoles.collegeUser || isModerator || role == AppRoles.teacher;
}
