import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../models/resource.dart';
import '../models/notice.dart';

class HomeWidgetService {
  static const String _defaultAndroidWidgetPackage = 'me.studyshare.android';

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

    // Re-apply groupId if already initialized (iOS only).
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

  Future<bool> syncNotices(List<Notice> notices) async {
    if (!await _ensureInitialized()) {
      return false;
    }
    try {
      final recentNotices = notices.take(3).toList();
      String displayText = '';
      if (recentNotices.isEmpty) {
        displayText = 'No recent notices.';
      } else {
        final buffer = StringBuffer();
        for (var n in recentNotices) {
          buffer.writeln('• ${n.title}');
        }
        displayText = buffer.toString().trim();
      }

      await HomeWidget.saveWidgetData<String>(
        'notices_data',
        displayText.trim(),
      );
      await HomeWidget.saveWidgetData<String>(
        'notices_title',
        'Recent Notices',
      );
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
      final relevantSyllabus = preFilteredSyllabusItems.take(3).toList();

      String displayText = '';
      if (relevantSyllabus.isEmpty) {
        displayText = 'No syllabus for $branch Sem $semester.';
      } else {
        final buffer = StringBuffer();
        for (var s in relevantSyllabus) {
          buffer.writeln('• ${s.title}');
        }
        displayText = buffer.toString().trim();
      }

      await HomeWidget.saveWidgetData<String>(
        'syllabus_data',
        displayText.trim(),
      );
      await HomeWidget.saveWidgetData<String>(
        'syllabus_title',
        'Syllabus: $branch S$semester',
      );
      await _updateWidget(_syllabusWidgetName);
      return true;
    } catch (e) {
      debugPrint('Error syncing syllabus to widget: $e');
      return false;
    }
  }
}
