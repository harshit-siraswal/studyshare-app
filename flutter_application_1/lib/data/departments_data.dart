import 'dart:ui';

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
    'color': '#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase()}',
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
    
    return DepartmentData(
      name: name,
      full: full,
      color: color,
    );
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
  // Configurable source (can be replaced with fetch from API/Asset)
  static Future<List<DepartmentData>> getDepartments() async {
    // Simulate async fetch or loading from config
    await Future.delayed(const Duration(milliseconds: 10)); // Minimal delay
    
    return const [
      DepartmentData(name: 'CSE', full: 'Computer Science', color: Color(0xFF8B5CF6)),
      DepartmentData(name: 'ECE', full: 'Electronics & Comm', color: Color(0xFF10B981)),
      DepartmentData(name: 'EEE', full: 'Electrical Engg', color: Color(0xFFF59E0B)),
      DepartmentData(name: 'ME', full: 'Mechanical Engg', color: Color(0xFFEF4444)),
      DepartmentData(name: 'CE', full: 'Civil Engineering', color: Color(0xFF6366F1)),
      DepartmentData(name: 'IT', full: 'Information Tech', color: Color(0xFF14B8A6)),
    ];
  }
}
