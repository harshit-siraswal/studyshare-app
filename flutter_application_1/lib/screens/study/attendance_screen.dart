import 'package:flutter/material.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../models/attendance_models.dart';
import '../../services/attendance_service.dart';
import '../ai_chat_screen.dart';
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
  bool _isLoadingDaywise = false;
  bool _autoSyncAttempted = false;

  bool get _isKietCollege => _attendanceService.isKietCollege(
    collegeId: widget.collegeId,
    collegeName: widget.collegeName,
  );

  @override
  void initState() {
    super.initState();
    _loadCachedSnapshot();
  }

  Future<void> _loadCachedSnapshot() async {
    if (!_isKietCollege) {
      setState(() => _isLoading = false);
      return;
    }
    final snapshot = await _attendanceService.loadCachedSnapshot(
      widget.collegeId,
    );
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _isLoading = false;
    });
    _triggerBackgroundSyncIfPossible();
  }

  Future<void> _triggerBackgroundSyncIfPossible() async {
    if (_autoSyncAttempted || !_isKietCollege) return;
    _autoSyncAttempted = true;

    final token = await _attendanceService.loadSavedToken(widget.collegeId);
    if (!mounted || token == null || token.isEmpty) return;

    try {
      await _syncWithToken(token, showSuccessToast: false);
    } catch (error) {
      debugPrint('Attendance background sync skipped: $error');
    }
  }

  Future<void> _connectAndSync() async {
    if (_isSyncing) return;

    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AttendanceWebLoginScreen()),
    );
    if (!mounted || token == null || token.trim().isEmpty) return;

    try {
      await _syncWithToken(token.trim());
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Future<void> _syncWithSavedToken({bool promptIfMissingToken = true}) async {
    final token = await _attendanceService.loadSavedToken(widget.collegeId);
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      if (promptIfMissingToken) {
        await _connectAndSync();
      }
      return;
    }
    try {
      await _syncWithToken(token);
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

  Future<void> _syncWithToken(
    String token, {
    bool showSuccessToast = true,
  }) async {
    setState(() => _isSyncing = true);
    try {
      final snapshot = await _attendanceService.syncKietAttendance(
        collegeId: widget.collegeId,
        collegeName: widget.collegeName,
        cybervidyaToken: token,
        context: context,
      );
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      if (showSuccessToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('KIET attendance synced successfully.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
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

  void _openAttendanceAi() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AIChatScreen(
          collegeId: widget.collegeId,
          collegeName: widget.collegeName,
          initialPrompt: _attendanceService.buildAiPrompt(snapshot),
        ),
      ),
    );
  }

  String _formatDate(String rawDate) {
    return _attendanceService.formatDateDdMmYyyy(rawDate);
  }

  List<AttendanceScheduleEntry> _upcomingScheduleEntries(
    AttendanceSnapshot snapshot,
  ) {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final entries = List<AttendanceScheduleEntry>.from(snapshot.schedule.entries)
      ..sort((a, b) {
        final aDate = _attendanceService.tryParseDate(a.lectureDate) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = _attendanceService.tryParseDate(b.lectureDate) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final dateCmp = aDate.compareTo(bDate);
        if (dateCmp != 0) return dateCmp;
        return a.start.compareTo(b.start);
      });

    final upcoming = entries.where((entry) {
      final parsed = _attendanceService.tryParseDate(entry.lectureDate);
      if (parsed == null) return false;
      final dayDate = DateTime(parsed.year, parsed.month, parsed.day);
      return !dayDate.isBefore(startOfToday);
    }).toList();

    return upcoming.isNotEmpty ? upcoming : entries;
  }

  DateTime _parseEntryDateTime(String dateRaw, String timeRaw) {
    final baseDate =
        _attendanceService.tryParseDate(dateRaw) ?? DateTime.now();
    final parts = timeRaw.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
  }

  Future<void> _addAllToCalendar(List<AttendanceScheduleEntry> entries) async {
    if (entries.isEmpty) return;
    for (final entry in entries) {
      final start = _parseEntryDateTime(entry.lectureDate, entry.start);
      final end = _parseEntryDateTime(entry.lectureDate, entry.end);
      final safeEnd =
          end.isAfter(start) ? end : start.add(const Duration(hours: 1));
      final title = entry.courseName.isEmpty
          ? (entry.title.isEmpty ? 'Class' : entry.title)
          : entry.courseName;
      final description =
          '${entry.courseComponentName} • ${entry.facultyName}'.trim();
      final event = Event(
        title: title,
        description: description,
        location: entry.classRoom,
        startDate: start,
        endDate: safeEnd,
      );
      await Add2Calendar.addEvent2Cal(event);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All classes added to your calendar')),
      );
    }
  }

  Future<void> _openWeeklyScheduleSheet() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    final entries = _upcomingScheduleEntries(snapshot);
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
                      fontSize: 18,
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
                        : ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              final title = entry.courseName.isEmpty
                                  ? (entry.title.isEmpty ? 'Class' : entry.title)
                                  : entry.courseName;
                              final location = entry.classRoom.isEmpty
                                  ? 'Classroom TBA'
                                  : entry.classRoom;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  title,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_formatDate(entry.lectureDate)} • ${entry.start} - ${entry.end}\n$location',
                                  style: GoogleFonts.inter(height: 1.3),
                                ),
                                trailing: null,
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
                  onPressed: _snapshot == null ? null : _openWeeklyScheduleSheet,
                  icon: const Icon(Icons.calendar_month_rounded),
                ),
                IconButton(
                  onPressed: _isSyncing ? null : _syncWithSavedToken,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect your KIET ERP session to sync attendance.',
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
            'StudyShare opens the official KIET ERP page, waits for the authenticated home state after login and reCAPTCHA, then reads the session token the same way the upstream bridge does.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.4,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _isSyncing ? null : _connectAndSync,
            icon: const Icon(Icons.login_rounded),
            label: Text(
              _isSyncing ? 'Syncing...' : 'Connect KIET ERP',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _syncWithSavedToken,
      child: ListView(
        children: [
          _buildOverviewCard(snapshot, isDark),
          const SizedBox(height: 16),
          if (snapshot.lowAttendance.isNotEmpty) ...[
            _buildLowAttendanceCard(snapshot, isDark),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSyncing ? null : _syncWithSavedToken,
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(
                    'Sync now',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openAttendanceAi,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    'Ask AI',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_upcomingScheduleEntries(snapshot).isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_month_rounded),
              label: const Text('Add All Classes to Calendar'),
              onPressed: () =>
                  _addAllToCalendar(_upcomingScheduleEntries(snapshot)),
            ),
          const SizedBox(height: 20),
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
          if (_upcomingScheduleEntries(snapshot).isNotEmpty) ...[
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
            ..._upcomingScheduleEntries(snapshot)
                .take(5)
                .map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      entry.courseName.isEmpty ? entry.title : entry.courseName,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${_formatDate(entry.lectureDate)} • ${entry.start} - ${entry.end}',
                      style: GoogleFonts.inter(),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewCard(AttendanceSnapshot snapshot, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snapshot.student.fullName,
            style: GoogleFonts.inter(
              fontSize: 18,
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
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${snapshot.overall.percentage.toStringAsFixed(2)}%',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color:
                  snapshot.overall.percentage <
                      AttendanceService.lowAttendanceThreshold
                  ? Colors.redAccent
                  : Colors.green,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${snapshot.overall.presentClasses}/${snapshot.overall.totalClasses} classes attended',
            style: GoogleFonts.inter(
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Last synced ${_formatSyncTime(snapshot.syncedAt)}',
            style: GoogleFonts.inter(
              fontSize: 12,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A1A1A) : const Color(0xFFFFEFEF),
        borderRadius: BorderRadius.circular(20),
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
          ...snapshot.lowAttendance.map(
            (component) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${component.courseName} (${component.componentName}) • '
                '${component.percentage.toStringAsFixed(2)}% • '
                'Need ${component.classesNeededForThreshold} classes to recover',
                style: GoogleFonts.inter(
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(18),
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
          const SizedBox(height: 12),
          Text(
            '${component.attendedClasses}/${component.totalClasses} attended • '
            '${component.extraAttendance} extra attendance',
            style: GoogleFonts.inter(
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            component.isLowAttendance
                ? 'Recovery: attend ${component.classesNeededForThreshold} more classes to reach ${component.threshold}%.'
                : 'Safe margin: you can miss ${component.bunkAllowance} classes and stay above ${component.threshold}%.',
            style: GoogleFonts.inter(
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
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

  String _formatSyncTime(DateTime syncedAt) {
    if (syncedAt.millisecondsSinceEpoch == 0) {
      return 'just now';
    }
    final now = DateTime.now();
    final difference = now.difference(syncedAt);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes} min ago';
    if (difference.inDays < 1) return '${difference.inHours} hr ago';
    return '${difference.inDays} day ago';
  }
}



