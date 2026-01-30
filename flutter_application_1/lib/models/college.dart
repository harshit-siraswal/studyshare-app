class College {
  final String id;
  final String name;
  final String domain;
  final String? code;
  final String? logoUrl;
  final bool isActive;

  College({
    required this.id,
    required this.name,
    required this.domain,
    this.code,
    this.logoUrl,
    this.isActive = true,
  });

  factory College.fromJson(Map<String, dynamic> json) {
    return College(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      domain: json['domain'] ?? '',
      code: json['code'],
      logoUrl: json['logo_url'],
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'domain': domain,
      'code': code,
      'logo_url': logoUrl,
      'is_active': isActive,
    };
  }

  /// Get first letter for avatar fallback
  String get initial => name.isNotEmpty ? name[0].toUpperCase() : 'C';
}
