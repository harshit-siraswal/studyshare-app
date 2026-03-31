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

  static String _asString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  static bool _asBool(dynamic value, {bool fallback = true}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return fallback;
  }

  factory College.fromJson(Map<String, dynamic> json) {
    final id = _asString(json['id']);
    final name = _asString(json['name']);
    final domain = _asString(
      json['domain'] ?? json['college_domain'] ?? json['email_domain'],
    ).replaceAll('@', '');

    return College(
      id: id,
      name: name,
      domain: domain,
      code: _asString(json['code']).isEmpty ? null : _asString(json['code']),
      logoUrl: _asString(json['logo_url']).isEmpty
          ? null
          : _asString(json['logo_url']),
      isActive: _asBool(json['is_active'], fallback: true),
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
