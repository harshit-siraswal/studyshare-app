import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../models/resource.dart';
import '../models/notice.dart';

class HomeWidgetService {
  String _groupId = 'group.com.mystudyspace.app';
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
    _groupId = 'group.com.mystudyspace.app';
    _noticesWidgetName = 'NoticesWidgetProvider';
    _syllabusWidgetName = 'SyllabusWidgetProvider';
  }

  void configure({
    String? groupId,
    String? noticesWidgetName,
    String? syllabusWidgetName,
  }) {
    if (groupId != null) _groupId = groupId;
    if (noticesWidgetName != null) _noticesWidgetName = noticesWidgetName;
    if (syllabusWidgetName != null) _syllabusWidgetName = syllabusWidgetName;

    // Re-apply groupId if already initialized
    if (_isInitialized && groupId != null) {
      HomeWidget.setAppGroupId(_groupId).catchError((e) {
        debugPrint('Error re-applying groupId after configure: $e');
        return null;
      });
    }
  }

  Future<bool> initialize() {
    if (_isInitialized) return Future.value(true);
    if (_initializing != null) return _initializing!;

    _initializing = _doInitialize();
    return _initializing!;
  }

  Future<bool> _doInitialize() async {
    try {
      await HomeWidget.setAppGroupId(_groupId);
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

  Future<bool> syncNotices(List<Notice> notices) async {
    if (!_isInitialized) {
      debugPrint('HomeWidgetService not initialized');
      return false;
    }
    try {
      final recentNotices = notices.take(3).toList();
      String displayText = '';
      if (recentNotices.isEmpty) {
        displayText = 'No recent notices.';
      } else {
        for (var n in recentNotices) {
          displayText += '• ${n.title}\n';
        }
      }

      await HomeWidget.saveWidgetData<String>('notices_data', displayText.trim());
      await HomeWidget.updateWidget(name: _noticesWidgetName);
      return true;
    } catch (e) {
      debugPrint('Error syncing notices to widget: $e');
      return false;
    }
  }

  Future<bool> syncSyllabus(String semester, String branch, List<Resource> preFilteredSyllabusItems) async {
    if (!_isInitialized) {
      debugPrint('HomeWidgetService not initialized');
      return false;
    }
    try {
      final relevantSyllabus = preFilteredSyllabusItems.take(3).toList();

      String displayText = '';
      if (relevantSyllabus.isEmpty) {
        displayText = 'No syllabus for $branch Sem $semester.';
      } else {
        for (var s in relevantSyllabus) {
          displayText += '• ${s.title}\n';
        }
      }

      await HomeWidget.saveWidgetData<String>('syllabus_data', displayText.trim());
      await HomeWidget.saveWidgetData<String>('syllabus_title', 'Syllabus: $branch S$semester');
      await HomeWidget.updateWidget(name: _syllabusWidgetName);
      return true;
    } catch (e) {
      debugPrint('Error syncing syllabus to widget: $e');
      return false;
    }
  }
}
