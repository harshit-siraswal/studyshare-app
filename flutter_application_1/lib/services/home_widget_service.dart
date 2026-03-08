import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/academic_subjects_data.dart';
import '../models/notice.dart';
import '../models/resource.dart';

class HomeWidgetService {
  static const String _defaultAndroidWidgetPackage = 'me.studyshare.android';
  static const int _maxVisibleItems = 3;

  String _groupId = 'group.com.studyshare.app';
  String _noticesWidgetName = 'NoticesWidgetProvider';
  String _syllabusWidgetName = 'SyllabusWidgetProvider';

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
    _syllabusWidgetName = 'SyllabusWidgetProvider';
  }

  Future<void> configure({
    String? groupId,
    String? noticesWidgetName,
    String? syllabusWidgetName,
  }) async {
    if (groupId != null) _groupId = groupId;
    if (noticesWidgetName != null) _noticesWidgetName = noticesWidgetName;
    if (syllabusWidgetName != null) _syllabusWidgetName = syllabusWidgetName;

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

  Future<void> _saveWidgetLines(String prefix, List<String> lines) async {
    // Parallelize all save operations for better performance
    final saveFutures = <Future<bool?>>[];
    for (var index = 0; index < _maxVisibleItems; index++) {
      final value = index < lines.length ? lines[index] : '';
      saveFutures.add(
        HomeWidget.saveWidgetData<String>(
          '${prefix}_item_${index + 1}',
          value,
        ),
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
          ? 'Stay updated from your campus'
          : '${noticeLines.length} latest update${noticeLines.length == 1 ? '' : 's'}';

      await HomeWidget.saveWidgetData<String>('notices_title', 'Campus Notices');
      await HomeWidget.saveWidgetData<String>('notices_subtitle', subtitle);
      await HomeWidget.saveWidgetData<String>(
        'notices_empty_message',
        'No recent notices yet. Tap to open StudyShare.',
      );
      await _saveWidgetLines('notices', noticeLines);
      await _updateWidget(_noticesWidgetName);
      return true;
    } catch (e) {
      debugPrint('Error syncing notices to widget: $e');
      return false;
    }
  }

  Future<bool> syncSyllabus(
    String semester,
    String branch,
    List<Resource> preFilteredSyllabusItems,
  ) async {
    if (!await _ensureInitialized()) {
      return false;
    }
    try {
      final relevantSyllabus = preFilteredSyllabusItems
          .take(_maxVisibleItems)
          .toList();
      final syllabusLines = _buildWidgetLines(
        relevantSyllabus.map((item) => item.title),
      );
      final branchLabel = getBranchShortLabel(branch);

      await HomeWidget.saveWidgetData<String>(
        'syllabus_title',
        'Syllabus Tracker',
      );
      await HomeWidget.saveWidgetData<String>(
        'syllabus_subtitle',
        '$branchLabel | Semester $semester',
      );
      await HomeWidget.saveWidgetData<String>(
        'syllabus_empty_message',
        'No syllabus items for $branchLabel semester $semester.',
      );
      await _saveWidgetLines('syllabus', syllabusLines);
      await _updateWidget(_syllabusWidgetName);
      return true;
    } catch (e) {
      debugPrint('Error syncing syllabus to widget: $e');
      return false;
    }
  }
}
