import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance_models.dart';
import 'attendance_notification_service.dart';
import 'backend_api_service.dart';

class AttendanceSyncException implements Exception {
  const AttendanceSyncException({
    required this.code,
    required this.message,
    this.retryable = false,
    this.cause,
  });

  final String code;
  final String message;
  final bool retryable;
  final Object? cause;

  @override
  String toString() => message;
}

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
    try {
      final response = await _apiService.syncKietAttendance(
        collegeId: collegeId,
        cybervidyaToken: cybervidyaToken,
        context: context,
      );
      final snapshotRaw = response['snapshot'];
      if (snapshotRaw is! Map) {
        throw const AttendanceSyncException(
          code: 'invalid_snapshot',
          message: 'Attendance sync returned an invalid snapshot.',
        );
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
    } on AttendanceSyncException {
      rethrow;
    } catch (error) {
      final mapped = _mapAttendanceError(error, isDaywise: false);
      debugPrint(
        '[AttendanceService] syncKietAttendance failed '
        '(code=${mapped.code}, retryable=${mapped.retryable}): $error',
      );
      throw mapped;
    }
  }

  Future<List<AttendanceLecture>> getDaywiseAttendance({
    required String collegeId,
    required AttendanceComponent component,
    required int studentId,
  }) async {
    try {
      final token = await loadSavedToken(collegeId);
      if (token == null || token.isEmpty) {
        throw const AttendanceSyncException(
          code: 'session_expired',
          message: 'Please reconnect KIET ERP to load daywise attendance.',
        );
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
            (item) =>
                AttendanceLecture.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on AttendanceSyncException {
      rethrow;
    } catch (error) {
      final mapped = _mapAttendanceError(error, isDaywise: true);
      debugPrint(
        '[AttendanceService] getDaywiseAttendance failed '
        '(code=${mapped.code}, retryable=${mapped.retryable}): $error',
      );
      throw mapped;
    }
  }

  AttendanceSyncException _mapAttendanceError(
    Object error, {
    required bool isDaywise,
  }) {
    if (error is AttendanceSyncException) return error;

    final fallbackMessage = isDaywise
        ? 'Failed to load daywise attendance. Please try again.'
        : 'Failed to sync KIET attendance. Please try again.';

    if (error is BackendApiHttpException) {
      final statusCode = error.statusCode;
      final message = error.message.trim().isEmpty
          ? fallbackMessage
          : error.message.trim();
      if (statusCode == 401 || statusCode == 403) {
        return AttendanceSyncException(
          code: 'session_expired',
          message: 'Your KIET session expired. Please login again.',
          retryable: false,
          cause: error,
        );
      }
      if (statusCode == 429) {
        return AttendanceSyncException(
          code: 'rate_limited',
          message: 'Too many attendance requests. Please retry shortly.',
          retryable: true,
          cause: error,
        );
      }
      if (statusCode >= 500) {
        return AttendanceSyncException(
          code: 'backend_unavailable',
          message: 'Attendance service is temporarily unavailable.',
          retryable: true,
          cause: error,
        );
      }
      return AttendanceSyncException(
        code: 'http_$statusCode',
        message: message,
        retryable: false,
        cause: error,
      );
    }

    final lowered = error.toString().toLowerCase();
    if (lowered.contains('security check') || lowered.contains('recaptcha')) {
      return AttendanceSyncException(
        code: 'security_check',
        message: 'Security verification failed. Please retry login once.',
        retryable: true,
        cause: error,
      );
    }
    if (lowered.contains('timeout') || lowered.contains('timed out')) {
      return AttendanceSyncException(
        code: 'timeout',
        message: 'Attendance request timed out. Please try again.',
        retryable: true,
        cause: error,
      );
    }
    if (lowered.contains('connection') || lowered.contains('network')) {
      return AttendanceSyncException(
        code: 'network_error',
        message: 'Network issue while syncing attendance. Check connection.',
        retryable: true,
        cause: error,
      );
    }
    if (lowered.contains('authentication required') ||
        lowered.contains('invalid token') ||
        lowered.contains('session expired')) {
      return AttendanceSyncException(
        code: 'session_expired',
        message: 'Your KIET session expired. Please login again.',
        retryable: false,
        cause: error,
      );
    }

    return AttendanceSyncException(
      code: 'unknown',
      message: fallbackMessage,
      retryable: false,
      cause: error,
    );
  }

  /// Parses a KIET date string into a [DateTime] when possible.
  DateTime? tryParseDate(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.isEmpty) return null;

    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    final normalized = trimmed.replaceAll('.', '/').replaceAll('-', '/');
    final parts = normalized.split('/');
    if (parts.length != 3) return null;

    final p0 = int.tryParse(parts[0]);
    final p1 = int.tryParse(parts[1]);
    final p2 = int.tryParse(parts[2]);
    if (p0 == null || p1 == null || p2 == null) return null;

    if (parts[0].length == 4) {
      return DateTime(p0, p1, p2);
    }

    if (parts[2].length == 4) {
      final year = p2;
      int day;
      int month;
      if (p0 > 12) {
        day = p0;
        month = p1;
      } else if (p1 > 12) {
        day = p1;
        month = p0;
      } else {
        day = p0;
        month = p1;
      }
      return DateTime(year, month, day);
    }

    return null;
  }

  /// Formats a date string as `dd/MM/yyyy` for display.
  String formatDateDdMmYyyy(String rawDate) {
    final parsed = tryParseDate(rawDate);
    if (parsed == null) return rawDate;

    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final day = twoDigits(parsed.day);
    final month = twoDigits(parsed.month);
    return '$day/$month/${parsed.year}';
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
