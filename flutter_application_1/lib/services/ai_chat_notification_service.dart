import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AiChatNotificationService {
  AiChatNotificationService._();
  static final AiChatNotificationService instance =
      AiChatNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initializing;
  int _notificationIdCounter = 0;

  static const String _channelId = 'ai_chat_long_response';
  static const String _channelName = 'AI Chat Updates';
  static const String _channelDescription =
      'Notifications when AI responses are ready';
  bool? _darwinPermissionsGranted;

  bool? get darwinPermissionsGranted => _darwinPermissionsGranted;

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    if (_initializing != null) {
      await _initializing;
      return;
    }

    _initializing = _performInitialization();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _performInitialization() async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      debugPrint(
        'AiChatNotificationService: Unsupported platform '
        '${Platform.operatingSystem}.',
      );
      _initialized = false;
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    await _plugin.initialize(initSettings);

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
    if (Platform.isIOS) {
      _darwinPermissionsGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (_darwinPermissionsGranted != true) {
        debugPrint(
          'AiChatNotificationService: iOS notification permissions denied.',
        );
      }
    } else if (Platform.isMacOS) {
      _darwinPermissionsGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (_darwinPermissionsGranted != true) {
        debugPrint(
          'AiChatNotificationService: macOS notification permissions denied.',
        );
      }
    }

    _initialized = true;
  }

  int _nextNotificationId() {
    _notificationIdCounter =
        (_notificationIdCounter + 1) & 0x7FFFFFFF; // keep positive 31-bit int
    if (_notificationIdCounter == 0) {
      _notificationIdCounter = 1;
    }
    return _notificationIdCounter;
  }

  Future<void> notifyAnswerReady({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) {
      await initialize();
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    final notificationId = _nextNotificationId();
    try {
      await _plugin.show(notificationId, title, body, details);
    } catch (e, st) {
      debugPrint(
        'AiChatNotificationService.notifyAnswerReady failed '
        '(id=$notificationId): $e',
      );
      debugPrint('$st');
    }
  }
}
