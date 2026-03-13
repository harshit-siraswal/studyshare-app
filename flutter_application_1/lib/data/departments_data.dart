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
    'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
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
  // Configurable source (can be replaced with fetch from API/Asset)
  static Future<List<DepartmentData>> getDepartments() async {
    // Simulate async fetch or loading from config
    await Future.delayed(const Duration(milliseconds: 10)); // Minimal delay

    return const [
      DepartmentData(
        name: 'CSE',
        full: 'Computer Science & Engineering (CSE/CS)',
        color: Color(0xFF8B5CF6),
      ),
      DepartmentData(
        name: 'IT/CSIT',
        full: 'Information Technology (IT/CSIT)',
        color: Color(0xFF14B8A6),
      ),
      DepartmentData(
        name: 'CSE-AI',
        full: 'Computer Science (AI)',
        color: Color(0xFF6366F1),
      ),
      DepartmentData(
        name: 'CSE-AIML',
        full: 'Computer Science (AI & ML)',
        color: Color(0xFF7C3AED),
      ),
      DepartmentData(
        name: 'CSE-DS',
        full: 'Computer Science (Data Science)',
        color: Color(0xFF0EA5E9),
      ),
      DepartmentData(
        name: 'CSE-CS',
        full: 'Computer Science (Cyber Security)',
        color: Color(0xFF2563EB),
      ),
      DepartmentData(
        name: 'ECE',
        full: 'Electronics & Communication Engineering (ECE)',
        color: Color(0xFF10B981),
      ),
      DepartmentData(
        name: 'ECE-VLSI',
        full: 'ECE (VLSI Design & Technology)',
        color: Color(0xFF0F766E),
      ),
      DepartmentData(
        name: 'EEE',
        full: 'Electrical & Electronics Engineering (EEE)',
        color: Color(0xFFF59E0B),
      ),
      DepartmentData(
        name: 'ELCE',
        full: 'Electrical & Computer Engineering (ELCE)',
        color: Color(0xFF0284C7),
      ),
      DepartmentData(
        name: 'ME',
        full: 'Mechanical Engineering (ME)',
        color: Color(0xFFEF4444),
      ),
      DepartmentData(
        name: 'AM&IA',
        full: 'Advanced Mechatronics & Industrial Automation',
        color: Color(0xFFDC2626),
      ),
      DepartmentData(
        name: 'CE',
        full: 'Civil Engineering',
        color: Color(0xFF6366F1),
      ),
    ];
  }
}
