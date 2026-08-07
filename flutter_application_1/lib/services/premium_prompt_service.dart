import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subscription_service.dart';

/// Manages periodic premium prompts shown to free users.
///
/// Logic:
/// - Show once per session after [kUsageDelayBeforePrompt] of active usage.
/// - Minimum [kMinGapBetweenPrompts] gap between prompts.
/// - Never show to premium users.
/// - Never show more than once per app session.
class PremiumPromptService {
  PremiumPromptService({SubscriptionService? subscriptionService})
      : _subscriptionService = subscriptionService ?? SubscriptionService();

  static const String _lastShownKey = 'premium_prompt_last_shown';
  static const Duration kUsageDelayBeforePrompt = Duration(minutes: 5);
  static const Duration kMinGapBetweenPrompts = Duration(hours: 24);

  final SubscriptionService _subscriptionService;

  /// Fires `true` exactly once per session when a prompt should be shown.
  final ValueNotifier<bool> shouldShowPrompt = ValueNotifier(false);

  Timer? _usageTimer;
  bool _promptShownThisSession = false;
  bool _disposed = false;

  /// Call once from the home screen's [initState].
  void startTracking() {
    if (_promptShownThisSession || _disposed) return;
    _usageTimer?.cancel();
    _usageTimer = Timer(kUsageDelayBeforePrompt, _evaluatePrompt);
  }

  Future<void> _evaluatePrompt() async {
    if (_promptShownThisSession || _disposed) return;

    // Never show to premium users.
    try {
      final isPremium = await _subscriptionService.isPremium();
      if (isPremium) return;
    } catch (_) {
      // If the check fails, skip this session to be safe.
      return;
    }

    // Enforce minimum gap.
    final prefs = await SharedPreferences.getInstance();
    final lastShownMs = prefs.getInt(_lastShownKey) ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastShownMs;
    if (elapsed < kMinGapBetweenPrompts.inMilliseconds) return;

    // Fire the prompt.
    _promptShownThisSession = true;
    if (!_disposed) {
      shouldShowPrompt.value = true;
    }
  }

  /// Call after the user dismisses or interacts with the prompt.
  Future<void> markPromptShown() async {
    _promptShownThisSession = true;
    shouldShowPrompt.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lastShownKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  void dispose() {
    _disposed = true;
    _usageTimer?.cancel();
    _usageTimer = null;
  }
}
