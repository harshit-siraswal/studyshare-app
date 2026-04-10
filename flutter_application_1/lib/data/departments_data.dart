import 'dart:ui';

import 'department_catalog.dart';

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
  static Future<List<DepartmentData>> getDepartments() async {
    return departmentCatalogEntries
        .map(
          (entry) => DepartmentData(
            name: entry.shortName,
            full: entry.name,
            color: entry.color,
          ),
        )
        .toList(growable: false);
  }
}
