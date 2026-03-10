import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[PushService] Background message: ${message.messageId}');
  // Background messages are handled by the system notification tray.
}

/// Service for handling Firebase Cloud Messaging (FCM) push notifications.
class PushNotificationService {
  PushNotificationService._internal();

  static final PushNotificationService _instance =
      PushNotificationService._internal();
  static const String notificationsEnabledKey = 'notifications_enabled';
  static const String _tokenPrefsKey = 'fcm_token';

  factory PushNotificationService() => _instance;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  bool _isInitialized = false;
  bool _localNotificationsInitialized = false;
  bool _notificationsEnabled = true;
  FutureOr<void> Function(String token)? _onTokenRefresh;
  FutureOr<void> Function(String token)? _onTokenInvalidated;
  FutureOr<void> Function(RemoteMessage message)? _onMessageReceived;
  FutureOr<void> Function(RemoteMessage message)? _onNotificationTap;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  /// Get the current FCM token.
  String? get fcmToken => _fcmToken;

  /// Releases subscriptions and resets initialization state.
  ///
  /// Safe to call multiple times (e.g. during testing or hot-restart).
  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    await _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription = null;
    await _messageOpenedSubscription?.cancel();
    _messageOpenedSubscription = null;
    _isInitialized = false;
  }

  /// Initialize push notification service.
  Future<void> initialize({
    required FutureOr<void> Function(String token) onTokenRefresh,
    required FutureOr<void> Function(RemoteMessage message) onMessageReceived,
    FutureOr<void> Function(RemoteMessage message)? onNotificationTap,
    FutureOr<void> Function(String token)? onTokenInvalidated,
  }) async {
    _onTokenRefresh = onTokenRefresh;
    _onTokenInvalidated = onTokenInvalidated;
    _onMessageReceived = onMessageReceived;
    _onNotificationTap = onNotificationTap;
    _notificationsEnabled = await areNotificationsEnabled();

    if (_isInitialized) {
      await _applyForegroundPresentationOptions();
      return;
    }

    try {
      await _messaging.setAutoInitEnabled(_notificationsEnabled);
      await _initializeLocalNotifications();
      _attachMessageListeners();
      await _applyForegroundPresentationOptions();

      if (_notificationsEnabled) {
        await _requestPermissionAndSyncToken();
      } else {
        await _localNotifications.cancelAll();
      }

      await _handleLaunchNotifications();
      _isInitialized = true;
      debugPrint(
        '[PushService] Initialized successfully '
        '(enabled=$_notificationsEnabled)',
      );
    } catch (e) {
      debugPrint('[PushService] Initialization error: $e');
    }
  }

  Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(notificationsEnabledKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(notificationsEnabledKey, enabled);
    _notificationsEnabled = enabled;

    await _messaging.setAutoInitEnabled(enabled);
    await _applyForegroundPresentationOptions();

    if (enabled) {
      await _requestPermissionAndSyncToken();
      debugPrint('[PushService] Notifications enabled');
      return;
    }

    await _localNotifications.cancelAll();
    final tokenToInvalidate = _fcmToken ?? await getSavedToken();
    if (tokenToInvalidate != null && tokenToInvalidate.isNotEmpty) {
      await _notifyTokenInvalidated(tokenToInvalidate);
    }

    await _messaging.deleteToken();
    _fcmToken = null;
    await _clearSavedToken();
    debugPrint('[PushService] Notifications disabled');
  }

  /// Initialize local notifications for foreground display.
  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        debugPrint('[PushService] Local notification tapped');
        await _handleLocalNotificationPayload(response.payload);
      },
    );
    _localNotificationsInitialized = true;

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'studyspace_notifications',
        'StudyShare Notifications',
        description: 'Notifications from StudyShare',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  /// Show a local notification for foreground messages.
  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (!_notificationsEnabled || !Platform.isAndroid) return;

    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'studyspace_notifications',
      'StudyShare Notifications',
      channelDescription: 'Notifications from StudyShare',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
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

    await _localNotifications.show(
      notification.hashCode,
      notification.title ?? 'StudyShare',
      notification.body ?? '',
      details,
      payload: jsonEncode(message.toMap()),
    );
  }

  /// Save token locally for comparison.
  Future<void> _saveTokenLocally(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenPrefsKey, token);
  }

  Future<void> _clearSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenPrefsKey);
  }

  /// Get locally saved token.
  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenPrefsKey);
  }

  /// Subscribe to a topic (e.g., college-specific notifications).
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('[PushService] Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('[PushService] Failed to subscribe to topic: $e');
    }
  }

  /// Unsubscribe from a topic.
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('[PushService] Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('[PushService] Failed to unsubscribe from topic: $e');
    }
  }

  /// Delete FCM token (for logout).
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
      _fcmToken = null;
      await _clearSavedToken();
      debugPrint('[PushService] FCM token deleted');
    } catch (e) {
      debugPrint('[PushService] Failed to delete token: $e');
    }
  }

  void _attachMessageListeners() {
    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((
      String newToken,
    ) async {
      if (!_notificationsEnabled || newToken.isEmpty) return;

      debugPrint('[PushService] FCM token refreshed');
      _fcmToken = newToken;
      await _saveTokenLocally(newToken);
      await _notifyTokenRefresh(newToken);
    });

    _foregroundMessageSubscription ??= FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) async {
      if (!_notificationsEnabled) {
        debugPrint(
          '[PushService] Ignoring foreground message while notifications are disabled',
        );
        return;
      }

      debugPrint(
        '[PushService] Foreground message: ${message.notification?.title}',
      );
      await _notifyMessageReceived(message);
      await _showLocalNotification(message);
    });

    _messageOpenedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen((
      RemoteMessage message,
    ) async {
      if (!_notificationsEnabled) return;

      debugPrint('[PushService] Notification tapped from system tray');
      await _notifyNotificationTap(message);
    });
  }

  Future<void> _requestPermissionAndSyncToken() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint('[PushService] Notification permission denied');
      return;
    }

    debugPrint('[PushService] Notification permission granted');
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('[PushService] No FCM token available');
      return;
    }

    _fcmToken = token;
    await _saveTokenLocally(token);
    final tokenPreviewLength = token.length < 8 ? token.length : 8;
    debugPrint(
      '[PushService] FCM token acquired '
      '(${token.substring(0, tokenPreviewLength)}...)',
    );
    await _notifyTokenRefresh(token);
  }

  Future<void> _applyForegroundPresentationOptions() async {
    final shouldShowAppleForegroundAlert =
        _notificationsEnabled && (Platform.isIOS || Platform.isMacOS);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: shouldShowAppleForegroundAlert,
      badge: _notificationsEnabled,
      sound: _notificationsEnabled,
    );
  }

  Future<void> _handleLaunchNotifications() async {
    if (!_notificationsEnabled) return;

    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    final payload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.isNotEmpty) {
      await _handleLocalNotificationPayload(payload);
      return;
    }

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[PushService] Initial FCM message received');
      await _notifyNotificationTap(initialMessage);
    }
  }

  Future<void> _handleLocalNotificationPayload(String? payload) async {
    if (payload == null || payload.isEmpty) return;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        debugPrint('[PushService] Local payload is not a JSON object');
        return;
      }

      final decodedMap = Map<String, dynamic>.from(decoded);
      final message = RemoteMessage.fromMap(decodedMap);
      await _notifyNotificationTap(message);
    } catch (e) {
      debugPrint('[PushService] Failed to parse local notification payload: $e');
    }
  }

  Future<void> _notifyTokenRefresh(String token) async {
    final callback = _onTokenRefresh;
    if (callback == null) return;
    await Future<void>.sync(() => callback(token));
  }

  Future<void> _notifyTokenInvalidated(String token) async {
    final callback = _onTokenInvalidated;
    if (callback == null) return;
    await Future<void>.sync(() => callback(token));
  }

  Future<void> _notifyMessageReceived(RemoteMessage message) async {
    final callback = _onMessageReceived;
    if (callback == null) return;
    await Future<void>.sync(() => callback(message));
  }

  Future<void> _notifyNotificationTap(RemoteMessage message) async {
    final callback = _onNotificationTap;
    if (callback == null) return;
    await Future<void>.sync(() => callback(message));
  }
}
