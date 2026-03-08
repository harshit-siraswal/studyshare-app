import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[PushService] Background message: ${message.messageId}');
  // Background messages are handled by the system notification tray
}

/// Service for handling Firebase Cloud Messaging (FCM) push notifications
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  String? _fcmToken;
  bool _isInitialized = false;

  /// Get the current FCM token
  String? get fcmToken => _fcmToken;

  /// Initialize push notification service
  Future<void> initialize({
    required Function(String token) onTokenRefresh,
    required Function(RemoteMessage message) onMessageReceived,
    Function(RemoteMessage message)? onNotificationTap,
  }) async {
    if (_isInitialized) return;

    try {
      // Request permission
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('[PushService] Notification permission granted');
        
        // Get FCM token
        _fcmToken = await _messaging.getToken();
        if (_fcmToken != null && _fcmToken!.isNotEmpty) {
          final tokenPreviewLength = _fcmToken!.length < 8
              ? _fcmToken!.length
              : 8;
          debugPrint(
            '[PushService] FCM token acquired '
            '(${_fcmToken!.substring(0, tokenPreviewLength)}...)',
          );
        }
        
        if (_fcmToken != null) {
          onTokenRefresh(_fcmToken!);
          _saveTokenLocally(_fcmToken!);
        }

        // Listen for token refresh
        _messaging.onTokenRefresh.listen((newToken) {
          debugPrint('[PushService] FCM Token refreshed: $newToken');
          _fcmToken = newToken;
          onTokenRefresh(newToken);
          _saveTokenLocally(newToken);
        });

        // Configure foreground notification presentation
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Initialize local notifications for foreground display
        await _initializeLocalNotifications(onNotificationTap);

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen((message) {
          debugPrint('[PushService] Foreground message: ${message.notification?.title}');
          onMessageReceived(message);
          _showLocalNotification(message);
        });

        // Handle notification tap when app is in background
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          debugPrint('[PushService] Notification tapped (background): ${message.data}');
          if (onNotificationTap != null) {
            onNotificationTap(message);
          }
        });

        // Check for initial message (app opened from terminated state via notification)
        final initialMessage = await _messaging.getInitialMessage();
        if (initialMessage != null && onNotificationTap != null) {
          debugPrint('[PushService] Initial message: ${initialMessage.data}');
          onNotificationTap(initialMessage);
        }

        _isInitialized = true;
        debugPrint('[PushService] Initialized successfully');
      } else {
        debugPrint('[PushService] Notification permission denied');
      }
    } catch (e) {
      debugPrint('[PushService] Initialization error: $e');
    }
  }

  /// Initialize local notifications for foreground display
  Future<void> _initializeLocalNotifications(Function(RemoteMessage)? onTap) async {
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
      onDidReceiveNotificationResponse: (response) {
        debugPrint('[PushService] Local notification tapped: ${response.payload}');
        // Handle notification tap - parse payload and navigate
      },
    );

    // Create notification channel for Android
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
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Show a local notification for foreground messages
  Future<void> _showLocalNotification(RemoteMessage message) async {
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
      payload: message.data.toString(),
    );
  }

  /// Save token locally for comparison
  Future<void> _saveTokenLocally(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
  }

  /// Get locally saved token
  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fcm_token');
  }

  /// Subscribe to a topic (e.g., college-specific notifications)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('[PushService] Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('[PushService] Failed to subscribe to topic: $e');
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('[PushService] Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('[PushService] Failed to unsubscribe from topic: $e');
    }
  }

  /// Delete FCM token (for logout)
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
      _fcmToken = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fcm_token');
      debugPrint('[PushService] FCM token deleted');
    } catch (e) {
      debugPrint('[PushService] Failed to delete token: $e');
    }
  }
}
