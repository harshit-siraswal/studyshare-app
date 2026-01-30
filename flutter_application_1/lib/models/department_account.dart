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
}
