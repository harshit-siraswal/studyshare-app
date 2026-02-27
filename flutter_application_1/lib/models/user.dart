class AppRoles {
  AppRoles._(); // Prevent instantiation

  static const readOnly = 'READ_ONLY';
  static const admin = 'ADMIN';
  static const moderator = 'MODERATOR';
  static const collegeUser = 'COLLEGE_USER';
  static const teacher = 'TEACHER';

  static const Set<String> validRoles = {
    readOnly,
    admin,
    moderator,
    collegeUser,
    teacher,
  };
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
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw FormatException('AppUser.fromJson: id is null or empty');
    }
    
    final email = json['email']?.toString() ?? '';
    if (email.isEmpty) {
      throw FormatException('AppUser.fromJson: email is null or empty for id=$id');
    }

    return AppUser(
      id: id,
      email: email,
      displayName: json['display_name'],
      username: json['username'],
      profilePhotoUrl: json['profile_photo_url'],
      college: json['college'],
      bio: json['bio'],
      role: () {
        final r = json['role']?.toString();
        if (r != null && AppRoles.validRoles.contains(r)) {
          return r;
        }
        return AppRoles.readOnly;
      }(),
      createdAt: () {
        if (json['created_at'] == null) {
          throw FormatException('AppUser.fromJson: created_at is null for id=${json['id']}');
        }
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
  bool get isTeacher => role == AppRoles.teacher;
  bool get canPostNotices => isTeacher || isAdmin;
  bool get canPostSyllabus => isTeacher || isAdmin;
  bool get isVerified => role == AppRoles.collegeUser || isModerator || isTeacher;
}
