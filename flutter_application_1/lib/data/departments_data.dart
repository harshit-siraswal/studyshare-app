import 'dart:ui';

import 'academic_subjects_data.dart';

class DepartmentData {
  final String name;
  final String full;
  final Color color;

  const DepartmentData({
    required this.name,
    required this.full,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'full': full,
    'color':
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
  };

  factory DepartmentData.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final full = json['full'];
    final colorHex = json['color'];

    if (name is! String || full is! String) {
      throw FormatException('Invalid DepartmentData JSON: $json');
    }

    Color color;
    if (colorHex is int) {
      // Handle legacy integer serialization
      color = Color(colorHex);
    } else if (colorHex is String && colorHex.startsWith('#')) {
      // Handle hex string
      final hex = colorHex.substring(1);
      final val = int.tryParse(hex, radix: 16);
      if (val != null) {
        color = Color(val);
      } else {
        throw FormatException('Invalid hex color value: $colorHex');
      }
    } else {
      throw FormatException('Invalid DepartmentData JSON color: $colorHex');
    }

    return DepartmentData(name: name, full: full, color: color);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DepartmentData &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          full == other.full &&
          color == other.color;

  @override
  int get hashCode => Object.hash(name, full, color);
}

class DepartmentsProvider {
  static const List<Color> _departmentPalette = <Color>[
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFF7C3AED),
    Color(0xFF0EA5E9),
    Color(0xFF2563EB),
    Color(0xFF10B981),
    Color(0xFF0F766E),
    Color(0xFFF59E0B),
    Color(0xFF0284C7),
    Color(0xFFEF4444),
    Color(0xFFDC2626),
    Color(0xFF64748B),
    Color(0xFF8B5E3C),
    Color(0xFFD97706),
    Color(0xFF6D28D9),
  ];

  static Future<List<DepartmentData>> getDepartments({
    String? collegeId,
    String? collegeDomain,
    String? collegeName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final options = getBranchOptionsForCollege(
      collegeId: collegeId,
      collegeDomain: collegeDomain,
      collegeName: collegeName,
    );

    return <DepartmentData>[
      for (var index = 0; index < options.length; index++)
        DepartmentData(
          name: options[index].shortLabel,
          full: options[index].label,
          color: _departmentPalette[index % _departmentPalette.length],
        ),
    ];
  }
}
