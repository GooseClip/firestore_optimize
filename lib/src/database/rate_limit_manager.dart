import 'dart:async';
import 'dart:collection';
import 'operations.dart';

class RateLimitManager {
  RateLimitManager({this.rateLimitWindow = const Duration(seconds: 60), this.maxRequests = 100});

  static bool enabled = true;
  final Duration rateLimitWindow;
  final int maxRequests;

  final Queue<DateTime> _requestTimestamps = Queue<DateTime>();

  // Track pending requests to implement proper queuing
  final Queue<Completer<void>> _pendingRequests = Queue<Completer<void>>();
  Timer? _releaseTimer;

  bool _shouldThrottle() {
    final now = DateTime.now();
    final cutoff = now.subtract(rateLimitWindow);

    // Remove timestamps older than the duration
    while (_requestTimestamps.isNotEmpty && _requestTimestamps.first.isBefore(cutoff)) {
      _requestTimestamps.removeFirst();
    }

    // Check if the limit is exceeded
    if (_requestTimestamps.length >= maxRequests) {
      return true;
    }

    // Add the current timestamp only if not throttling
    _requestTimestamps.addLast(now);
    return false;
  }

  Future<void> checkRateLimit(FirestorePath path, String debugAction, {required bool batched}) async {
    final shouldThrottle = _shouldThrottle();

    if (!shouldThrottle) {
      return;
    }

    await _enqueueRequest(path, batched);
  }

  final _tracker = <FirestorePath, List<Completer<void>>>{};
  Future<void> _enqueueRequest(FirestorePath path, bool batched) async {
    final completer = Completer<void>();

    _pendingRequests.addLast(completer);

    _scheduleNextRelease();

    // Only batched requests are candidate for bulk release
    if (batched) {
      // Track completers for paths so we can release together when one releases
      _tracker[path] ??= [];
      _tracker[path]!.add(completer);
    }
    // Wait for this request to be released
    await completer.future;

    if (batched) {
      _tracker[path]?.remove(completer);
      if (_tracker[path] != null && _tracker[path]!.isEmpty) {
        _tracker.remove(path);
      }
    }
  }

  void _scheduleNextRelease() {
    // Don't schedule if already scheduled or no pending requests
    if (_pendingRequests.isEmpty) {
      return;
    }

    _releaseTimer?.cancel();

    // Calculate when the next slot becomes available
    final now = DateTime.now();
    final cutoff = now.subtract(rateLimitWindow);

    // Remove old timestamps
    while (_requestTimestamps.isNotEmpty && _requestTimestamps.first.isBefore(cutoff)) {
      _requestTimestamps.removeFirst();
    }

    Duration delay;
    if (_requestTimestamps.length < maxRequests) {
      // We have available slots, release immediately
      delay = Duration.zero;
    } else {
      // Calculate when the oldest request will expire
      final oldestRequest = _requestTimestamps.first;
      final timeUntilExpiry = oldestRequest.add(rateLimitWindow).difference(now);
      delay = timeUntilExpiry.isNegative ? Duration.zero : timeUntilExpiry;

      // Add a small buffer to avoid race conditions
      delay = delay + Duration(milliseconds: 10);
    }

    _releaseTimer = Timer(delay, _releaseNextRequest);
  }

  void _releaseNextRequest() {
    _releaseTimer = null;

    if (_pendingRequests.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final cutoff = now.subtract(rateLimitWindow);

    // Clean up old timestamps
    while (_requestTimestamps.isNotEmpty && _requestTimestamps.first.isBefore(cutoff)) {
      _requestTimestamps.removeFirst();
    }

    // Check if we can release a request
    if (_requestTimestamps.length < maxRequests) {
      final completer = _pendingRequests.removeFirst();
      _requestTimestamps.addLast(now);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    // Schedule the next release

    _scheduleNextRelease();
  }

  // Release will release all completers with matching path
  void release(FirestorePath path, int count) {
    if (_tracker.containsKey(path)) {
      final matching = [..._tracker[path]!]; // clone since completing will modify list (when it completes)
      for (var c in matching) {
        if (!c.isCompleted) {
          c.complete();
        }
      }
    }

    for (var i = 0; i < count; i++) {
      if (_requestTimestamps.isEmpty) {
        break;
      }
      _requestTimestamps.removeFirst();
    }

    // After removing counts, we might be able to release pending requests

    _scheduleNextRelease();
  }

  void rush() {
    while (_pendingRequests.isNotEmpty) {
      final completer = _pendingRequests.removeFirst();
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  // Clean up method to cancel pending requests if needed
  void dispose() {
    _releaseTimer?.cancel();
    _releaseTimer = null;

    // Complete all pending requests with an error or just complete them
    rush();
  }
}
