import 'dart:convert';

import 'dart:async';
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
  static const String _snapshotKeyPrefix = 'attendance_snapshot_';
  static const String _tokenKeyPrefix = 'attendance_token_';
  static const String _syncCooldownKeyPrefix = 'attendance_sync_cooldown_until_';
  final BackendApiService _apiService;

  String _normalizeKeyPart(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  String _cacheSuffix({String? userEmail}) {
    final normalized = _normalizeKeyPart(userEmail ?? '');
    return normalized.isEmpty ? '' : '_$normalized';
  }

  String _snapshotKey(String collegeId, {String? userEmail}) =>
      '$_snapshotKeyPrefix${_normalizeKeyPart(collegeId)}'
      '${_cacheSuffix(userEmail: userEmail)}';

  String _tokenKey(String collegeId, {String? userEmail}) =>
      '$_tokenKeyPrefix${_normalizeKeyPart(collegeId)}'
      '${_cacheSuffix(userEmail: userEmail)}';

  List<String> _snapshotKeyCandidates(String collegeId, {String? userEmail}) {
    final normalizedEmail = userEmail?.trim();
    if (normalizedEmail != null && normalizedEmail.isNotEmpty) {
      return <String>[_snapshotKey(collegeId, userEmail: normalizedEmail)];
    }
    return <String>[_snapshotKey(collegeId)];
  }

  List<String> _tokenKeyCandidates(String collegeId, {String? userEmail}) {
    final normalizedEmail = userEmail?.trim();
    if (normalizedEmail != null && normalizedEmail.isNotEmpty) {
      return <String>[_tokenKey(collegeId, userEmail: normalizedEmail)];
    }
    return <String>[_tokenKey(collegeId)];
  }

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

  Future<AttendanceSnapshot?> loadCachedSnapshot(
    String collegeId, {
    String? userEmail,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _snapshotKeyCandidates(collegeId, userEmail: userEmail)) {
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        return AttendanceSnapshot.fromJson(Map<String, dynamic>.from(decoded));
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<String?> loadSavedToken(String collegeId, {String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _tokenKeyCandidates(collegeId, userEmail: userEmail)) {
      final token = prefs.getString(key)?.trim();
      if (token == null || token.isEmpty) continue;
      return token;
    }
    return null;
  }

  Future<void> clearSavedSession(String collegeId, {String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = <String>{
      ..._tokenKeyCandidates(collegeId, userEmail: userEmail),
      ..._snapshotKeyCandidates(collegeId, userEmail: userEmail),
      _tokenKey(collegeId),
      _snapshotKey(collegeId),
    };
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  Future<void> clearAllSavedSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = prefs.getKeys().where((key) {
      return key.startsWith(_tokenKeyPrefix) ||
          key.startsWith(_snapshotKeyPrefix) ||
          key.startsWith(_syncCooldownKeyPrefix);
    }).toList(growable: false);

    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }

  Future<AttendanceSnapshot> syncKietAttendance({
    required String collegeId,
    required String collegeName,
    required String cybervidyaToken,
    String? userEmail,
  }) async {
    try {
      final response = await _apiService.syncKietAttendance(
        collegeId: collegeId,
        cybervidyaToken: cybervidyaToken,
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
      final snapshotJson = jsonEncode(snapshot.toJson());
      final normalizedEmail = userEmail?.trim();
      if (normalizedEmail != null && normalizedEmail.isNotEmpty) {
        await prefs.setString(
          _tokenKey(collegeId, userEmail: normalizedEmail),
          cybervidyaToken,
        );
        await prefs.setString(
          _snapshotKey(collegeId, userEmail: normalizedEmail),
          snapshotJson,
        );
      } else {
        await prefs.setString(_tokenKey(collegeId), cybervidyaToken);
        await prefs.setString(_snapshotKey(collegeId), snapshotJson);
      }

      unawaited(
        AttendanceNotificationService.instance
            .notifyLowAttendance(
              collegeId: collegeId,
              collegeName: collegeName,
              lowAttendance: snapshot.lowAttendance,
            )
            .catchError((error) {
              debugPrint(
                '[AttendanceService] notifyLowAttendance failed: $error',
              );
            }),
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
    String? userEmail,
  }) async {
    try {
      final token = await loadSavedToken(collegeId, userEmail: userEmail);
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

  bool isAttendanceOrSchedulePrompt(String prompt) {
    final normalized = prompt.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    const attendanceKeywords = <String>[
      'attendance',
      'low attendance',
      'attendance risk',
      'attendance percentage',
      'attendance today',
      'present classes',
      'absent',
    ];

    const scheduleKeywords = <String>[
      'schedule',
      'timetable',
      'time table',
      'next class',
      'next lecture',
      'room number',
      'room no',
      'room',
      'upcoming class',
      'upcoming classes',
      'today\'s class',
      'today\'s classes',
    ];

    return attendanceKeywords.any(normalized.contains) ||
        scheduleKeywords.any(normalized.contains);
  }

  Future<String?> buildLocalAiResponse({
    required String collegeId,
    required String collegeName,
    required String prompt,
    String? userEmail,
  }) async {
    if (!isAttendanceOrSchedulePrompt(prompt)) return null;

    final snapshot = await loadCachedSnapshot(collegeId, userEmail: userEmail);
    if (snapshot == null) return null;

    return buildLocalAiResponseForSnapshot(
      snapshot: snapshot,
      prompt: prompt,
      now: DateTime.now(),
      collegeName: collegeName,
    );
  }

  String buildLocalAiResponseForSnapshot({
    required AttendanceSnapshot snapshot,
    required String prompt,
    required DateTime now,
    String collegeName = '',
  }) {
    final buffer = StringBuffer()
      ..writeln('I checked your private KIET ERP cache.')
      ..writeln('Student: ${snapshot.student.fullName}')
      ..writeln('Registration number: ${snapshot.student.registrationNumber}');

    if (snapshot.student.studentId != null) {
      buffer.writeln('Student ID ${snapshot.student.studentId}');
    }

    if (collegeName.trim().isNotEmpty) {
      buffer.writeln('College: ${collegeName.trim()}');
    }

    buffer
      ..writeln(
        'Program: ${snapshot.student.degreeName} • '
        '${snapshot.student.branchShortName} • '
        '${snapshot.student.semesterName} • '
        'Section ${snapshot.student.sectionName}',
      )
      ..writeln(
        'Overall attendance: '
        '${snapshot.overall.percentage.toStringAsFixed(2)}% '
        '(${snapshot.overall.presentClasses}/${snapshot.overall.totalClasses})',
      );

    if (snapshot.lowAttendance.isEmpty) {
      buffer.writeln(
        'Low attendance summary: No subjects are currently below the threshold.',
      );
    } else {
      buffer.writeln('Low attendance summary:');
      for (final component in snapshot.lowAttendance) {
        buffer.writeln(
          '- ${component.courseName} (${component.componentName}): '
          '${component.percentage.toStringAsFixed(2)}%, need '
          '${component.classesNeededForThreshold} more attended classes '
          'to reach ${component.threshold}%.',
        );
      }
    }

    final scheduleEntries = _upcomingScheduleEntries(snapshot.schedule, now);
    if (scheduleEntries.isNotEmpty) {
      buffer.writeln('Upcoming classes:');
      for (final entry in scheduleEntries) {
        final dateLabel = formatDateDdMmYyyy(entry.lectureDate);
        final roomLabel = entry.classRoom.trim().isEmpty
            ? 'Room unavailable'
            : 'Room ${entry.classRoom}';
        buffer.writeln(
          '- ${entry.courseName} • ${entry.courseComponentName} '
          'on $dateLabel at ${entry.start}-${entry.end} in $roomLabel',
        );
      }
    } else if (isAttendanceOrSchedulePrompt(prompt)) {
      buffer.writeln(
        'Upcoming classes: No upcoming classes are available in the private KIET ERP cache.',
      );
    }

    return buffer.toString().trim();
  }

  List<AttendanceScheduleEntry> _upcomingScheduleEntries(
    AttendanceSchedule schedule,
    DateTime now,
  ) {
    final entries = schedule.entries.toList(growable: false);
    if (entries.isEmpty) return entries;

    final upcoming = entries
        .where((entry) {
          final scheduled = _scheduleEntryDateTime(entry);
          if (scheduled == null) return true;
          return !scheduled.isBefore(now);
        })
        .toList(growable: false);

    final sorted = upcoming.isNotEmpty ? upcoming : entries;
    return sorted.toList()..sort((left, right) {
      final leftTime = _scheduleEntryDateTime(left);
      final rightTime = _scheduleEntryDateTime(right);
      if (leftTime == null && rightTime == null) return 0;
      if (leftTime == null) return 1;
      if (rightTime == null) return -1;
      return leftTime.compareTo(rightTime);
    });
  }

  DateTime? _scheduleEntryDateTime(AttendanceScheduleEntry entry) {
    final date = tryParseDate(entry.lectureDate);
    if (date == null) return null;

    final parts = entry.start.split(':');
    if (parts.length < 2) return date;

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
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
          // Avoid sending snapshot.student.fullName to external models; use a
          // non-identifying reference that still helps the AI describe the report.
          final studentReference = snapshot.student.studentId != null
            ? 'Student ID ${snapshot.student.studentId}'
            : snapshot.student.registrationNumber.trim().isNotEmpty
            ? 'Registration ${snapshot.student.registrationNumber.trim()}'
            : 'Anonymous student';
    return 'I am a KIET student. Analyze my attendance and tell me the most urgent recovery steps, '
        'which subjects are risky, and how I should plan the next week.\n\n'
        'Overall attendance: ${overall.percentage.toStringAsFixed(2)}% '
        '(${overall.presentClasses}/${overall.totalClasses})\n'
            'Student: $studentReference, ${snapshot.student.branchShortName}, '
            '${snapshot.student.semesterName}\n\n'
        'Low attendance summary:\n$lowAttendanceLines';
  }
}
