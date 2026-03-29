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

  LocalRateLimitDecision checkAndConsume(
    String key, {
    required int maxEvents,
    required Duration window,
    int cost = 1,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now().toUtc();
    final events = _eventsByKey.putIfAbsent(key, () => <DateTime>[]);
    final cutoff = currentTime.subtract(window);
    events.removeWhere((timestamp) => timestamp.isBefore(cutoff));

    if (events.length + cost > maxEvents) {
      final oldest = events.isEmpty ? currentTime : events.first;
      final retryAfter = oldest.add(window).difference(currentTime);
      return LocalRateLimitDecision(
        allowed: false,
        retryAfter: retryAfter.isNegative ? Duration.zero : retryAfter,
        remaining: 0,
      );
    }

    for (var i = 0; i < cost; i++) {
      events.add(currentTime);
    }

    return LocalRateLimitDecision(
      allowed: true,
      retryAfter: Duration.zero,
      remaining: maxEvents - events.length,
    );
  }

  void clear(String key) {
    _eventsByKey.remove(key);
  }

  void clearAll() {
    _eventsByKey.clear();
  }
}
