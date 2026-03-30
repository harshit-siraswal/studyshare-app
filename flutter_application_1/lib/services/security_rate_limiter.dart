class LocalRateLimitException implements Exception {
  const LocalRateLimitException({
    required this.scope,
    required this.retryAfter,
    required this.message,
  });

  final String scope;
  final Duration retryAfter;
  final String message;

  @override
  String toString() => message;
}

class LocalRateLimitDecision {
  const LocalRateLimitDecision({
    required this.allowed,
    required this.retryAfter,
    required this.remaining,
  });

  final bool allowed;
  final Duration retryAfter;
  final int remaining;
}

class SlidingWindowRateLimiter {
  final Map<String, List<DateTime>> _eventsByKey = <String, List<DateTime>>{};
  final Map<String, DateTime> _lastAccessByKey = <String, DateTime>{};
  static const int _maxTrackedKeys = 2048;

  void _markAccess(String key, DateTime now) {
    _lastAccessByKey[key] = now;
  }

  void _removeKey(String key) {
    _eventsByKey.remove(key);
    _lastAccessByKey.remove(key);
  }

  void _evictLeastRecentlyUsedKeyIfNeeded() {
    if (_eventsByKey.length <= _maxTrackedKeys) return;
    String? oldestKey;
    DateTime? oldestAccess;
    _lastAccessByKey.forEach((key, accessedAt) {
      if (!_eventsByKey.containsKey(key)) return;
      if (oldestAccess == null || accessedAt.isBefore(oldestAccess!)) {
        oldestAccess = accessedAt;
        oldestKey = key;
      }
    });
    if (oldestKey != null) {
      _removeKey(oldestKey!);
    }
  }

  LocalRateLimitDecision checkAndConsume(
    String key, {
    required int maxEvents,
    required Duration window,
    int cost = 1,
    DateTime? now,
  }) {
    if (cost <= 0) {
      throw ArgumentError.value(cost, 'cost', 'must be greater than 0');
    }
    if (maxEvents <= 0) {
      throw ArgumentError.value(
        maxEvents,
        'maxEvents',
        'must be greater than 0',
      );
    }
    if (window <= Duration.zero) {
      throw ArgumentError.value(window, 'window', 'must be greater than zero');
    }

    final currentTime = now ?? DateTime.now().toUtc();
    _markAccess(key, currentTime);
    final events = _eventsByKey.putIfAbsent(key, () => <DateTime>[]);
    final cutoff = currentTime.subtract(window);
    events.removeWhere((timestamp) => timestamp.isBefore(cutoff));
    if (events.isEmpty) {
      _removeKey(key);
      _eventsByKey[key] = <DateTime>[];
    }

    if (cost > maxEvents) {
      return const LocalRateLimitDecision(
        allowed: false,
        retryAfter: Duration.zero,
        remaining: 0,
      );
    }

    final activeEvents = _eventsByKey.putIfAbsent(key, () => <DateTime>[]);

    if (activeEvents.length + cost > maxEvents) {
      final oldest = activeEvents.isEmpty ? currentTime : activeEvents.first;
      final retryAfter = oldest.add(window).difference(currentTime);
      return LocalRateLimitDecision(
        allowed: false,
        retryAfter: retryAfter.isNegative ? Duration.zero : retryAfter,
        remaining: 0,
      );
    }

    activeEvents.addAll(List<DateTime>.filled(cost, currentTime));
    _evictLeastRecentlyUsedKeyIfNeeded();

    return LocalRateLimitDecision(
      allowed: true,
      retryAfter: Duration.zero,
      remaining: maxEvents - activeEvents.length,
    );
  }

  void clear(String key) {
    _eventsByKey.remove(key);
  }

  void clearAll() {
    _eventsByKey.clear();
  }
}
