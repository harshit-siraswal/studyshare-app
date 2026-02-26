import 'package:flutter/material.dart';

class DepartmentAccount {
  final String id;
  final String name;
  final String handle;
  final String avatarLetter;
  final Color color;
  final int noticeCount;
  
  const DepartmentAccount({
    required this.id,
    required this.name,
    required this.handle,
    required this.avatarLetter,
    required this.color,
    this.noticeCount = 0,
  });
  factory DepartmentAccount.unknown({String? deptId}) {
    return DepartmentAccount(
      id: deptId ?? 'unknown',
      name: 'Unknown Department',
      handle: '@unknown',
      avatarLetter: '?',
      color: const Color(0xFF64748B),
    );
  }

  factory DepartmentAccount.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString() ?? '';
    if (rawId.isEmpty) {
      return DepartmentAccount.unknown();
    }

    String hexColor = json['color']?.toString() ?? '64748B'; // Default slate-500
    if (hexColor.startsWith('#')) hexColor = hexColor.substring(1);
    final colorValue = int.tryParse('FF$hexColor', radix: 16) ?? 0xFF64748B;

    return DepartmentAccount(
      id: rawId,
      name: json['name']?.toString() ?? 'Unknown Department',
      handle: json['handle']?.toString() ?? '@unknown',
      avatarLetter: json['avatar_letter']?.toString() ?? '?',
      color: Color(colorValue),
      noticeCount: _parseIntOrString(json['notice_count']),
    );
  }

  static int _parseIntOrString(dynamic val) {
    if (val is int) return val;
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }
}
