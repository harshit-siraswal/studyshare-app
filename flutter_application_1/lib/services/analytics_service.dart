import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';

/// Central Firebase Analytics wrapper for app-wide events and screen tracking.
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;
  late final NavigatorObserver _navigatorObserver = _AnalyticsNavigatorObserver(
    this,
  );
  String? _lastTrackedScreenName;
  DateTime? _lastTrackedScreenAt;
  String? _lastCollegeId;
  String? _lastCollegeDomain;

  /// Shared navigator observer for route-based screen tracking.
  NavigatorObserver get navigatorObserver => _navigatorObserver;

  /// Initializes Firebase Analytics after Firebase itself is ready.
  Future<void> initialize() async {
    if (_analytics != null) return;

    try {
      final analytics = FirebaseAnalytics.instance;
      await analytics.setAnalyticsCollectionEnabled(true);
      _analytics = analytics;
    } catch (e, st) {
      debugPrint('Analytics initialization failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  /// Tracks a screen transition with lightweight duplicate suppression.
  Future<void> trackScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;

    final normalizedScreenName = _normalizeScreenName(screenName);
    final now = DateTime.now();
    if (normalizedScreenName.isEmpty ||
        (_lastTrackedScreenName == normalizedScreenName &&
            _lastTrackedScreenAt != null &&
            now.difference(_lastTrackedScreenAt!) <
                const Duration(seconds: 1))) {
      return;
    }

    _lastTrackedScreenName = normalizedScreenName;
    _lastTrackedScreenAt = now;
    try {
      await analytics.logScreenView(
        screenName: normalizedScreenName,
        screenClass: screenClass ?? normalizedScreenName,
      );
    } catch (e, st) {
      debugPrint('Analytics screen tracking failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  /// Logs a custom analytics event with sanitized parameter names and values.
  Future<void> logEvent(
    String name, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;

    final normalizedName = _normalizeEventName(name);
    if (normalizedName.isEmpty) return;

    final normalizedParameters = _normalizeParameters(parameters);

    try {
      await analytics.logEvent(
        name: normalizedName,
        parameters: normalizedParameters.isEmpty ? null : normalizedParameters,
      );
    } catch (e, st) {
      debugPrint('Analytics event "$normalizedName" failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  /// Sets or clears signed-in user context on the current analytics session.
  Future<void> setUserContext({
    required String? userId,
    String? authProvider,
    bool? emailVerified,
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;

    try {
      await analytics.setUserId(id: _normalizeUserId(userId));
      await analytics.setUserProperty(
        name: 'auth_provider',
        value: _normalizeUserPropertyValue(authProvider),
      );
      await analytics.setUserProperty(
        name: 'email_verified',
        value: emailVerified == null
            ? null
            : (emailVerified ? 'true' : 'false'),
      );
    } catch (e, st) {
      debugPrint('Analytics user context update failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  /// Clears signed-in user context after logout or session expiration.
  Future<void> clearUserContext() async {
    await setUserContext(userId: null, authProvider: null, emailVerified: null);
  }

  /// Sets the currently selected college context for segmentation.
  Future<void> setCollegeContext({
    String? collegeId,
    String? collegeDomain,
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;

    final normalizedCollegeId = _normalizeUserPropertyValue(collegeId);
    final normalizedCollegeDomain = _normalizeUserPropertyValue(collegeDomain);
    if (_lastCollegeId == normalizedCollegeId &&
        _lastCollegeDomain == normalizedCollegeDomain) {
      return;
    }

    _lastCollegeId = normalizedCollegeId;
    _lastCollegeDomain = normalizedCollegeDomain;

    try {
      await analytics.setUserProperty(
        name: 'college_id',
        value: normalizedCollegeId,
      );
      await analytics.setUserProperty(
        name: 'college_domain',
        value: normalizedCollegeDomain,
      );
    } catch (e, st) {
      debugPrint('Analytics college context update failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  void trackRoute(Route<dynamic> route) {
    final routeName = route.settings.name?.trim();
    if (routeName == null || routeName.isEmpty) return;
    unawaited(trackScreenView(screenName: routeName));
  }

  String _normalizeEventName(String value) {
    var normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    normalized = normalized.replaceAll(RegExp(r'_+'), '_');
    normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) return '';
    if (!RegExp(r'^[a-z]').hasMatch(normalized)) {
      normalized = 'evt_$normalized';
    }
    if (normalized.length > 40) {
      normalized = normalized.substring(0, 40);
    }
    return normalized.replaceAll(RegExp(r'_+$'), '');
  }

  String _normalizeParameterName(String value) {
    final normalized = _normalizeEventName(value);
    if (normalized.isEmpty) return '';
    return normalized.length <= 40
        ? normalized
        : normalized.substring(0, 40).replaceAll(RegExp(r'_+$'), '');
  }

  Map<String, Object> _normalizeParameters(Map<String, Object?> parameters) {
    final normalized = <String, Object>{};
    for (final entry in parameters.entries) {
      final key = _normalizeParameterName(entry.key);
      final value = _normalizeParameterValue(entry.value);
      if (key.isEmpty || value == null) continue;
      normalized[key] = value;
    }
    return normalized;
  }

  Object? _normalizeParameterValue(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is bool) return value ? 1 : 0;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return text.length <= 100 ? text : text.substring(0, 100);
  }

  String _normalizeScreenName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final parsed = Uri.tryParse(trimmed);
    final canonical = parsed != null && parsed.path.trim().isNotEmpty
        ? parsed.path.trim()
        : trimmed.split('?').first.trim();
    final collapsed = canonical.replaceAll(RegExp(r'\s+'), '_');
    return collapsed.length <= 60 ? collapsed : collapsed.substring(0, 60);
  }

  String? _normalizeUserId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length <= 256 ? trimmed : trimmed.substring(0, 256);
  }

  String? _normalizeUserPropertyValue(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length <= 36 ? trimmed : trimmed.substring(0, 36);
  }
}

class _AnalyticsNavigatorObserver extends NavigatorObserver {
  _AnalyticsNavigatorObserver(this._analyticsService);

  final AnalyticsService _analyticsService;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _analyticsService.trackRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _analyticsService.trackRoute(previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _analyticsService.trackRoute(newRoute);
    }
  }
}
