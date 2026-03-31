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
  static const int _maxAiLowAttendanceItems = 5;
  static const int _maxAiUpcomingClasses = 4;
  final BackendApiService _apiService;

  String _legacySnapshotKey(String collegeId) =>
      'attendance_snapshot_$collegeId';
  String _legacyTokenKey(String collegeId) => 'attendance_token_$collegeId';

  String _normalizeScopeComponent(String? rawValue) {
    final lowered = rawValue?.trim().toLowerCase() ?? '';
    if (lowered.isEmpty) return '';
    return lowered
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _snapshotKey(String collegeId, {String? userEmail}) {
    final scope = _normalizeScopeComponent(userEmail);
    final legacyKey = _legacySnapshotKey(collegeId);
    return scope.isEmpty ? legacyKey : '${legacyKey}_$scope';
  }

  String _tokenKey(String collegeId, {String? userEmail}) {
    final scope = _normalizeScopeComponent(userEmail);
    final legacyKey = _legacyTokenKey(collegeId);
    return scope.isEmpty ? legacyKey : '${legacyKey}_$scope';
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
    final raw = prefs.getString(_snapshotKey(collegeId, userEmail: userEmail));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AttendanceSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadSavedToken(String collegeId, {String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs
        .getString(_tokenKey(collegeId, userEmail: userEmail))
        ?.trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<void> clearSavedSession(String collegeId, {String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = <String>{
      _legacyTokenKey(collegeId),
      _legacySnapshotKey(collegeId),
      _tokenKey(collegeId, userEmail: userEmail),
      _snapshotKey(collegeId, userEmail: userEmail),
    };
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }

  Future<void> clearAllSavedSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) {
          return key.startsWith('attendance_snapshot_') ||
              key.startsWith('attendance_token_');
        })
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  Future<AttendanceSnapshot> syncKietAttendance({
    required String collegeId,
    required String collegeName,
    required String cybervidyaToken,
    required BuildContext context,
    String? userEmail,
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
      final tokenKey = _tokenKey(collegeId, userEmail: userEmail);
      final snapshotKey = _snapshotKey(collegeId, userEmail: userEmail);
      await prefs.setString(tokenKey, cybervidyaToken);
      await prefs.setString(snapshotKey, jsonEncode(snapshot.toJson()));
      if (tokenKey != _legacyTokenKey(collegeId)) {
        await prefs.remove(_legacyTokenKey(collegeId));
      }
      if (snapshotKey != _legacySnapshotKey(collegeId)) {
        await prefs.remove(_legacySnapshotKey(collegeId));
      }

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

  bool isAttendanceOrSchedulePrompt(String prompt) {
    final normalized = prompt.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    const directKeywords = <String>[
      'attendance',
      'attendence',
      'low attendance',
      'attendance shortage',
      'present classes',
      'total classes',
      'bunk',
      'bunk allowance',
      'classes needed',
      'student id',
      'registration number',
      'recover attendance',
      '75%',
    ];
    if (directKeywords.any(normalized.contains)) {
      return true;
    }

    const scheduleKeywords = <String>[
      'time table',
      'timetable',
      'today class',
      'class today',
      'today timetable',
      'today time table',
      'next class',
      'upcoming class',
      'current class',
      'live class',
      'class room',
      'classroom',
      'room number',
      'lecture timing',
      'class timing',
      'faculty today',
      'today lecture',
    ];
    return scheduleKeywords.any(normalized.contains);
  }

  Future<String?> buildLocalAiResponse({
    required String collegeId,
    required String collegeName,
    required String prompt,
    String? userEmail,
  }) async {
    if (!isKietCollege(collegeId: collegeId, collegeName: collegeName) ||
        !isAttendanceOrSchedulePrompt(prompt)) {
      return null;
    }

    final snapshot = await loadCachedSnapshot(collegeId, userEmail: userEmail);
    if (snapshot == null) {
      return 'I do not have a private KIET attendance cache for this account '
          'yet. Open the Attendance screen, connect KIET ERP once, and sync '
          'your data so I can answer from your own offline snapshot only.';
    }

    return buildLocalAiResponseForSnapshot(snapshot: snapshot, prompt: prompt);
  }

  String buildLocalAiResponseForSnapshot({
    required AttendanceSnapshot snapshot,
    required String prompt,
    DateTime? now,
  }) {
    final normalized = prompt.trim().toLowerCase();
    final referenceNow = now ?? DateTime.now();
    final student = snapshot.student;
    final overall = snapshot.overall;

    final wantsStudentIdentity =
        normalized.contains('student id') ||
        normalized.contains('registration') ||
        normalized.contains('who am i');
    final wantsSchedule =
        normalized.contains('time table') ||
        normalized.contains('timetable') ||
        normalized.contains('today class') ||
        normalized.contains('class today') ||
        normalized.contains('next class') ||
        normalized.contains('upcoming class') ||
        normalized.contains('current class') ||
        normalized.contains('live class') ||
        normalized.contains('class room') ||
        normalized.contains('classroom') ||
        normalized.contains('room number') ||
        normalized.contains('lecture timing') ||
        normalized.contains('class timing') ||
        normalized.contains('faculty today');
    final wantsLowAttendance =
        normalized.contains('low attendance') ||
        normalized.contains('shortage') ||
        normalized.contains('risky') ||
        normalized.contains('recover') ||
        normalized.contains('75%') ||
        normalized.contains('need') ||
        normalized.contains('bunk');
    final wantsOverallAttendance =
        normalized.contains('attendance') ||
        normalized.contains('present classes') ||
        normalized.contains('total classes') ||
        normalized.contains('percentage');
    final wantsBunkAllowance =
        normalized.contains('bunk') ||
        normalized.contains('leave') ||
        normalized.contains('skip class');

    final hasSpecificIntent =
        wantsStudentIdentity ||
        wantsSchedule ||
        wantsLowAttendance ||
        wantsOverallAttendance;

    final sections = <String>[
      'This answer was generated locally from your private KIET ERP cache.',
      _buildStudentIdentityLine(student, snapshot.syncedAt),
    ];

    if (wantsStudentIdentity || !hasSpecificIntent) {
      sections.add(_buildStudentSummary(snapshot));
    }

    if (wantsOverallAttendance || !hasSpecificIntent) {
      sections.add(
        'Overall attendance: ${overall.percentage.toStringAsFixed(2)}% '
        '(${overall.presentClasses}/${overall.totalClasses} classes).',
      );
    }

    if (wantsLowAttendance || wantsBunkAllowance || !hasSpecificIntent) {
      sections.add(
        _buildLowAttendanceSummary(
          snapshot: snapshot,
          includeBunkAllowance: wantsBunkAllowance || !hasSpecificIntent,
        ),
      );
    }

    if (wantsSchedule || !hasSpecificIntent) {
      sections.add(
        _buildScheduleSummary(snapshot: snapshot, now: referenceNow),
      );
    }

    if (wantsLowAttendance || !hasSpecificIntent) {
      sections.add(_buildRecoveryAdvice(snapshot));
    }

    return sections.where((section) => section.trim().isNotEmpty).join('\n\n');
  }

  String _buildStudentIdentityLine(
    AttendanceStudent student,
    DateTime syncedAt,
  ) {
    final identity = <String>[
      if (student.fullName.trim().isNotEmpty) student.fullName.trim(),
      if (student.studentId != null) 'Student ID ${student.studentId}',
      if (student.registrationNumber.trim().isNotEmpty)
        'Reg ${student.registrationNumber.trim()}',
    ];
    final syncLabel = syncedAt.millisecondsSinceEpoch <= 0
        ? 'Sync time unavailable'
        : 'Synced ${formatDateDdMmYyyy(syncedAt.toIso8601String())} '
              'at ${_formatTimeOfDay(syncedAt)}';
    return '${identity.join(' | ')}\n$syncLabel';
  }

  String _buildStudentSummary(AttendanceSnapshot snapshot) {
    final student = snapshot.student;
    final parts = <String>[
      if (student.branchShortName.trim().isNotEmpty)
        student.branchShortName.trim(),
      if (student.semesterName.trim().isNotEmpty) student.semesterName.trim(),
      if (student.sectionName.trim().isNotEmpty)
        'Section ${student.sectionName.trim()}',
      if (student.degreeName.trim().isNotEmpty) student.degreeName.trim(),
    ];
    if (parts.isEmpty) return '';
    return 'Student profile: ${parts.join(' | ')}.';
  }

  String _buildLowAttendanceSummary({
    required AttendanceSnapshot snapshot,
    required bool includeBunkAllowance,
  }) {
    if (snapshot.lowAttendance.isEmpty) {
      return 'Low attendance: no course component is currently below '
          '$lowAttendanceThreshold%.';
    }

    final lines = snapshot.lowAttendance
        .take(_maxAiLowAttendanceItems)
        .map((component) {
          final details = <String>[
            '${component.percentage.toStringAsFixed(2)}%',
            'need ${component.classesNeededForThreshold} more attended classes '
                'to reach ${component.threshold}%',
            if (includeBunkAllowance)
              'safe bunk allowance ${component.bunkAllowance}',
          ];
          return '- ${component.courseName} (${component.componentName}): '
              '${details.join(', ')}';
        })
        .join('\n');
    return 'Low attendance summary:\n$lines';
  }

  String _buildRecoveryAdvice(AttendanceSnapshot snapshot) {
    if (snapshot.lowAttendance.isEmpty) {
      return 'Recovery advice: keep your current attendance stable and avoid '
          'unplanned bunks in subjects with a low remaining allowance.';
    }

    final topRisk = snapshot.lowAttendance.first;
    return 'Recovery advice: prioritize ${topRisk.courseName} '
        '(${topRisk.componentName}) first because it needs '
        '${topRisk.classesNeededForThreshold} more attended classes to cross '
        '${topRisk.threshold}%. After that, work down the remaining low '
        'attendance subjects in the order listed above.';
  }

  String _buildScheduleSummary({
    required AttendanceSnapshot snapshot,
    required DateTime now,
  }) {
    if (snapshot.schedule.entries.isEmpty) {
      return 'Schedule: no cached timetable entries are available right now.';
    }

    final entries =
        List<AttendanceScheduleEntry>.from(snapshot.schedule.entries)
          ..sort((first, second) {
            final firstStart =
                _parseScheduleEntryDateTime(first.lectureDate, first.start) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final secondStart =
                _parseScheduleEntryDateTime(second.lectureDate, second.start) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return firstStart.compareTo(secondStart);
          });

    AttendanceScheduleEntry? currentEntry;
    final upcoming = <AttendanceScheduleEntry>[];
    for (final entry in entries) {
      final start = _parseScheduleEntryDateTime(entry.lectureDate, entry.start);
      final end = _parseScheduleEntryDateTime(entry.lectureDate, entry.end);
      if (start == null) continue;
      if (end != null && !now.isBefore(start) && now.isBefore(end)) {
        currentEntry = entry;
        continue;
      }
      if (start.isAfter(now)) {
        upcoming.add(entry);
      }
    }

    final sections = <String>[];
    if (currentEntry != null) {
      sections.add('Current class: ${_formatScheduleEntry(currentEntry)}.');
    }
    if (upcoming.isNotEmpty) {
      final lines = upcoming
          .take(_maxAiUpcomingClasses)
          .map((entry) => '- ${_formatScheduleEntry(entry)}')
          .join('\n');
      sections.add('Upcoming classes:\n$lines');
    } else if (currentEntry == null) {
      sections.add('Schedule: no upcoming cached classes were found.');
    }

    return sections.join('\n\n');
  }

  DateTime? _parseScheduleEntryDateTime(String rawDate, String rawTime) {
    final baseDate = tryParseDate(rawDate);
    if (baseDate == null) return null;

    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(rawTime);
    if (match == null) return null;

    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) return null;

    return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
  }

  String _formatScheduleEntry(AttendanceScheduleEntry entry) {
    final details = <String>[
      if (entry.courseName.trim().isNotEmpty) entry.courseName.trim(),
      if (entry.courseComponentName.trim().isNotEmpty)
        entry.courseComponentName.trim(),
      if (entry.lectureDate.trim().isNotEmpty)
        formatDateDdMmYyyy(entry.lectureDate),
      if (entry.start.trim().isNotEmpty || entry.end.trim().isNotEmpty)
        '${entry.start.trim()}-${entry.end.trim()}'.replaceAll(
          RegExp(r'^-|-$'),
          '',
        ),
      if (entry.classRoom.trim().isNotEmpty) 'Room ${entry.classRoom.trim()}',
      if (entry.facultyName.trim().isNotEmpty) entry.facultyName.trim(),
    ];
    return details.join(' | ');
  }

  String _formatTimeOfDay(DateTime dateTime) {
    final hour = dateTime.hour == 0
        ? 12
        : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
