import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
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
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(initSettings);

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Notifications when AI responses are ready',
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
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
      channelDescription: 'Notifications when AI responses are ready',
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
    );

    await _plugin.show(
      _nextNotificationId(),
      title,
      body,
      details,
    );
  }
}
