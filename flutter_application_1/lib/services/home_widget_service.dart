import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/academic_subjects_data.dart';
import '../models/attendance_models.dart';
import '../models/notice.dart';
import 'attendance_service.dart';

class HomeWidgetService {
  static const String _defaultAndroidWidgetPackage = 'me.studyshare.android';
  static const int _maxVisibleItems = 3;
  static const int _maxScheduleCards = 5;

  final AttendanceService _attendanceService = AttendanceService();

  String _groupId = 'group.com.studyshare.app';
  String _noticesWidgetName = 'NoticesWidgetProvider';
  String _scheduleWidgetName = 'ScheduleWidgetProvider';

  bool _isInitialized = false;
  Future<bool>? _initializing;

  HomeWidgetService._();
  static final HomeWidgetService instance = HomeWidgetService._();

  /// Resets all mutable internal state back to defaults for testing.
  @visibleForTesting
  void resetForTesting() {
    _isInitialized = false;
    _initializing = null;
    _groupId = 'group.com.studyshare.app';
    _noticesWidgetName = 'NoticesWidgetProvider';
    _scheduleWidgetName = 'ScheduleWidgetProvider';
  }

  Future<void> configure({
    String? groupId,
    String? noticesWidgetName,
    String? scheduleWidgetName,
  }) async {
    if (groupId != null) _groupId = groupId;
    if (noticesWidgetName != null) _noticesWidgetName = noticesWidgetName;
    if (scheduleWidgetName != null) _scheduleWidgetName = scheduleWidgetName;

    if (_isInitialized &&
        groupId != null &&
        defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId(_groupId);
    }
  }

  Future<bool> initialize() {
    if (_isInitialized) return Future.value(true);
    if (_initializing != null) return _initializing!;

    _initializing = _doInitialize();
    return _initializing!;
  }

  Future<bool> _doInitialize() async {
    if (kIsWeb) {
      _isInitialized = false;
      return false;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await HomeWidget.setAppGroupId(_groupId);
      }
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Error initializing HomeWidget: $e');
      _isInitialized = false;
      return false;
    } finally {
      _initializing = null;
    }
  }

  String _qualifiedAndroidName(String widgetName) {
    if (widgetName.contains('.')) return widgetName;
    return '$_defaultAndroidWidgetPackage.$widgetName';
  }

  Future<bool> _ensureInitialized() async {
    if (_isInitialized) return true;
    final ready = await initialize();
    if (!ready) {
      debugPrint('HomeWidgetService not initialized');
    }
    return ready;
  }

  Future<void> _updateWidget(String widgetName) async {
    final result = await HomeWidget.updateWidget(
      name: widgetName,
      qualifiedAndroidName: _qualifiedAndroidName(widgetName),
    );
    if (result != true) {
      debugPrint(
        'HomeWidget update returned $result for $widgetName '
        '(qualified: ${_qualifiedAndroidName(widgetName)})',
      );
    }
  }

  String _sanitizeWidgetLine(String raw, {int maxLength = 54}) {
    // Defensive guard for invalid maxLength
    if (maxLength < 0) maxLength = 0;

    final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return '';
    if (compact.length <= maxLength) return compact;

    // Handle tiny maxLength values
    if (maxLength <= 3) {
      return compact.substring(0, maxLength);
    }

    return '${compact.substring(0, maxLength - 3).trim()}...';
  }

  List<String> _buildWidgetLines(Iterable<String> values) {
    return values
        .map(_sanitizeWidgetLine)
        .where((value) => value.isNotEmpty)
        .take(_maxVisibleItems)
        .toList();
  }

  DateTime? _parseScheduleEntryDateTime(String rawDate, String rawTime) {
    final baseDate = _attendanceService.tryParseDate(rawDate);
    if (baseDate == null) return null;

    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(rawTime);
    if (match == null) return null;

    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) return null;

    return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
  }

  List<AttendanceScheduleEntry> _sortedScheduleEntries(
    AttendanceSnapshot snapshot,
  ) {
    final entries = List<AttendanceScheduleEntry>.from(
      snapshot.schedule.entries,
    );
    entries.sort((a, b) {
      final aStart =
          _parseScheduleEntryDateTime(a.lectureDate, a.start) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bStart =
          _parseScheduleEntryDateTime(b.lectureDate, b.start) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return aStart.compareTo(bStart);
    });
    return entries;
  }

  AttendanceScheduleEntry? _findCurrentEntry(
    List<AttendanceScheduleEntry> entries,
    DateTime now,
  ) {
    for (final entry in entries) {
      final start = _parseScheduleEntryDateTime(entry.lectureDate, entry.start);
      final end = _parseScheduleEntryDateTime(entry.lectureDate, entry.end);
      if (start == null || end == null) continue;
      if (!now.isBefore(start) && now.isBefore(end)) {
        return entry;
      }
    }
    return null;
  }

  List<AttendanceScheduleEntry> _findUpcomingEntries(
    List<AttendanceScheduleEntry> entries,
    DateTime now,
  ) {
    return entries.where((entry) {
      final start = _parseScheduleEntryDateTime(entry.lectureDate, entry.start);
      return start != null && !start.isBefore(now);
    }).toList();
  }

  String _formatScheduleRange(AttendanceScheduleEntry entry) {
    final start = entry.start.trim();
    final end = entry.end.trim();
    if (start.isEmpty && end.isEmpty) return '';
    if (start.isEmpty) return end;
    if (end.isEmpty) return start;
    return '$start - $end';
  }

  String _entryPrimaryLabel(AttendanceScheduleEntry entry) {
    final subject = entry.courseName.trim();
    final code = entry.courseCode.trim();
    if (subject.isEmpty && code.isEmpty) {
      return entry.title.trim().isEmpty
          ? 'Class in progress'
          : entry.title.trim();
    }
    if (code.isEmpty) return subject;
    if (subject.isEmpty) return code;
    return '$subject ($code)';
  }

  String _entryCardTitle(AttendanceScheduleEntry entry) {
    final subject = entry.courseName.trim();
    final title = entry.title.trim();
    final code = entry.courseCode.trim();
    if (subject.isNotEmpty) return subject;
    if (title.isNotEmpty) return title;
    if (code.isNotEmpty) return code;
    return 'Scheduled class';
  }

  String _entrySecondaryLabel(AttendanceScheduleEntry entry) {
    final parts = <String>[];
    final room = entry.classRoom.trim();
    final timeRange = _formatScheduleRange(entry);
    final faculty = entry.facultyName.trim();
    if (room.isNotEmpty) parts.add('Room $room');
    if (timeRange.isNotEmpty) parts.add(timeRange);
    if (faculty.isNotEmpty) parts.add(faculty);
    return parts.join(' - ');
  }

  String _entryCardMeta(AttendanceScheduleEntry entry) {
    final parts = <String>[];
    final code = entry.courseCode.trim();
    final timeRange = _formatScheduleRange(entry);
    if (code.isNotEmpty) parts.add(code);
    if (timeRange.isNotEmpty) parts.add(timeRange);
    if (parts.isEmpty) return _entrySecondaryLabel(entry);
    return parts.join(' | ');
  }

  String _entryDetailLabel(AttendanceScheduleEntry entry) {
    final details = <String>[];
    final component = entry.courseComponentName.trim();
    final faculty = entry.facultyName.trim();
    final lectureDate = _attendanceService.formatDateDdMmYyyy(
      entry.lectureDate,
    );
    if (component.isNotEmpty) details.add(component);
    if (faculty.isNotEmpty) details.add(faculty);
    if (lectureDate.trim().isNotEmpty) details.add(lectureDate);
    return details.join(' - ');
  }

  String _entryCardDetail(AttendanceScheduleEntry entry) {
    final details = <String>[];
    final faculty = entry.facultyName.trim();
    final component = entry.courseComponentName.trim();
    if (faculty.isNotEmpty) details.add(faculty);
    if (component.isNotEmpty) details.add(component);
    if (details.isEmpty) return _entryDetailLabel(entry);
    return details.join(' | ');
  }

  String _formatRoomLabel(String room) {
    final trimmed = room.trim();
    if (trimmed.isEmpty) return 'Open Schedule';
    if (trimmed.toLowerCase().startsWith('room ')) return trimmed;
    return 'Room $trimmed';
  }

  bool _isSameScheduleEntry(
    AttendanceScheduleEntry first,
    AttendanceScheduleEntry second,
  ) {
    return first.lectureDate == second.lectureDate &&
        first.start == second.start &&
        first.end == second.end &&
        first.courseCode == second.courseCode &&
        first.classRoom == second.classRoom;
  }

  int _progressPercent(AttendanceScheduleEntry entry, DateTime now) {
    final start = _parseScheduleEntryDateTime(entry.lectureDate, entry.start);
    final end = _parseScheduleEntryDateTime(entry.lectureDate, entry.end);
    if (start == null ||
        end == null ||
        !now.isAfter(start) ||
        !end.isAfter(start)) {
      return 0;
    }
    if (!now.isBefore(end)) return 100;
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 0;
    final elapsed = now.difference(start).inMilliseconds.clamp(0, total);
    return ((elapsed / total) * 100).round().clamp(0, 100);
  }

  String _buildScheduleTargetUri(AttendanceScheduleEntry entry) {
    return Uri(
      scheme: 'studyshare',
      host: 'widget',
      path: '/schedule',
      queryParameters: <String, String>{
        'view': 'attendance',
        'date': entry.lectureDate,
        'course': _entryPrimaryLabel(entry),
        if (entry.classRoom.trim().isNotEmpty) 'room': entry.classRoom.trim(),
      },
    ).toString();
  }

  List<_ScheduleWidgetCard> _buildScheduleCards(
    AttendanceSnapshot snapshot,
    List<AttendanceScheduleEntry> entries,
    AttendanceScheduleEntry? current,
    List<AttendanceScheduleEntry> upcoming,
    DateTime now,
  ) {
    final cards = <_ScheduleWidgetCard>[];
    final consumed = <AttendanceScheduleEntry>[];

    void addCard(
      AttendanceScheduleEntry entry, {
      required String status,
      required bool isLive,
    }) {
      if (cards.length >= _maxScheduleCards) return;
      final progress = isLive ? _progressPercent(entry, now) : 0;
      cards.add(
        _ScheduleWidgetCard(
          status: status,
          title: _sanitizeWidgetLine(_entryCardTitle(entry), maxLength: 44),
          meta: _sanitizeWidgetLine(_entryCardMeta(entry), maxLength: 46),
          detail: _sanitizeWidgetLine(_entryCardDetail(entry), maxLength: 46),
          progress: progress,
          progressLabel: isLive ? '$progress%' : '',
          isLive: isLive,
          targetUri: _buildScheduleTargetUri(entry),
        ),
      );
      consumed.add(entry);
    }

    if (current != null) {
      addCard(current, status: 'Live now', isLive: true);
    }

    final futureEntries = upcoming.where((entry) {
      return !consumed.any((taken) => _isSameScheduleEntry(taken, entry));
    });

    var nextLabelUsed = false;
    for (final entry in futureEntries) {
      addCard(entry, status: nextLabelUsed ? 'Then' : 'Up next', isLive: false);
      nextLabelUsed = true;
      if (cards.length >= _maxScheduleCards) break;
    }

    if (cards.isEmpty) {
      for (final entry in entries.take(_maxScheduleCards)) {
        addCard(entry, status: 'Scheduled', isLive: false);
      }
    }

    return cards;
  }

  _ScheduleWidgetPayload _buildScheduleWidgetPayload({
    required String semester,
    required String branch,
    AttendanceSnapshot? snapshot,
  }) {
    final branchLabel = branch.trim().isEmpty
        ? 'Schedule'
        : getBranchShortLabel(branch);
    final defaultPayload = _ScheduleWidgetPayload(
      badge: 'Schedule',
      isLive: false,
      locationLabel: semester.trim().isEmpty
          ? 'Current Class Location'
          : '$branchLabel | Semester $semester',
      roomLabel: 'Open Schedule',
      footerLabel: 'Tap to open schedule',
      emptyMessage:
          'Live class and room will appear here when schedule data is available.',
      indicatorCount: 0,
      cards: const <_ScheduleWidgetCard>[],
    );

    if (snapshot == null || snapshot.schedule.entries.isEmpty) {
      return defaultPayload;
    }

    final now = DateTime.now();
    final entries = _sortedScheduleEntries(snapshot);
    final current = _findCurrentEntry(entries, now);
    final upcoming = _findUpcomingEntries(entries, now);
    final cards = _buildScheduleCards(
      snapshot,
      entries,
      current,
      upcoming,
      now,
    );
    final indicatorCount = cards.length.clamp(0, 3).toInt();

    String footerLabel() {
      final nextEntry = upcoming.firstWhere(
        (entry) => current == null || !_isSameScheduleEntry(entry, current),
        orElse: () => upcoming.isNotEmpty ? upcoming.first : entries.first,
      );
      if (cards.length <= 1) return 'Tap to open schedule';
      return 'Next: ${_sanitizeWidgetLine(_entryCardTitle(nextEntry).toUpperCase(), maxLength: 28)}';
    }

    if (current != null) {
      return _ScheduleWidgetPayload(
        badge: 'Live now',
        isLive: true,
        locationLabel: 'Current Class Location',
        roomLabel: _sanitizeWidgetLine(
          _formatRoomLabel(current.classRoom),
          maxLength: 24,
        ),
        footerLabel: footerLabel(),
        emptyMessage: defaultPayload.emptyMessage,
        indicatorCount: indicatorCount,
        cards: cards,
      );
    }

    if (upcoming.isNotEmpty) {
      final next = upcoming.first;
      final roomLabel = next.classRoom.trim().isNotEmpty
          ? _formatRoomLabel(next.classRoom)
          : _formatScheduleRange(next);
      return _ScheduleWidgetPayload(
        badge: 'Up next',
        isLive: false,
        locationLabel: 'Next Class Location',
        roomLabel: _sanitizeWidgetLine(roomLabel, maxLength: 24),
        footerLabel: 'Tap to open schedule',
        emptyMessage: defaultPayload.emptyMessage,
        indicatorCount: indicatorCount,
        cards: cards,
      );
    }

    return _ScheduleWidgetPayload(
      badge: 'Today',
      isLive: false,
      locationLabel: 'Current Class Location',
      roomLabel: 'No Live Class',
      footerLabel: 'Tap to open schedule',
      emptyMessage: defaultPayload.emptyMessage,
      indicatorCount: indicatorCount,
      cards: cards,
    );
  }

  Future<void> _saveWidgetLines(String prefix, List<String> lines) async {
    // Parallelize all save operations for better performance
    final saveFutures = <Future<bool?>>[];
    for (var index = 0; index < _maxVisibleItems; index++) {
      final value = index < lines.length ? lines[index] : '';
      saveFutures.add(
        HomeWidget.saveWidgetData<String>('${prefix}_item_${index + 1}', value),
      );
    }
    await Future.wait(saveFutures);
  }

  Future<bool> syncNotices(List<Notice> notices) async {
    if (!await _ensureInitialized()) {
      return false;
    }
    try {
      final recentNotices = notices.take(_maxVisibleItems).toList();
      final noticeLines = _buildWidgetLines(
        recentNotices.map((notice) => notice.title),
      );
      final subtitle = noticeLines.isEmpty
          ? 'Latest campus notices'
          : '${noticeLines.length} recent notice${noticeLines.length == 1 ? '' : 's'}';

      await HomeWidget.saveWidgetData<String>(
        'notices_title',
        'Campus Updates',
      );
      await HomeWidget.saveWidgetData<String>('notices_subtitle', subtitle);
      await HomeWidget.saveWidgetData<String>(
        'notices_empty_message',
        'No recent notices right now. Tap to open StudyShare.',
      );
      await _saveWidgetLines('notices', noticeLines);
      await _updateWidget(_noticesWidgetName);
      return true;
    } catch (e) {
      debugPrint('Error syncing notices to widget: $e');
      return false;
    }
  }

  Future<bool> syncSchedule({
    required String collegeId,
    required String semester,
    required String branch,
    AttendanceSnapshot? snapshot,
  }) async {
    if (!await _ensureInitialized()) {
      return false;
    }
    try {
      final payload = _buildScheduleWidgetPayload(
        semester: semester,
        branch: branch,
        snapshot:
            snapshot ?? await _attendanceService.loadCachedSnapshot(collegeId),
      );

      await Future.wait([
        HomeWidget.saveWidgetData<String>('schedule_badge', payload.badge),
        HomeWidget.saveWidgetData<String>(
          'schedule_location_label',
          payload.locationLabel,
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_room_label',
          payload.roomLabel,
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_footer_label',
          payload.footerLabel,
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_empty_message',
          payload.emptyMessage,
        ),
        HomeWidget.saveWidgetData<bool>('schedule_is_live', payload.isLive),
        HomeWidget.saveWidgetData<int>(
          'schedule_indicator_count',
          payload.indicatorCount,
        ),
        HomeWidget.saveWidgetData<String>(
          'schedule_cards_json',
          jsonEncode(
            payload.cards.map((card) => card.toJson()).toList(growable: false),
          ),
        ),
      ]);
      await _updateWidget(_scheduleWidgetName);
      return true;
    } catch (e) {
      debugPrint('Error syncing schedule to widget: $e');
      return false;
    }
  }
}

class _ScheduleWidgetPayload {
  const _ScheduleWidgetPayload({
    required this.badge,
    required this.isLive,
    required this.locationLabel,
    required this.roomLabel,
    required this.footerLabel,
    required this.emptyMessage,
    required this.indicatorCount,
    required this.cards,
  });

  final String badge;
  final bool isLive;
  final String locationLabel;
  final String roomLabel;
  final String footerLabel;
  final String emptyMessage;
  final int indicatorCount;
  final List<_ScheduleWidgetCard> cards;
}

class _ScheduleWidgetCard {
  const _ScheduleWidgetCard({
    required this.status,
    required this.title,
    required this.meta,
    required this.detail,
    required this.progress,
    required this.progressLabel,
    required this.isLive,
    required this.targetUri,
  });

  final String status;
  final String title;
  final String meta;
  final String detail;
  final int progress;
  final String progressLabel;
  final bool isLive;
  final String targetUri;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'status': status,
      'title': title,
      'meta': meta,
      'detail': detail,
      'progress': progress,
      'progressLabel': progressLabel,
      'isLive': isLive,
      'targetUri': targetUri,
    };
  }
}
