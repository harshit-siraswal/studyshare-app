import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance_models.dart';
import 'attendance_notification_service.dart';
import 'backend_api_service.dart';

class AttendanceService {
  AttendanceService({BackendApiService? apiService})
    : _apiService = apiService ?? BackendApiService();

  static const int lowAttendanceThreshold = 75;
  final BackendApiService _apiService;

  String _snapshotKey(String collegeId) => 'attendance_snapshot_$collegeId';
  String _tokenKey(String collegeId) => 'attendance_token_$collegeId';

  bool isKietCollege({
    required String collegeId,
    required String collegeName,
    String? collegeDomain,
  }) {
    final id = collegeId.trim().toLowerCase();
    final name = collegeName.trim().toLowerCase();
    final domain = collegeDomain?.trim().toLowerCase() ?? '';
    return id.contains('kiet') ||
        name.contains('kiet') ||
        domain.contains('kiet');
  }

  Future<AttendanceSnapshot?> loadCachedSnapshot(String collegeId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey(collegeId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AttendanceSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadSavedToken(String collegeId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey(collegeId))?.trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<void> clearSavedSession(String collegeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey(collegeId));
    await prefs.remove(_snapshotKey(collegeId));
  }

  Future<AttendanceSnapshot> syncKietAttendance({
    required String collegeId,
    required String collegeName,
    required String cybervidyaToken,
    required BuildContext context,
  }) async {
    final response = await _apiService.syncKietAttendance(
      collegeId: collegeId,
      cybervidyaToken: cybervidyaToken,
      context: context,
    );
    final snapshotRaw = response['snapshot'];
    if (snapshotRaw is! Map) {
      throw Exception('Attendance sync returned an invalid snapshot');
    }

    final snapshot = AttendanceSnapshot.fromJson(
      Map<String, dynamic>.from(snapshotRaw),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey(collegeId), cybervidyaToken);
    await prefs.setString(
      _snapshotKey(collegeId),
      jsonEncode(snapshot.toJson()),
    );

    await AttendanceNotificationService.instance.notifyLowAttendance(
      collegeId: collegeId,
      collegeName: collegeName,
      lowAttendance: snapshot.lowAttendance,
    );

    return snapshot;
  }

  Future<List<AttendanceLecture>> getDaywiseAttendance({
    required String collegeId,
    required AttendanceComponent component,
    required int studentId,
  }) async {
    final token = await loadSavedToken(collegeId);
    if (token == null || token.isEmpty) {
      throw Exception('Please reconnect KIET ERP to load daywise attendance.');
    }

    final response = await _apiService.getKietAttendanceDaywise(
      collegeId: collegeId,
      cybervidyaToken: token,
      courseId: component.courseId,
      courseComponentId: component.courseComponentId,
      studentId: studentId,
    );

    final lecturesRaw = (response['lectures'] as List?) ?? const [];
    return lecturesRaw
        .whereType<Map>()
        .map(
          (item) => AttendanceLecture.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  String buildAiPrompt(AttendanceSnapshot snapshot) {
    final lowAttendanceLines = snapshot.lowAttendance.isEmpty
        ? 'No subjects are currently below 75% attendance.'
        : snapshot.lowAttendance
              .map((component) {
                return '- ${component.courseName} (${component.componentName}): '
                    '${component.percentage.toStringAsFixed(2)}%, '
                    'need ${component.classesNeededForThreshold} more attended classes '
                    'to reach ${component.threshold}%';
              })
              .join('\n');

    final overall = snapshot.overall;
    return 'I am a KIET student. Analyze my attendance and tell me the most urgent recovery steps, '
        'which subjects are risky, and how I should plan the next week.\n\n'
        'Overall attendance: ${overall.percentage.toStringAsFixed(2)}% '
        '(${overall.presentClasses}/${overall.totalClasses})\n'
        'Student: ${snapshot.student.fullName}, ${snapshot.student.branchShortName}, '
        '${snapshot.student.semesterName}\n\n'
        'Low attendance summary:\n$lowAttendanceLines';
  }
}
