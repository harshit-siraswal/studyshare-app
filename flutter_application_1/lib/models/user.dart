class AppUser {
  final String id;
  final String email;
  final String? displayName;
  final String? username;
  final String? profilePhotoUrl;
  final String? college;
  final String? bio;
  final String role; // READ_ONLY, COLLEGE_USER, MODERATOR, ADMIN
  final DateTime createdAt;

  AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.username,
    this.profilePhotoUrl,
    this.college,
    this.bio,
    this.role = 'READ_ONLY',
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
      role: json['role'] ?? 'READ_ONLY',
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
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
      final parts = displayName!.split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return displayName![0].toUpperCase();
    }
    return email[0].toUpperCase();
  }

  /// Check permissions
  bool get canUpload => role != 'READ_ONLY';
  bool get canComment => role != 'READ_ONLY';
  bool get canVote => role != 'READ_ONLY';
  bool get canJoinChatrooms => role != 'READ_ONLY';
  bool get isAdmin => role == 'ADMIN';
  bool get isModerator => role == 'MODERATOR' || role == 'ADMIN';
  bool get isVerified => role == 'COLLEGE_USER' || isModerator;
}
