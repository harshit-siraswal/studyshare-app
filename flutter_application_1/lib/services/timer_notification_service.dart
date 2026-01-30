import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing study timer with persistent notifications.
/// 
/// Features:
/// - Timer runs in background
/// - Shows persistent notification with elapsed time
/// - Saves state to SharedPreferences for recovery
class TimerNotificationService {
  static final TimerNotificationService _instance = TimerNotificationService._internal();
  factory TimerNotificationService() => _instance;
  TimerNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  DateTime? _startTime;
  bool _isRunning = false;
  String? _currentPdfName;
  
  // Notification constants
  static const int _notificationId = 888;
  static const String _channelId = 'study_timer_channel';
  static const String _channelName = 'Study Timer';
  
  // SharedPreferences keys
  static const String _prefStartTime = 'timer_start_time';
  static const String _prefPdfName = 'timer_pdf_name';
  static const String _prefIsRunning = 'timer_is_running';

  // Callbacks for UI updates
  final List<VoidCallback> _listeners = [];
  
  bool get isRunning => _isRunning;
  Duration get elapsed => _elapsed;
  String? get currentPdfName => _currentPdfName;

  /// Initialize the notification service. Call this in main.dart
  Future<void> initialize() async {
    // Android initialization
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS initialization
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(initSettings);
    
    // Create notification channel for Android
    await _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Shows study timer progress',
        importance: Importance.low, // Low to avoid sounds
        playSound: false,
        enableVibration: false,
      ),
    );
    
    // Restore timer state if it was running
    await _restoreState();
  }

  /// Start the timer
  Future<void> start({String? pdfName}) async {
    if (_isRunning) return;
    
    _isRunning = true;
    _startTime = DateTime.now();
    _currentPdfName = pdfName;
    _elapsed = Duration.zero;
    
    // Save state
    await _saveState();
    
    // Start the tick timer
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick();
    });
    
    // Show initial notification
    await _showNotification();
    _notifyListeners();
  }

  /// Stop the timer
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    
    // Cancel notification
    await _notifications.cancel(_notificationId);
    
    // Clear saved state
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefStartTime);
    await prefs.remove(_prefPdfName);
    await prefs.remove(_prefIsRunning);
    
    _notifyListeners();
  }

  /// Pause the timer (keeps elapsed time)
  void pause() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _notifyListeners();
  }

  /// Resume the timer
  void resume() {
    if (_isRunning) return;
    
    _isRunning = true;
    _startTime = DateTime.now().subtract(_elapsed);
    
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick();
    });
    
    _notifyListeners();
  }

  void _tick() {
    if (_startTime != null) {
      _elapsed = DateTime.now().difference(_startTime!);
      _showNotification();
      _notifyListeners();
    }
  }

  Future<void> _showNotification() async {
    final title = _currentPdfName != null 
        ? 'Studying: $_currentPdfName' 
        : 'Study Timer Running';
    
    final body = _formatDuration(_elapsed);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Shows study timer progress',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true, // Makes it persistent
      autoCancel: false,
      showWhen: false,
      playSound: false,
      enableVibration: false,
      // Actions
      actions: [
        const AndroidNotificationAction(
          'stop',
          'Stop',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      _notificationId,
      title,
      body,
      details,
    );
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_startTime != null) {
      await prefs.setString(_prefStartTime, _startTime!.toIso8601String());
    }
    if (_currentPdfName != null) {
      await prefs.setString(_prefPdfName, _currentPdfName!);
    }
    await prefs.setBool(_prefIsRunning, _isRunning);
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    final wasRunning = prefs.getBool(_prefIsRunning) ?? false;
    
    if (wasRunning) {
      final startTimeStr = prefs.getString(_prefStartTime);
      if (startTimeStr != null) {
        _startTime = DateTime.parse(startTimeStr);
        _currentPdfName = prefs.getString(_prefPdfName);
        _elapsed = DateTime.now().difference(_startTime!);
        _isRunning = true;
        
        // Resume the timer
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          _tick();
        });
        
        await _showNotification();
      }
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Add a listener for timer updates
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }
}
