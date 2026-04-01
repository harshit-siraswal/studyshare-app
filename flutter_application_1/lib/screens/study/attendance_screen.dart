import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme.dart';
import '../../models/attendance_models.dart';
import '../../services/attendance_service.dart';
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

  AttendanceSnapshot? _snapshot;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isManualSyncing = false;
  bool _isLoadingDaywise = false;
  bool _hasSavedSession = false;
  String? _lastSyncErrorMessage;
  String? _lastSyncErrorCode;

  /// Periodic timer that calls [setState] during an ongoing class so the
  /// [LinearProgressIndicator] in each schedule card updates in real time.
  Timer? _scheduleProgressTimer;

  bool get _isKietCollege => _attendanceService.isKietCollege(
    collegeId: widget.collegeId,
    collegeName: widget.collegeName,
  );

  String get _syncCooldownUntilKey =>
      'attendance_sync_cooldown_until_${widget.collegeId}';

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
    _scheduleProgressTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (!mounted) {
          _scheduleProgressTimer?.cancel();
          return;
        }
        if (!_hasOngoingClass()) {
          _scheduleProgressTimer?.cancel();
          return;
        }
        setState(() {});
      },
    );
  }

  /// Returns true when the current snapshot contains at least one class that
  /// is actively in session right now (used to gate the progress timer).
  bool _hasOngoingClass() {
    final snapshot = _snapshot;
    if (snapshot == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final entry in snapshot.schedule.entries) {
      final entryDate = _attendanceService.tryParseDate(entry.lectureDate);
      if (entryDate == null) continue;
      if (DateTime(entryDate.year, entryDate.month, entryDate.day) != today) {
        continue;
      }
      if (entry.start.isEmpty || entry.end.isEmpty) continue;
      final sParts = entry.start.split(':');
      final eParts = entry.end.split(':');
      if (sParts.length < 2 || eParts.length < 2) continue;
      final sH = int.tryParse(sParts[0]);
      final sM = int.tryParse(sParts[1]);
      final eH = int.tryParse(eParts[0]);
      final eM = int.tryParse(eParts[1]);
      if (sH == null || sM == null || eH == null || eM == null) continue;
      final start = DateTime(
        entryDate.year, entryDate.month, entryDate.day, sH, sM,
      );
      final end = DateTime(
        entryDate.year, entryDate.month, entryDate.day, eH, eM,
      );
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
      _attendanceService.loadSavedToken(widget.collegeId),
      _attendanceService.loadCachedSnapshot(widget.collegeId),
    ]);
    final token = results[0] as String?;
    final snapshot = results[1] as AttendanceSnapshot?;
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _hasSavedSession = token != null && token.trim().isNotEmpty;
      _isLoading = false;
    });
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
    final token = await _attendanceService.loadSavedToken(widget.collegeId);
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
        await _attendanceService.clearSavedSession(widget.collegeId);
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
    await _attendanceService.clearSavedSession(widget.collegeId);
    await _clearSyncCooldown();
    if (!mounted) return;
    setState(() {
      _snapshot = null;
      _hasSavedSession = false;
      _lastSyncErrorMessage = null;
      _lastSyncErrorCode = null;
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
        );
      }

      final snapshot = await doSync();
      await _clearSyncCooldown();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _hasSavedSession = true;
        _lastSyncErrorMessage = null;
        _lastSyncErrorCode = null;
      });
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
    if (studentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student ID unavailable. Please sync again.'),
        ),
      );
      return;
    }

    setState(() => _isLoadingDaywise = true);
    try {
      final lectures = await _attendanceService.getDaywiseAttendance(
        collegeId: widget.collegeId,
        component: component,
        studentId: studentId,
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
                      '${component.courseName} • ${component.componentName}',
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
                                'No daywise attendance available yet.',
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
                                    '${lecture.dayName} • ${lecture.timeSlot}',
                                    style: GoogleFonts.inter(),
                                  ),
                                  trailing: Text(
                                    lecture.attendanceStatus.isEmpty
                                        ? 'N/A'
                                        : lecture.attendanceStatus,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      color:
                                          lecture.attendanceStatus
                                              .toLowerCase()
                                              .contains('present')
                                          ? Colors.green
                                          : Colors.redAccent,
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
      _showSyncError(error);
    } finally {
      if (mounted) setState(() => _isLoadingDaywise = false);
    }
  }

  String _formatDate(String rawDate) {
    return _attendanceService.formatDateDdMmYyyy(rawDate);
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
      return !dayDate.isBefore(startOfToday);
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

    final entries = _weeklyScheduleEntries(snapshot);
    final groupedEntries = _groupScheduleEntries(entries);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
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
                  const SizedBox(height: 12),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Text(
                              'No classes in this week schedule.',
                              style: GoogleFonts.inter(
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary,
                              ),
                            ),
                          )
                        : ListView(
                            children: groupedEntries.entries.map((group) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.key,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? AppTheme.darkTextSecondary
                                            : AppTheme.lightTextSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    ...group.value.map(
                                      (entry) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: _buildScheduleEntryCard(
                                          entry,
                                          isDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                ],
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

    final upcomingEntries = _upcomingScheduleEntries(snapshot).take(5).toList();

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
                child: _buildComponentCard(component, isDark),
              ),
            ),
          ),
          if (upcomingEntries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Upcoming Classes',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
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
    final alert =
        snapshot.overall.percentage < AttendanceService.lowAttendanceThreshold;
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
            '${snapshot.student.branchShortName} • ${snapshot.student.semesterName} • ${snapshot.student.sectionName}',
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
                  '${snapshot.overall.percentage.toStringAsFixed(2)}%',
                  style: GoogleFonts.inter(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: alert ? Colors.redAccent : Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert
                      ? 'You are below the safe threshold right now.'
                      : 'You are above the safe threshold right now.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
                label: 'Attended',
                value:
                    '${snapshot.overall.presentClasses}/${snapshot.overall.totalClasses}',
                isDark: isDark,
              ),
              _buildOverviewStat(
                label: 'Last synced',
                value: _formatSyncTime(snapshot.syncedAt),
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
                      '${component.componentName} • ${component.percentage.toStringAsFixed(2)}%',
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

  Widget _buildComponentCard(AttendanceComponent component, bool isDark) {
    final accent = component.isLowAttendance ? Colors.redAccent : Colors.green;
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
                      '${component.componentName} • ${component.courseCode}',
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
                  '${component.percentage.toStringAsFixed(2)}%',
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
              value: (component.percentage / 100).clamp(0.0, 1.0),
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
                value: '${component.attendedClasses}/${component.totalClasses}',
                isDark: isDark,
              ),
              _buildComponentStatChip(
                label: 'Extra',
                value: '${component.extraAttendance}',
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
                  component.isLowAttendance ? 'Next action' : 'Safe zone',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.16,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  component.isLowAttendance
                      ? 'Attend ${component.classesNeededForThreshold} more classes to reach ${component.threshold}%.'
                      : 'You can miss ${component.bunkAllowance} classes and stay above ${component.threshold}%.',
                  style: GoogleFonts.inter(
                    fontSize: 12.8,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
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

  Widget _buildScheduleEntryCard(AttendanceScheduleEntry entry, bool isDark) {
    final now = DateTime.now();
    final entryDate = _attendanceService.tryParseDate(entry.lectureDate);
    final today = DateTime(now.year, now.month, now.day);
    final isToday = entryDate != null &&
        DateTime(entryDate.year, entryDate.month, entryDate.day) == today;

    DateTime? classStart;
    DateTime? classEnd;
    if (entryDate != null && entry.start.isNotEmpty && entry.end.isNotEmpty) {
      final sParts = entry.start.split(':');
      final eParts = entry.end.split(':');
      if (sParts.length >= 2 && eParts.length >= 2) {
        final sHour = int.tryParse(sParts[0]);
        final sMin = int.tryParse(sParts[1]);
        final eHour = int.tryParse(eParts[0]);
        final eMin = int.tryParse(eParts[1]);
        if (sHour != null && sMin != null && eHour != null && eMin != null) {
          classStart = DateTime(
            entryDate.year, entryDate.month, entryDate.day, sHour, sMin,
          );
          classEnd = DateTime(
            entryDate.year, entryDate.month, entryDate.day, eHour, eMin,
          );
        }
      }
    }

    final isOngoing = isToday &&
        classStart != null &&
        classEnd != null &&
        !now.isBefore(classStart) &&
        now.isBefore(classEnd);
    final isPast = classEnd != null && now.isAfter(classEnd);
    double progress = 0.0;
    if (isOngoing) {
      final totalSecs = classEnd.difference(classStart).inSeconds.toDouble();
      final elapsedSecs = now.difference(classStart).inSeconds.toDouble();
      progress =
          (totalSecs > 0 ? elapsedSecs / totalSecs : 0.0).clamp(0.0, 1.0);
    }

    final accentColor = isOngoing ? Colors.green : AppTheme.primary;
    final title = entry.courseName.isEmpty
        ? (entry.title.isEmpty ? 'Class' : entry.title)
        : entry.courseName;
    final location =
        entry.classRoom.isEmpty ? 'Classroom TBA' : entry.classRoom;

    return Opacity(
      opacity: isPast ? 0.55 : 1.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: isOngoing
                ? Border.all(
                    color: Colors.green.withValues(alpha: 0.5),
                    width: 1.5,
                  )
                : Border.all(
                    color: isDark ? Colors.white10 : Colors.black12,
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
                        color: accentColor.withValues(
                          alpha: isDark ? 0.16 : 0.1,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.start,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.end,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: accentColor.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatDate(entry.lectureDate),
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
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
              // Green progress bar shown at the bottom only for ongoing classes.
              if (isOngoing)
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.green.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  minHeight: 4,
                ),
            ],
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
    return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';  }
}
