import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class StudyTimerController extends ChangeNotifier with WidgetsBindingObserver {
  static final StudyTimerController _instance = StudyTimerController._internal();
  factory StudyTimerController() => _instance;
  
  StudyTimerController._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  // Timer state
  int _selectedMinutes = 25; // Default Pomodoro
  int _remainingSeconds = 25 * 60;
  bool _isRunning = false;
  Timer? _timer;
  DateTime? _endTime;
  
  // Stats
  int _sessionCount = 0;
  int _totalMinutes = 0;

  // Getters
  int get selectedMinutes => _selectedMinutes;
  int get remainingSeconds => _remainingSeconds;
  bool get isRunning => _isRunning;
  int get sessionCount => _sessionCount;
  int get totalMinutes => _totalMinutes;
  double get progress => _selectedMinutes > 0 ? 1 - (_remainingSeconds / (_selectedMinutes * 60)) : 0;
  String get formattedTime => formatTime(_remainingSeconds);

  @override
  void dispose() {
    // Note: Since this is a singleton that lives for the app lifecycle, 
    // dispose might only be called on app termination or if manually cleaned up.
    // Unregistering the observer is critical to prevent leaks.
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Cancels the active timer without disposing the singleton.
  /// Call this when pausing app or cleaning up resources temporarily.
  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning && _endTime != null) {
      _reconcileTime();
    }
  }

  void _reconcileTime() {
    final now = DateTime.now();
    if (now.isAfter(_endTime!)) {
      _stopTimer(completed: true);
    } else {
      _remainingSeconds = _endTime!.difference(now).inSeconds;
      notifyListeners();
    }
  }
  void startTimer() {
    if (_isRunning) return;
    
    if (_remainingSeconds <= 0) {
      _remainingSeconds = _selectedMinutes * 60;
    }
    
    _isRunning = true;
    _endTime = DateTime.now().add(Duration(seconds: _remainingSeconds));
    notifyListeners();
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        notifyListeners();
      } else {
        _stopTimer(completed: true);
      }
    });
  }

  void pauseTimer() {
    _timer?.cancel();
    _isRunning = false;
    _endTime = null; // Clear end time on manual pause
    notifyListeners();
  }

  void _stopTimer({bool completed = false}) {
    _timer?.cancel();
    _isRunning = false;
    _endTime = null;
    if (completed) {
      _sessionCount++;
      _totalMinutes += _selectedMinutes;
      _remainingSeconds = 0;
    }
    notifyListeners();
  }

  void resetTimer() {
    _timer?.cancel();
    _isRunning = false;
    _endTime = null;
    _remainingSeconds = _selectedMinutes * 60;
    notifyListeners();
  }

  bool setDuration(int minutes) {
    if (minutes <= 0 || minutes > 300) {
      debugPrint('Invalid duration: $minutes. Must be between 1 and 300.');
      return false; 
    }
    _timer?.cancel();
    _selectedMinutes = minutes;
    _remainingSeconds = minutes * 60;
    _isRunning = false;
    _endTime = null;
    notifyListeners();
    return true;
  }

  void addTime(int seconds) {
    if (seconds <= 0) return;
    _remainingSeconds += seconds;
    
    // Update total duration to keep progress valid
    if (_remainingSeconds > _selectedMinutes * 60) {
        _selectedMinutes = (_remainingSeconds / 60).ceil(); 
    }
    
    // Adjust end time if running
    if (_isRunning && _endTime != null) {
      _endTime = _endTime!.add(Duration(seconds: seconds));
    }
    
    notifyListeners();
  }

  static String formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // Overlay System Window Logic
  Future<void> showOverlay() async {
    // This requires platform channel implementation or the system_alert_window package usage.
    // For now, we will notify listeners that overlay mode is requested.
    // In a real implementation, you'd call SystemAlertWindow.showSystemWindow(...) here.
    debugPrint('Showing system overlay...');
    // Implementation detail: The actual overlay draw is often handled by the native side or a specific plugin method.
    // We will simulate the state here.
  }

  Future<void> closeOverlay() async {
    debugPrint('Closing system overlay...');
    // SystemAlertWindow.closeSystemWindow();
  }
}
