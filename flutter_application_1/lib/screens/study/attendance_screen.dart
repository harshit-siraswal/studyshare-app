import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme.dart';
import '../../models/attendance_models.dart';
import '../../services/attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/home_widget_service.dart';
import 'attendance_web_login_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final String collegeId;
  final String collegeName;

  const AttendanceScreen({
    super.key,
    required this.collegeId,
    required this.collegeName,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final AuthService _authService = AuthService();
  final DateFormat _scheduleTileDateFormat = DateFormat('dd/MM/\nyyyy');
  final DateFormat _scheduleTimeFormat = DateFormat('HH:mm');

  AttendanceSnapshot? _snapshot;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isManualSyncing = false;
  bool _isLoadingDaywise = false;
  bool _hasSavedSession = false;
  String? _lastSyncErrorMessage;
  String? _lastSyncErrorCode;
  final Set<String> _projectedMissedEntries = <String>{};
  final Set<String> _expandedProjectionDays = <String>{};

  /// Periodic timer that calls [setState] during an ongoing class so the
  /// [LinearProgressIndicator] in each schedule card updates in real time.
  Timer? _scheduleProgressTimer;

  bool get _isKietCollege => _attendanceService.isKietCollege(
    collegeId: widget.collegeId,
    collegeName: widget.collegeName,
  );

  String get _syncCooldownUntilKey =>
      'attendance_sync_cooldown_until_${widget.collegeId}';

  String get _projectionPrefsKey =>
      'attendance_projection_skips_${widget.collegeId}_${_currentUserEmail ?? 'anonymous'}';

  String? get _currentUserEmail {
    final email = _authService.userEmail?.trim().toLowerCase();
    if (email == null || email.isEmpty) return null;
    return email;
  }

  Future<void> _syncScheduleWidget([AttendanceSnapshot? snapshot]) async {
    final effectiveSnapshot = snapshot ?? _snapshot;
    try {
      await HomeWidgetService.instance.syncSchedule(
        collegeId: widget.collegeId,
        semester: effectiveSnapshot?.student.semesterName ?? '',
        branch: effectiveSnapshot?.student.branchShortName ?? '',
        snapshot: effectiveSnapshot,
      );
    } catch (error) {
      debugPrint('Attendance widget sync failed: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCachedSnapshot();
  }

  @override
  void dispose() {
    _scheduleProgressTimer?.cancel();
    super.dispose();
  }

  /// Starts a 30-second periodic timer that re-renders schedule cards while a
  /// class is currently in progress. Cancels automatically once no class is
  /// ongoing: no-op if the timer is already running.
  void _startScheduleProgressTimerIfNeeded() {
    if (_scheduleProgressTimer?.isActive == true) return;
    _scheduleProgressTimer?.cancel();
    _scheduleProgressTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) {
        _scheduleProgressTimer?.cancel();
        return;
      }
      if (!_hasOngoingClass()) {
        _scheduleProgressTimer?.cancel();
        return;
      }
      setState(() {});
    });
  }

  /// Returns true when the current snapshot contains at least one class that
  /// is actively in session right now (used to gate the progress timer).
  bool _hasOngoingClass() {
    final snapshot = _snapshot;
    if (snapshot == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final entry in snapshot.schedule.entries) {
      final start = _parseEntryDateTime(entry.lectureDate, entry.start);
      final end = _parseEntryDateTime(entry.lectureDate, entry.end);
      if (start == null || end == null) continue;
      if (DateTime(start.year, start.month, start.day) != today) continue;
      if (!now.isBefore(start) && now.isBefore(end)) return true;
    }
    return false;
  }

  Future<void> _loadCachedSnapshot() async {
    if (!_isKietCollege) {
      setState(() => _isLoading = false);
      return;
    }
    final results = await Future.wait<Object?>([
      _attendanceService.loadSavedToken(
        widget.collegeId,
        userEmail: _currentUserEmail,
      ),
      _attendanceService.loadCachedSnapshot(
        widget.collegeId,
        userEmail: _currentUserEmail,
      ),
      _loadSavedProjectedMisses(),
    ]);
    final token = results[0] as String?;
    final snapshot = results[1] as AttendanceSnapshot?;
    final savedProjectedMisses = results[2] as Set<String>;
    final activeProjectedMisses = snapshot == null
        ? <String>{}
        : _filterProjectedMisses(snapshot, savedProjectedMisses);
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _hasSavedSession = token != null && token.trim().isNotEmpty;
      _projectedMissedEntries
        ..clear()
        ..addAll(activeProjectedMisses);
      _isLoading = false;
    });
    if (snapshot != null) {
      _seedProjectionDays(snapshot);
    }
    if (savedProjectedMisses.length != activeProjectedMisses.length) {
      unawaited(_persistProjectedMisses());
    }
    _startScheduleProgressTimerIfNeeded();
    unawaited(_syncScheduleWidget(snapshot));
  }

  Future<void> _connectAndSync() async {
    if (_isSyncing) return;
    if (!await _ensureSyncAllowed(showMessage: true)) return;
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final token = await navigator.push<String>(
      MaterialPageRoute(builder: (_) => const AttendanceWebLoginScreen()),
    );
    if (!mounted || token == null || token.trim().isEmpty) return;

    try {
      await _syncWithToken(token.trim(), isManualSync: true);
    } catch (error) {
      _showSyncError(error);
    }
  }

  bool _isLikelyExpiredSessionError(Object error) {
    if (error is AttendanceSyncException) {
      return error.code == 'session_expired';
    }

    final message = error.toString().toLowerCase();
    return message.contains('401') ||
        message.contains('403') ||
        message.contains('unauthorized') ||
        message.contains('authentication required') ||
        message.contains('invalid token') ||
        message.contains('session expired') ||
        message.contains('reconnect kiet');
  }

  void _showSyncError(Object error) {
    if (!mounted) return;
    final message = error is AttendanceSyncException
        ? error.message
        : error.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _daywiseErrorMessage(Object error) {
    if (error is! AttendanceSyncException) {
      return error.toString().replaceFirst('Exception: ', '');
    }

    return switch (error.code) {
      'session_expired' =>
        'Your KIET session expired. Reconnect and sync attendance to load day-wise records.',
      'invalid_payload' =>
        'Day-wise attendance is temporarily unavailable because KIET returned an invalid subject payload.',
      _ => error.message,
    };
  }

  String _daywiseAttendanceLabel(AttendanceLecture lecture) {
    final normalized = lecture.attendanceStatus.trim();
    if (normalized.isNotEmpty) return normalized;
    return 'Unknown';
  }

  Color _daywiseAttendanceColor(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized.contains('present')) return Colors.green;
    if (normalized.contains('absent')) return Colors.redAccent;
    return AppTheme.primary;
  }

  Future<DateTime?> _loadSyncCooldownUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_syncCooldownUntilKey);
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> _setSyncCooldown(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    await prefs.setInt(_syncCooldownUntilKey, until);
  }

  Future<void> _clearSyncCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_syncCooldownUntilKey);
  }

  Future<bool> _ensureSyncAllowed({bool showMessage = false}) async {
    final cooldownUntil = await _loadSyncCooldownUntil();
    if (cooldownUntil == null || DateTime.now().isAfter(cooldownUntil)) {
      return true;
    }

    if (showMessage && mounted) {
      final remaining = cooldownUntil.difference(DateTime.now());
      final minutes = remaining.inMinutes;
      final seconds = remaining.inSeconds.remainder(60);
      final waitLabel = minutes > 0
          ? '$minutes min ${seconds.toString().padLeft(2, '0')} sec'
          : '$seconds sec';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attendance sync is cooling down. Please wait $waitLabel.',
          ),
        ),
      );
    }
    return false;
  }

  Future<void> _syncWithSavedToken({bool promptIfMissingToken = true}) async {
    if (_isSyncing) return;
    if (!await _ensureSyncAllowed(showMessage: promptIfMissingToken)) return;
    final token = await _attendanceService.loadSavedToken(
      widget.collegeId,
      userEmail: _currentUserEmail,
    );
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() => _hasSavedSession = false);
      if (promptIfMissingToken) {
        await _connectAndSync();
      }
      return;
    }
    setState(() => _hasSavedSession = true);
    try {
      await _syncWithToken(token, isManualSync: true);
    } catch (error) {
      if (_isLikelyExpiredSessionError(error)) {
        await _attendanceService.clearSavedSession(
          widget.collegeId,
          userEmail: _currentUserEmail,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your KIET session expired. Please login once to continue.',
            ),
          ),
        );
        if (promptIfMissingToken) {
          await _connectAndSync();
        }
        return;
      }
      _showSyncError(error);
    }
  }

  Future<void> _logoutKietSession() async {
    await _attendanceService.clearSavedSession(
      widget.collegeId,
      userEmail: _currentUserEmail,
    );
    await _clearSyncCooldown();
    await _clearSavedProjectedMisses();
    if (!mounted) return;
    setState(() {
      _snapshot = null;
      _hasSavedSession = false;
      _lastSyncErrorMessage = null;
      _lastSyncErrorCode = null;
      _projectedMissedEntries.clear();
      _expandedProjectionDays.clear();
    });
    unawaited(_syncScheduleWidget());
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('KIET session cleared.')));
  }

  Future<void> _syncWithToken(
    String token, {
    bool showSuccessToast = true,
    bool isManualSync = false,
  }) async {
    if (_isSyncing) return;
    if (!await _ensureSyncAllowed(showMessage: isManualSync)) return;
    if (isManualSync) {
      setState(() => _isManualSyncing = true);
    }
    setState(() => _isSyncing = true);
    try {
      Future<AttendanceSnapshot> doSync() {
        return _attendanceService.syncKietAttendance(
          collegeId: widget.collegeId,
          collegeName: widget.collegeName,
          cybervidyaToken: token,
          userEmail: _currentUserEmail,
        );
      }

      final snapshot = await doSync();
      await _clearSyncCooldown();
      final savedProjectedMisses = _filterProjectedMisses(
        snapshot,
        await _loadSavedProjectedMisses(),
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _hasSavedSession = true;
        _lastSyncErrorMessage = null;
        _lastSyncErrorCode = null;
        _projectedMissedEntries
          ..clear()
          ..addAll(savedProjectedMisses);
      });
      _seedProjectionDays(snapshot);
      unawaited(_syncScheduleWidget(snapshot));
      if (showSuccessToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KIET attendance synced successfully.')),
        );
      }
    } catch (error) {
      if (error is AttendanceSyncException) {
        if (error.code == 'rate_limited') {
          await _setSyncCooldown(const Duration(minutes: 2));
        } else if (error.code == 'backend_unavailable') {
          await _setSyncCooldown(const Duration(seconds: 45));
        }
        if (mounted) {
          setState(() {
            _lastSyncErrorMessage = error.message;
            _lastSyncErrorCode = error.code;
          });
        }
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          if (isManualSync) _isManualSyncing = false;
        });
      }
    }
  }

  Future<void> _openDaywiseSheet(AttendanceComponent component) async {
    final snapshot = _snapshot;
    final studentId = snapshot?.student.studentId;
    if (snapshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync attendance first to load daywise data.'),
        ),
      );
      return;
    }

    setState(() => _isLoadingDaywise = true);
    try {
      final lectures = await _attendanceService.getDaywiseAttendance(
        collegeId: widget.collegeId,
        component: component,
        studentId: studentId ?? 0,
        userEmail: _currentUserEmail,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${component.courseName} | ${component.componentName}',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: lectures.isEmpty
                          ? Center(
                              child: Text(
                                'No day-wise attendance records were returned for this subject yet.',
                                style: GoogleFonts.inter(
                                  color: isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.lightTextSecondary,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: lectures.length,
                              separatorBuilder: (_, itemIndex) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final lecture = lectures[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    _formatDate(lecture.lectureDate),
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${lecture.dayName} | ${lecture.timeSlot}',
                                    style: GoogleFonts.inter(),
                                  ),
                                  trailing: Text(
                                    _daywiseAttendanceLabel(lecture),
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      color: _daywiseAttendanceColor(
                                        _daywiseAttendanceLabel(lecture),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_daywiseErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _isLoadingDaywise = false);
    }
  }

  String _formatDate(String rawDate) {
    return _attendanceService.formatDateDdMmYyyy(rawDate);
  }

  String _scheduleEntryIdentity(AttendanceScheduleEntry entry) {
    return [
      entry.lectureDate.trim(),
      entry.start.trim(),
      entry.end.trim(),
      entry.courseCode.trim(),
      entry.courseComponentName.trim(),
      entry.classRoom.trim(),
      entry.title.trim(),
      entry.type.trim(),
      entry.facultyName.trim(),
    ].join('|');
  }

  String _projectionBucketKeyForEntry(AttendanceScheduleEntry entry) {
    return [
      entry.courseCode.trim().toLowerCase(),
      entry.courseComponentName.trim().toLowerCase(),
    ].join('|');
  }

  String _projectionBucketKeyForComponent(AttendanceComponent component) {
    return [
      component.courseCode.trim().toLowerCase(),
      component.componentName.trim().toLowerCase(),
    ].join('|');
  }

  bool _isClassEntry(AttendanceScheduleEntry entry) {
    return entry.type.trim().toUpperCase() != 'HOLIDAY';
  }

  void _seedProjectionDays(AttendanceSnapshot snapshot) {
    if (_expandedProjectionDays.isNotEmpty) return;
    for (final entry in _upcomingScheduleEntries(snapshot)) {
      if (!_isClassEntry(entry)) continue;
      _expandedProjectionDays.add(_formatDate(entry.lectureDate));
      break;
    }
  }

  Future<Set<String>> _loadSavedProjectedMisses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_projectionPrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <String>{};
      }
      return decoded
          .map((value) => value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _persistProjectedMisses() async {
    final prefs = await SharedPreferences.getInstance();
    if (_projectedMissedEntries.isEmpty) {
      await prefs.remove(_projectionPrefsKey);
      return;
    }
    final values = _projectedMissedEntries.toList()..sort();
    await prefs.setString(_projectionPrefsKey, jsonEncode(values));
  }

  Future<void> _clearSavedProjectedMisses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_projectionPrefsKey);
  }

  Set<String> _filterProjectedMisses(
    AttendanceSnapshot snapshot,
    Set<String> persisted,
  ) {
    if (persisted.isEmpty) return <String>{};
    final activeEntries = _upcomingScheduleEntries(
      snapshot,
    ).where(_isClassEntry).map(_scheduleEntryIdentity).toSet();
    return persisted.where(activeEntries.contains).toSet();
  }

  DateTime? _tryParseFlexibleDateTime(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return null;
    final direct = DateTime.tryParse(normalized);
    if (direct != null) return direct;

    const patterns = <String>[
      'dd/MM/yyyy HH:mm:ss',
      'dd/MM/yyyy HH:mm',
      'dd-MM-yyyy HH:mm:ss',
      'dd-MM-yyyy HH:mm',
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm',
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'yyyy-MM-dd',
    ];

    for (final pattern in patterns) {
      try {
        return DateFormat(pattern).parseLoose(normalized);
      } catch (_) {}
    }
    return null;
  }

  ({int hour, int minute, int second})? _extractTimeParts(String rawTime) {
    final normalized = rawTime.trim();
    if (normalized.isEmpty) return null;
    final directDateTime = _tryParseFlexibleDateTime(normalized);
    if (directDateTime != null) {
      return (
        hour: directDateTime.hour,
        minute: directDateTime.minute,
        second: directDateTime.second,
      );
    }

    final match = RegExp(
      r'(\d{1,2})\s*:\s*(\d{2})(?:\s*:\s*(\d{2}))?',
    ).firstMatch(normalized);
    if (match == null) return null;
    return (
      hour: int.tryParse(match.group(1) ?? '0') ?? 0,
      minute: int.tryParse(match.group(2) ?? '0') ?? 0,
      second: int.tryParse(match.group(3) ?? '0') ?? 0,
    );
  }

  DateTime? _parseEntryDateTime(String rawDate, String rawTime) {
    final timeAsDateTime = _tryParseFlexibleDateTime(rawTime);
    if (timeAsDateTime != null &&
        (rawDate.trim().isEmpty ||
            rawTime.contains('/') ||
            rawTime.contains('-'))) {
      return timeAsDateTime;
    }

    final baseDate =
        _attendanceService.tryParseDate(rawDate) ??
        _tryParseFlexibleDateTime(rawDate);
    if (baseDate == null) {
      return timeAsDateTime;
    }

    final timeParts = _extractTimeParts(rawTime);
    if (timeParts == null) {
      return DateTime(baseDate.year, baseDate.month, baseDate.day);
    }

    return DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      timeParts.hour,
      timeParts.minute,
      timeParts.second,
    );
  }

  String _formatScheduleDateLabel(AttendanceScheduleEntry entry) {
    final date =
        _parseEntryDateTime(entry.lectureDate, entry.start) ??
        _attendanceService.tryParseDate(entry.lectureDate) ??
        _tryParseFlexibleDateTime(entry.lectureDate);
    if (date == null) {
      return _formatDate(entry.lectureDate).replaceAll('/', '/\n');
    }
    return _scheduleTileDateFormat.format(date);
  }

  String _formatScheduleTimeLabel(DateTime? dateTime, String fallback) {
    if (dateTime != null) {
      return _scheduleTimeFormat.format(dateTime);
    }
    final timeParts = _extractTimeParts(fallback);
    if (timeParts != null) {
      return '${timeParts.hour.toString().padLeft(2, '0')}:${timeParts.minute.toString().padLeft(2, '0')}';
    }
    return fallback.trim();
  }

  String _formatScheduleTimeRange(AttendanceScheduleEntry entry) {
    final startLabel = _formatScheduleTimeLabel(
      _parseEntryDateTime(entry.lectureDate, entry.start),
      entry.start,
    );
    final endLabel = _formatScheduleTimeLabel(
      _parseEntryDateTime(entry.lectureDate, entry.end),
      entry.end,
    );
    return '$startLabel - $endLabel';
  }

  int _additionalClassesCanMiss({
    required int present,
    required int total,
    required int threshold,
  }) {
    if (total <= 0) return 0;
    final thresholdRatio = threshold / 100;
    final remaining = (present - (thresholdRatio * total)) / thresholdRatio;
    return remaining.isFinite ? remaining.floor().clamp(0, 100000) : 0;
  }

  int _classesNeededToRecover({
    required int present,
    required int total,
    required int threshold,
  }) {
    if (total <= 0) return 0;
    final thresholdRatio = threshold / 100;
    final required =
        ((thresholdRatio * total) - present) / (1 - thresholdRatio);
    if (!required.isFinite) return 0;
    return required.ceil().clamp(0, 100000);
  }

  Map<String, int> _projectedMissCountByComponent(AttendanceSnapshot snapshot) {
    final counts = <String, int>{};
    for (final entry in _upcomingScheduleEntries(
      snapshot,
    ).where(_isClassEntry)) {
      final identity = _scheduleEntryIdentity(entry);
      if (!_projectedMissedEntries.contains(identity)) continue;
      final key = _projectionBucketKeyForEntry(entry);
      counts.update(key, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Map<String, int> _scheduledClassCountByComponent(
    AttendanceSnapshot snapshot,
  ) {
    final counts = <String, int>{};
    for (final entry in _upcomingScheduleEntries(
      snapshot,
    ).where(_isClassEntry)) {
      final key = _projectionBucketKeyForEntry(entry);
      counts.update(key, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  _AttendanceProjectionSummary _buildProjectedSummary(
    AttendanceComponent component, {
    int projectedMisses = 0,
    int scheduledFutureClasses = 0,
  }) {
    final present = component.attendedClasses;
    final plannedAttendances = math.max(
      0,
      scheduledFutureClasses - projectedMisses,
    );
    final total = math.max(
      component.totalClasses,
      component.totalClasses + scheduledFutureClasses,
    );
    final projectedPresent = math.min(total, present + plannedAttendances);
    final percentage = total <= 0 ? 0.0 : (projectedPresent / total) * 100;
    final safe = percentage >= component.threshold;
    final classesToSafety = safe
        ? _additionalClassesCanMiss(
            present: projectedPresent,
            total: total,
            threshold: component.threshold,
          )
        : _classesNeededToRecover(
            present: projectedPresent,
            total: total,
            threshold: component.threshold,
          );

    final message = total <= 0
        ? 'No classes held yet.'
        : safe
        ? classesToSafety > 0
              ? 'You can still miss $classesToSafety more class${classesToSafety == 1 ? '' : 'es'} and stay above ${component.threshold}%.'
              : 'Try not to miss any more classes.'
        : 'Need to attend next $classesToSafety class${classesToSafety == 1 ? '' : 'es'} to reach ${component.threshold}%.';

    return _AttendanceProjectionSummary(
      percentage: percentage,
      projectedTotal: total,
      projectedPresent: projectedPresent,
      projectedMisses: projectedMisses,
      isSafe: safe,
      message: message,
    );
  }

  List<AttendanceScheduleEntry> _dedupeCalendarEntries(
    List<AttendanceScheduleEntry> entries,
  ) {
    final seen = <String>{};
    final unique = <AttendanceScheduleEntry>[];
    for (final entry in entries.where(_isClassEntry)) {
      final start = _parseEntryDateTime(entry.lectureDate, entry.start);
      final end =
          _parseEntryDateTime(entry.lectureDate, entry.end) ??
          start?.add(const Duration(hours: 1));
      final key = [
        entry.courseCode.trim().toLowerCase(),
        entry.courseComponentName.trim().toLowerCase(),
        _formatScheduleDateLabel(entry),
        _formatScheduleTimeLabel(start, entry.start),
        _formatScheduleTimeLabel(end, entry.end),
      ].join('|');
      if (seen.add(key)) {
        unique.add(entry);
      }
    }
    return unique;
  }

  Event? _buildNativeCalendarEvent(AttendanceScheduleEntry entry) {
    final start = _parseEntryDateTime(entry.lectureDate, entry.start);
    if (start == null) return null;
    final end =
        _parseEntryDateTime(entry.lectureDate, entry.end) ??
        start.add(const Duration(hours: 1));
    final safeEnd = end.isAfter(start)
        ? end
        : start.add(const Duration(hours: 1));
    final title = entry.courseName.trim().isNotEmpty
        ? entry.courseName.trim()
        : (entry.title.trim().isNotEmpty ? entry.title.trim() : 'Class');
    final details = <String>[
      if (entry.courseCode.trim().isNotEmpty)
        'Course Code: ${entry.courseCode.trim()}',
      if (entry.courseComponentName.trim().isNotEmpty)
        'Component: ${entry.courseComponentName.trim()}',
      if (entry.facultyName.trim().isNotEmpty)
        'Faculty: ${entry.facultyName.trim()}',
      'Created from StudyShare weekly schedule',
    ].join('\n');

    return Event(
      title: title,
      description: details,
      location: entry.classRoom.trim().isEmpty ? null : entry.classRoom.trim(),
      startDate: start,
      endDate: safeEnd,
      recurrence: Recurrence(frequency: Frequency.weekly),
    );
  }

  Future<void> _addEntriesToCalendar(
    List<AttendanceScheduleEntry> entries,
  ) async {
    final events = _dedupeCalendarEntries(
      entries,
    ).map(_buildNativeCalendarEvent).whereType<Event>().toList(growable: false);
    if (events.isEmpty) return;
    if (!mounted) return;
    try {
      for (final event in events) {
        Add2Calendar.addEvent2Cal(event);
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open your calendar app: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  _AttendanceOverviewProjectionSummary _buildOverallProjectionSummary(
    AttendanceSnapshot snapshot,
  ) {
    final futureClasses = _upcomingScheduleEntries(
      snapshot,
    ).where(_isClassEntry).toList(growable: false);
    final scheduledFutureClasses = futureClasses.length;
    final skippedClasses = futureClasses
        .where(
          (entry) =>
              _projectedMissedEntries.contains(_scheduleEntryIdentity(entry)),
        )
        .length;
    final plannedAttendances = math.max(
      0,
      scheduledFutureClasses - skippedClasses,
    );
    final projectedTotal =
        snapshot.overall.totalClasses + scheduledFutureClasses;
    final projectedPresent =
        snapshot.overall.presentClasses + plannedAttendances;
    final projectedPercentage = projectedTotal <= 0
        ? 0.0
        : (projectedPresent / projectedTotal) * 100;

    final message = scheduledFutureClasses == 0
        ? 'No upcoming classes are available for projection right now.'
        : skippedClasses > 0
        ? 'Projected from $scheduledFutureClasses upcoming class${scheduledFutureClasses == 1 ? '' : 'es'}, with $skippedClasses marked to skip.'
        : 'Projected assuming you attend the next $scheduledFutureClasses scheduled class${scheduledFutureClasses == 1 ? '' : 'es'}.';

    return _AttendanceOverviewProjectionSummary(
      actualPercentage: snapshot.overall.percentage,
      projectedPercentage: projectedPercentage,
      actualPresent: snapshot.overall.presentClasses,
      actualTotal: snapshot.overall.totalClasses,
      projectedPresent: projectedPresent,
      projectedTotal: projectedTotal,
      scheduledFutureClasses: scheduledFutureClasses,
      skippedClasses: skippedClasses,
      message: message,
    );
  }

  void _toggleProjectedMiss(AttendanceScheduleEntry entry) {
    final identity = _scheduleEntryIdentity(entry);
    setState(() {
      if (_projectedMissedEntries.contains(identity)) {
        _projectedMissedEntries.remove(identity);
      } else {
        _projectedMissedEntries.add(identity);
      }
    });
    unawaited(_persistProjectedMisses());
  }

  void _toggleProjectedDayEntries(
    List<AttendanceScheduleEntry> entries, {
    required bool shouldSelect,
  }) {
    setState(() {
      for (final entry in entries) {
        final identity = _scheduleEntryIdentity(entry);
        if (shouldSelect) {
          _projectedMissedEntries.add(identity);
        } else {
          _projectedMissedEntries.remove(identity);
        }
      }
    });
    unawaited(_persistProjectedMisses());
  }

  Map<String, List<AttendanceScheduleEntry>> _groupScheduleEntries(
    List<AttendanceScheduleEntry> entries,
  ) {
    final grouped = <String, List<AttendanceScheduleEntry>>{};
    for (final entry in entries) {
      final key = _formatDate(entry.lectureDate);
      grouped.putIfAbsent(key, () => <AttendanceScheduleEntry>[]).add(entry);
    }
    return grouped;
  }

  List<AttendanceScheduleEntry> _upcomingScheduleEntries(
    AttendanceSnapshot snapshot,
  ) {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final entries =
        List<AttendanceScheduleEntry>.from(snapshot.schedule.entries)
          ..sort((a, b) {
            final aDate =
                _attendanceService.tryParseDate(a.lectureDate) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                _attendanceService.tryParseDate(b.lectureDate) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final dateCmp = aDate.compareTo(bDate);
            if (dateCmp != 0) return dateCmp;
            return a.start.compareTo(b.start);
          });

    final weekStart = _attendanceService.tryParseDate(
      snapshot.schedule.weekStartDate,
    );
    final weekEnd = _attendanceService.tryParseDate(
      snapshot.schedule.weekEndDate,
    );

    final upcoming = entries.where((entry) {
      final parsed = _attendanceService.tryParseDate(entry.lectureDate);
      if (parsed == null) return false;
      final dayDate = DateTime(parsed.year, parsed.month, parsed.day);
      if (weekStart != null && dayDate.isBefore(weekStart)) return false;
      if (weekEnd != null && dayDate.isAfter(weekEnd)) return false;
      if (dayDate.isBefore(startOfToday)) return false;

      final entryEnd = _parseEntryDateTime(entry.lectureDate, entry.end);
      if (entryEnd != null) {
        return !entryEnd.isBefore(today);
      }

      return true;
    }).toList();

    return upcoming;
  }

  List<AttendanceScheduleEntry> _weeklyScheduleEntries(
    AttendanceSnapshot snapshot,
  ) {
    final entries =
        List<AttendanceScheduleEntry>.from(snapshot.schedule.entries)
          ..sort((a, b) {
            final aDate =
                _attendanceService.tryParseDate(a.lectureDate) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                _attendanceService.tryParseDate(b.lectureDate) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final dateCmp = aDate.compareTo(bDate);
            if (dateCmp != 0) return dateCmp;
            return a.start.compareTo(b.start);
          });
    final weekStart = _attendanceService.tryParseDate(
      snapshot.schedule.weekStartDate,
    );
    final weekEnd = _attendanceService.tryParseDate(
      snapshot.schedule.weekEndDate,
    );
    if (weekStart == null && weekEnd == null) return entries;

    return entries.where((entry) {
      final parsed = _attendanceService.tryParseDate(entry.lectureDate);
      if (parsed == null) return false;
      final dayDate = DateTime(parsed.year, parsed.month, parsed.day);
      if (weekStart != null && dayDate.isBefore(weekStart)) return false;
      if (weekEnd != null && dayDate.isAfter(weekEnd)) return false;
      return true;
    }).toList();
  }

  Future<void> _openWeeklyScheduleSheet() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    final entries = _upcomingScheduleEntries(
      snapshot,
    ).where(_isClassEntry).toList();
    final groupedEntries = _groupScheduleEntries(entries);
    final allEntries = _weeklyScheduleEntries(
      snapshot,
    ).where(_isClassEntry).toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final expandedDays = <String>{
          if (groupedEntries.isNotEmpty) groupedEntries.keys.first,
        };
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Weekly Schedule',
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? AppTheme.darkTextPrimary
                                        : AppTheme.lightTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_formatDate(snapshot.schedule.weekStartDate)} - ${_formatDate(snapshot.schedule.weekEndDate)}',
                                  style: GoogleFonts.inter(
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: allEntries.isEmpty
                                ? null
                                : () => _addEntriesToCalendar(allEntries),
                            icon: const Icon(
                              Icons.event_available_rounded,
                              size: 18,
                            ),
                            label: Text(
                              'Add',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (entries.isNotEmpty) ...[
                                _buildProjectionPlanner(
                                  entries: entries,
                                  isDark: isDark,
                                  onStateChanged: () {
                                    if (!mounted) return;
                                    setModalState(() {});
                                  },
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Upcoming Classes This Week',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? AppTheme.darkTextPrimary
                                        : AppTheme.lightTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (entries.isEmpty)
                                Center(
                                  child: Text(
                                    'No upcoming classes this week.',
                                    style: GoogleFonts.inter(
                                      color: isDark
                                          ? AppTheme.darkTextSecondary
                                          : AppTheme.lightTextSecondary,
                                    ),
                                  ),
                                )
                              else
                                ...groupedEntries.entries.map((group) {
                                  final dayKey = group.key;
                                  final dayEntries = group.value
                                      .where(_isClassEntry)
                                      .toList();
                                  final expanded = expandedDays.contains(
                                    dayKey,
                                  );
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.04,
                                              )
                                            : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white10
                                              : Colors.black12,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            onTap: () {
                                              setModalState(() {
                                                if (expanded) {
                                                  expandedDays.remove(dayKey);
                                                } else {
                                                  expandedDays.add(dayKey);
                                                }
                                              });
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    16,
                                                    14,
                                                    16,
                                                    14,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          dayKey,
                                                          style: GoogleFonts.inter(
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: isDark
                                                                ? AppTheme
                                                                      .darkTextPrimary
                                                                : AppTheme
                                                                      .lightTextPrimary,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          '${dayEntries.length} class${dayEntries.length == 1 ? '' : 'es'} | ${dayEntries.first.start} - ${dayEntries.last.end}',
                                                          style: GoogleFonts.inter(
                                                            fontSize: 12.4,
                                                            color: isDark
                                                                ? AppTheme
                                                                      .darkTextSecondary
                                                                : AppTheme
                                                                      .lightTextSecondary,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Icon(
                                                    expanded
                                                        ? Icons
                                                              .keyboard_arrow_up_rounded
                                                        : Icons
                                                              .keyboard_arrow_down_rounded,
                                                    color: isDark
                                                        ? AppTheme
                                                              .darkTextSecondary
                                                        : AppTheme
                                                              .lightTextSecondary,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (expanded)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    12,
                                                    0,
                                                    12,
                                                    12,
                                                  ),
                                              child: Column(
                                                children: dayEntries
                                                    .map((entry) {
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              bottom: 10,
                                                            ),
                                                        child:
                                                            _buildScheduleEntryCard(
                                                              entry,
                                                              isDark,
                                                              showDate: false,
                                                            ),
                                                      );
                                                    })
                                                    .toList(growable: false),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(
          'Attendance',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        actions: _isKietCollege
            ? [
                IconButton(
                  tooltip: 'Weekly schedule',
                  onPressed: _snapshot == null
                      ? null
                      : _openWeeklyScheduleSheet,
                  icon: const Icon(Icons.calendar_month_rounded),
                ),
                IconButton(
                  tooltip: 'Sync now',
                  onPressed: _isManualSyncing ? null : _syncWithSavedToken,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                ),
                IconButton(
                  tooltip: 'Log out',
                  onPressed: _isManualSyncing || !_hasSavedSession
                      ? null
                      : _logoutKietSession,
                  icon: const Icon(Icons.logout_rounded),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildBody(isDark),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (!_isKietCollege) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance is currently available only for KIET.',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Switch to KIET in the college selector to use attendance sync and attendance insights.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.4,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
        ],
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      return ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF121826) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.fact_check_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Connect your KIET ERP session',
                  style: GoogleFonts.inter(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'StudyShare opens the official KIET ERP page, waits for the authenticated home state, and uses your session token to bring attendance and timetable into one place.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.5,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.035),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Attendance sync can take 1-2 minutes after login. If the KIET server is busy, StudyShare will keep your last synced snapshot and let you retry after a short cooldown.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.45,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.lightTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _isManualSyncing ? null : _connectAndSync,
                  icon: const Icon(Icons.login_rounded),
                  label: Text(
                    _isSyncing ? 'Syncing...' : 'Connect KIET ERP',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_hasSavedSession) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isManualSyncing
                        ? null
                        : () =>
                              _syncWithSavedToken(promptIfMissingToken: false),
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Refresh with saved session'),
                  ),
                ],
              ],
            ),
          ),
          if (_lastSyncErrorMessage != null) ...[
            const SizedBox(height: 16),
            _buildSyncStatusBanner(isDark),
          ],
        ],
      );
    }

    final upcomingEntries = _upcomingScheduleEntries(
      snapshot,
    ).where(_isClassEntry).toList();
    final weeklyEntries = _weeklyScheduleEntries(
      snapshot,
    ).where(_isClassEntry).toList(growable: false);
    final projectedMissCounts = _projectedMissCountByComponent(snapshot);
    final scheduledClassCounts = _scheduledClassCountByComponent(snapshot);

    return RefreshIndicator(
      onRefresh: _syncWithSavedToken,
      child: ListView(
        children: [
          _buildOverviewCard(snapshot, isDark),
          if (_lastSyncErrorMessage != null) ...[
            const SizedBox(height: 14),
            _buildSyncStatusBanner(isDark),
          ],
          const SizedBox(height: 16),
          if (snapshot.lowAttendance.isNotEmpty) ...[
            _buildLowAttendanceCard(snapshot, isDark),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 4),
          Text(
            'Subjects',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...snapshot.courses.expand(
            (course) => course.components.map(
              (component) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildComponentCard(
                  component,
                  isDark,
                  projectedMisses:
                      projectedMissCounts[_projectionBucketKeyForComponent(
                        component,
                      )] ??
                      0,
                  scheduledFutureClasses:
                      scheduledClassCounts[_projectionBucketKeyForComponent(
                        component,
                      )] ??
                      0,
                ),
              ),
            ),
          ),
          if (upcomingEntries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Upcoming Classes',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.lightTextPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _addEntriesToCalendar(weeklyEntries),
                  icon: const Icon(Icons.event_available_rounded, size: 18),
                  label: Text(
                    'Add to Calendar',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...upcomingEntries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildScheduleEntryCard(entry, isDark),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewCard(AttendanceSnapshot snapshot, bool isDark) {
    final summary = _buildOverallProjectionSummary(snapshot);
    final displayPercentage = summary.projectedPercentage;
    final alert = displayPercentage < AttendanceService.lowAttendanceThreshold;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101827) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current standing',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.24,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.student.fullName,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${snapshot.student.branchShortName} | ${snapshot.student.semesterName} | ${snapshot.student.sectionName}',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: alert
                  ? Colors.redAccent.withValues(alpha: isDark ? 0.15 : 0.08)
                  : Colors.green.withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${displayPercentage.toStringAsFixed(2)}%',
                  style: GoogleFonts.inter(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: alert ? Colors.redAccent : Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Actual ${summary.actualPercentage.toStringAsFixed(2)}% from CyberVidya',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  summary.message,
                  style: GoogleFonts.inter(
                    fontSize: 12.4,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildOverviewStat(
                label: 'Actual',
                value: '${summary.actualPresent}/${summary.actualTotal}',
                isDark: isDark,
              ),
              _buildOverviewStat(
                label: 'Projected',
                value: '${summary.projectedPresent}/${summary.projectedTotal}',
                isDark: isDark,
              ),
              _buildOverviewStat(
                label: 'Last synced',
                value: _formatSyncTime(snapshot.syncedAt),
                isDark: isDark,
              ),
              if (summary.skippedClasses > 0)
                _buildOverviewStat(
                  label: 'Skipped',
                  value: summary.skippedClasses.toString(),
                  isDark: isDark,
                ),
              _buildOverviewStat(
                label: 'Low subjects',
                value: snapshot.lowAttendance.length.toString(),
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Read this number first. Everything below helps you decide what to recover next and which classes you cannot afford to miss.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.4,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLowAttendanceCard(AttendanceSnapshot snapshot, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A1A1A) : const Color(0xFFFFEFEF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Low attendance alert',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Focus on these first. Each card tells you exactly how many classes you need to attend to get back to safety.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.45,
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ...snapshot.lowAttendance.map(
            (component) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      component.courseName,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${component.componentName} | ${component.percentage.toStringAsFixed(2)}%',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Attend ${component.classesNeededForThreshold} more classes to reach ${component.threshold}%.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.45,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectionPlanner({
    required List<AttendanceScheduleEntry> entries,
    required bool isDark,
    VoidCallback? onStateChanged,
  }) {
    final groupedEntries = _groupScheduleEntries(entries);
    final selectedCount = entries
        .where(
          (entry) =>
              _projectedMissedEntries.contains(_scheduleEntryIdentity(entry)),
        )
        .length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Projection Planner',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use the upcoming schedule to see how planned misses '
                      'change each subject before the week hits you.',
                      style: GoogleFonts.inter(
                        fontSize: 12.8,
                        height: 1.45,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selectedCount > 0)
                TextButton.icon(
                  onPressed: () {
                    setState(() => _projectedMissedEntries.clear());
                    unawaited(_persistProjectedMisses());
                    onStateChanged?.call();
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: Text(
                    'Reset',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (groupedEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No upcoming classes are available for projection right now.',
                style: GoogleFonts.inter(
                  fontSize: 12.6,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Column(
                  children: groupedEntries.entries
                      .map((group) {
                        final dayEntries = group.value
                            .where(_isClassEntry)
                            .toList();
                        if (dayEntries.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final dayKey = group.key;
                        final expanded = _expandedProjectionDays.contains(
                          dayKey,
                        );
                        final selectedForDay = dayEntries
                            .where(
                              (entry) => _projectedMissedEntries.contains(
                                _scheduleEntryIdentity(entry),
                              ),
                            )
                            .length;
                        final allSelected = selectedForDay == dayEntries.length;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.black12,
                              ),
                            ),
                            child: Column(
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    setState(() {
                                      if (expanded) {
                                        _expandedProjectionDays.remove(dayKey);
                                      } else {
                                        _expandedProjectionDays.add(dayKey);
                                      }
                                    });
                                    onStateChanged?.call();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      14,
                                      16,
                                      14,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                dayKey,
                                                style: GoogleFonts.inter(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: isDark
                                                      ? AppTheme.darkTextPrimary
                                                      : AppTheme
                                                            .lightTextPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${dayEntries.length} class${dayEntries.length == 1 ? '' : 'es'} | '
                                                '${dayEntries.first.start} - ${dayEntries.last.end}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12.4,
                                                  color: isDark
                                                      ? AppTheme
                                                            .darkTextSecondary
                                                      : AppTheme
                                                            .lightTextSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (selectedForDay > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withValues(
                                                alpha: 0.14,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              '$selectedForDay skipped',
                                              style: GoogleFonts.inter(
                                                fontSize: 11.2,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.orange.shade700,
                                              ),
                                            ),
                                          ),
                                        const SizedBox(width: 10),
                                        Icon(
                                          expanded
                                              ? Icons.keyboard_arrow_up_rounded
                                              : Icons
                                                    .keyboard_arrow_down_rounded,
                                          color: isDark
                                              ? AppTheme.darkTextSecondary
                                              : AppTheme.lightTextSecondary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (expanded)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      16,
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            TextButton.icon(
                                              onPressed: () {
                                                _toggleProjectedDayEntries(
                                                  dayEntries,
                                                  shouldSelect: !allSelected,
                                                );
                                                onStateChanged?.call();
                                              },
                                              icon: Icon(
                                                allSelected
                                                    ? Icons.check_box_rounded
                                                    : Icons
                                                          .check_box_outline_blank_rounded,
                                                size: 18,
                                              ),
                                              label: Text(
                                                allSelected
                                                    ? 'Unmark day'
                                                    : 'Mark day as skipped',
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        ...dayEntries.map((entry) {
                                          final identity =
                                              _scheduleEntryIdentity(entry);
                                          final isSelected =
                                              _projectedMissedEntries.contains(
                                                identity,
                                              );
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 10,
                                            ),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              onTap: () {
                                                _toggleProjectedMiss(entry);
                                                onStateChanged?.call();
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  14,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? Colors.orange
                                                            .withValues(
                                                              alpha: isDark
                                                                  ? 0.16
                                                                  : 0.10,
                                                            )
                                                      : (isDark
                                                            ? Colors.white
                                                                  .withValues(
                                                                    alpha: 0.03,
                                                                  )
                                                            : Colors.white),
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? Colors.orange
                                                              .withValues(
                                                                alpha: 0.3,
                                                              )
                                                        : (isDark
                                                              ? Colors.white10
                                                              : Colors.black12),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      isSelected
                                                          ? Icons
                                                                .check_circle_rounded
                                                          : Icons
                                                                .radio_button_unchecked_rounded,
                                                      color: isSelected
                                                          ? Colors
                                                                .orange
                                                                .shade700
                                                          : (isDark
                                                                ? AppTheme
                                                                      .darkTextSecondary
                                                                : AppTheme
                                                                      .lightTextSecondary),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            entry.courseName
                                                                    .trim()
                                                                    .isNotEmpty
                                                                ? entry
                                                                      .courseName
                                                                      .trim()
                                                                : entry.title
                                                                      .trim(),
                                                            style: GoogleFonts.inter(
                                                              fontSize: 13.8,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: isDark
                                                                  ? AppTheme
                                                                        .darkTextPrimary
                                                                  : AppTheme
                                                                        .lightTextPrimary,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          Text(
                                                            '${_formatScheduleTimeRange(entry)}${entry.classRoom.trim().isEmpty ? '' : ' | Room ${entry.classRoom.trim()}'}',
                                                            style: GoogleFonts.inter(
                                                              fontSize: 12.2,
                                                              color: isDark
                                                                  ? AppTheme
                                                                        .darkTextSecondary
                                                                  : AppTheme
                                                                        .lightTextSecondary,
                                                            ),
                                                          ),
                                                          if (entry
                                                              .courseComponentName
                                                              .trim()
                                                              .isNotEmpty) ...[
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text(
                                                              entry
                                                                  .courseComponentName
                                                                  .trim(),
                                                              style: GoogleFonts.inter(
                                                                fontSize: 11.8,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: AppTheme
                                                                    .primary,
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComponentCard(
    AttendanceComponent component,
    bool isDark, {
    int projectedMisses = 0,
    int scheduledFutureClasses = 0,
  }) {
    final summary = _buildProjectedSummary(
      component,
      projectedMisses: projectedMisses,
      scheduledFutureClasses: scheduledFutureClasses,
    );
    final accent = summary.isSafe ? Colors.green : Colors.redAccent;
    final isProjected = projectedMisses > 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      component.courseName,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${component.componentName} | ${component.courseCode}',
                      style: GoogleFonts.inter(
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${summary.percentage.toStringAsFixed(2)}%',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: (summary.percentage / 100).clamp(0.0, 1.0),
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildComponentStatChip(
                label: 'Attended',
                value: '${summary.projectedPresent}/${summary.projectedTotal}',
                isDark: isDark,
              ),
              _buildComponentStatChip(
                label: 'Extra',
                value: '${component.extraAttendance}',
                isDark: isDark,
              ),
              if (isProjected)
                _buildComponentStatChip(
                  label: 'Skipped',
                  value: '$projectedMisses',
                  isDark: isDark,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isProjected
                      ? 'Projection'
                      : (summary.isSafe ? 'Safe zone' : 'Next action'),
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.16,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  summary.message,
                  style: GoogleFonts.inter(
                    fontSize: 12.8,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
                if (isProjected) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Based on the classes marked as skipped in the planner above.',
                    style: GoogleFonts.inter(
                      fontSize: 11.4,
                      height: 1.35,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _isLoadingDaywise
                  ? null
                  : () => _openDaywiseSheet(component),
              icon: const Icon(Icons.calendar_view_day_rounded),
              label: Text(
                'Daywise',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewStat({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.lightTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentStatChip({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        ),
      ),
    );
  }

  Widget _buildScheduleEntryCard(
    AttendanceScheduleEntry entry,
    bool isDark, {
    bool showDate = true,
  }) {
    final now = DateTime.now();
    final classStart = _parseEntryDateTime(entry.lectureDate, entry.start);
    final classEnd = _parseEntryDateTime(entry.lectureDate, entry.end);
    final entryDate =
        classStart ??
        _attendanceService.tryParseDate(entry.lectureDate) ??
        _tryParseFlexibleDateTime(entry.lectureDate);
    final today = DateTime(now.year, now.month, now.day);
    final isToday =
        entryDate != null &&
        DateTime(entryDate.year, entryDate.month, entryDate.day) == today;
    final startLabel = _formatScheduleTimeLabel(classStart, entry.start);
    final endLabel = _formatScheduleTimeLabel(classEnd, entry.end);
    final dateLabel = _formatScheduleDateLabel(entry);

    final isOngoing =
        isToday &&
        classStart != null &&
        classEnd != null &&
        !now.isBefore(classStart) &&
        now.isBefore(classEnd);
    final isPast = classEnd != null && now.isAfter(classEnd);
    double progress = 0.0;
    if (isOngoing) {
      final totalSecs = classEnd.difference(classStart).inSeconds.toDouble();
      final elapsedSecs = now.difference(classStart).inSeconds.toDouble();
      progress = (totalSecs > 0 ? elapsedSecs / totalSecs : 0.0).clamp(
        0.0,
        1.0,
      );
    }

    final accentColor = isOngoing ? Colors.green : AppTheme.primary;
    final title = entry.courseName.isEmpty
        ? (entry.title.isEmpty ? 'Class' : entry.title)
        : entry.courseName;
    final location = entry.classRoom.isEmpty
        ? 'Classroom TBA'
        : entry.classRoom;
    final surfaceColor = isDark
        ? const Color(0xFF111827)
        : const Color(0xFFF1F5F9);
    final shellTopColor = isDark ? const Color(0xFF182334) : Colors.white;
    final shellBottomColor = isDark
        ? const Color(0xFF0B1422)
        : const Color(0xFFE2E8F0);
    final softBorderColor = isOngoing
        ? accentColor.withValues(alpha: isDark ? 0.30 : 0.22)
        : (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.85));
    final cardShadows = isDark
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              offset: const Offset(10, 10),
              blurRadius: 24,
              spreadRadius: -10,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.05),
              offset: const Offset(-8, -8),
              blurRadius: 22,
              spreadRadius: -12,
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFD6DEE8).withValues(alpha: 0.95),
              offset: const Offset(10, 10),
              blurRadius: 22,
              spreadRadius: -10,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.98),
              offset: const Offset(-8, -8),
              blurRadius: 20,
              spreadRadius: -10,
            ),
          ];
    final innerSurfaceColor = Color.alphaBlend(
      isDark
          ? Colors.white.withValues(alpha: 0.03)
          : Colors.white.withValues(alpha: 0.78),
      surfaceColor,
    );
    final timeTileColor = Color.alphaBlend(
      accentColor.withValues(alpha: isDark ? 0.14 : 0.10),
      innerSurfaceColor,
    );
    final insetShadows = isDark
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              offset: const Offset(6, 6),
              blurRadius: 14,
              spreadRadius: -8,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.04),
              offset: const Offset(-4, -4),
              blurRadius: 12,
              spreadRadius: -8,
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFD9E1EA).withValues(alpha: 0.9),
              offset: const Offset(5, 5),
              blurRadius: 12,
              spreadRadius: -8,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.95),
              offset: const Offset(-4, -4),
              blurRadius: 12,
              spreadRadius: -8,
            ),
          ];

    return Opacity(
      opacity: isPast ? 0.55 : 1.0,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: cardShadows,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [shellTopColor, shellBottomColor],
              ),
              color: surfaceColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: softBorderColor,
                width: isOngoing ? 1.4 : 1,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 82,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.alphaBlend(
                                accentColor.withValues(
                                  alpha: isDark ? 0.16 : 0.12,
                                ),
                                timeTileColor,
                              ),
                              timeTileColor,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: accentColor.withValues(
                              alpha: isDark ? 0.22 : 0.15,
                            ),
                          ),
                          boxShadow: insetShadows,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              showDate ? dateLabel : startLabel,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: accentColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              showDate ? startLabel : endLabel,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: accentColor.withValues(alpha: 0.8),
                              ),
                            ),
                            if (showDate && endLabel.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                endLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.lightTextSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isOngoing) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'In Progress',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                            ],
                            Text(
                              title,
                              style: GoogleFonts.inter(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppTheme.darkTextPrimary
                                    : AppTheme.lightTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              entry.courseComponentName,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              location,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.4,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isOngoing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.green.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.green,
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStatusBanner(bool isDark) {
    final isRateLimited = _lastSyncErrorCode == 'rate_limited';
    final accent = isRateLimited ? Colors.orangeAccent : Colors.redAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _lastSyncErrorMessage ??
                  'Attendance sync is temporarily unavailable.',
              style: GoogleFonts.inter(
                fontSize: 12.8,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSyncTime(DateTime syncedAt) {
    if (syncedAt.millisecondsSinceEpoch == 0) {
      return 'just now';
    }
    final now = DateTime.now();
    final difference = now.difference(syncedAt);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes} min ago';
    if (difference.inDays < 1) {
      return '${difference.inHours} hr${difference.inHours == 1 ? '' : 's'} ago';
    }
    return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
  }
}

class _AttendanceProjectionSummary {
  const _AttendanceProjectionSummary({
    required this.percentage,
    required this.projectedTotal,
    required this.projectedPresent,
    required this.projectedMisses,
    required this.isSafe,
    required this.message,
  });

  final double percentage;
  final int projectedTotal;
  final int projectedPresent;
  final int projectedMisses;
  final bool isSafe;
  final String message;
}

class _AttendanceOverviewProjectionSummary {
  const _AttendanceOverviewProjectionSummary({
    required this.actualPercentage,
    required this.projectedPercentage,
    required this.actualPresent,
    required this.actualTotal,
    required this.projectedPresent,
    required this.projectedTotal,
    required this.scheduledFutureClasses,
    required this.skippedClasses,
    required this.message,
  });

  final double actualPercentage;
  final double projectedPercentage;
  final int actualPresent;
  final int actualTotal;
  final int projectedPresent;
  final int projectedTotal;
  final int scheduledFutureClasses;
  final int skippedClasses;
  final String message;
}
