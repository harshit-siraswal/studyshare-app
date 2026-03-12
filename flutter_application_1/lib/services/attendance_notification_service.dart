import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance_models.dart';

class AttendanceNotificationService {
  AttendanceNotificationService._();

  static final AttendanceNotificationService instance =
      AttendanceNotificationService._();
  static const String _channelId = 'attendance_alerts';
  static const String _channelName = 'Attendance Alerts';
  static const int _notificationId = 88021;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Alerts for low attendance subjects',
            importance: Importance.high,
          ),
        );

    _initialized = true;
  }

  Future<void> notifyLowAttendance({
    required String collegeId,
    required String collegeName,
    required List<AttendanceComponent> lowAttendance,
  }) async {
    await initialize();

    final prefs = await SharedPreferences.getInstance();
    final signatureKey = 'attendance_low_signature_$collegeId';

    if (lowAttendance.isEmpty) {
      await prefs.remove(signatureKey);
      return;
    }

    final signature = lowAttendance
        .map(
          (component) =>
              '${component.courseCode}:${component.componentName}:${component.percentage.toStringAsFixed(2)}',
        )
        .join('|');

    if (prefs.getString(signatureKey) == signature) {
      return;
    }

    await prefs.setString(signatureKey, signature);

    final topSubjects = lowAttendance
        .take(2)
        .map((component) {
          return component.courseCode.isNotEmpty
              ? component.courseCode
              : component.courseName;
        })
        .join(', ');

    final body = lowAttendance.length == 1
        ? '$topSubjects is below 75%. Open Attendance for the recovery plan.'
        : '${lowAttendance.length} KIET subjects are below 75%: $topSubjects';

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Alerts for low attendance subjects',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _notifications.show(
      _notificationId,
      '$collegeName attendance alert',
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
