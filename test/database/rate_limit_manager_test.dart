import 'package:firestore_optimize/firestore_optimize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RateLimitManager', () {
    late RateLimitManager rateLimiter;

    setUp(() {
    });

    tearDown(() {
      rateLimiter.dispose();
    });

    group('checkRateLimit', () {
      test('allows requests within rate limit', () async {
        rateLimiter = RateLimitManager(maxRequests: 3);

        // First request should pass immediately
        final stopwatch = Stopwatch()..start();
        await rateLimiter.checkRateLimit(FirestorePath('/test/path'), 'test_action', batched: true);
        stopwatch.stop();

        // Should complete quickly (within 100ms)
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });

      test('allows multiple requests up to the limit', () async {
        rateLimiter = RateLimitManager(maxRequests: 3);

        final stopwatch = Stopwatch()..start();

        // Make 3 requests (at the limit)
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'test_action', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path3'), 'test_action', batched: true);

        stopwatch.stop();

        // All should complete quickly
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });

      test('throttles requests exceeding rate limit', () async {
        rateLimiter = RateLimitManager(
          maxRequests: 2,
          rateLimitWindow: const Duration(milliseconds: 500),
        );

        // Make 2 requests to reach the limit
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'test_action', batched: true);

        // Third request should be throttled
        final stopwatch = Stopwatch()..start();
        await rateLimiter.checkRateLimit(FirestorePath('/test/path3'), 'test_action', batched: true);
        stopwatch.stop();

        // Should take at least the rate limit window duration
        expect(stopwatch.elapsedMilliseconds, greaterThan(400));
      });

      test('releases throttled requests after window expires', () async {
        rateLimiter = RateLimitManager(
          maxRequests: 1,
          rateLimitWindow: const Duration(milliseconds: 200),
        );

        // First request
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);

        // Second request should be throttled
        final future = rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'test_action', batched: true);

        // Wait for the window to expire
        await Future<void>.delayed(const Duration(milliseconds: 250));

        // The throttled request should now complete
        await expectLater(future, completes);
      });

      test('handles multiple concurrent throttled requests', () async {
        rateLimiter = RateLimitManager(
          maxRequests: 1,
          rateLimitWindow: const Duration(milliseconds: 300),
        );

        // First request to reach the limit
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);

        // Start multiple throttled requests
        final futures = <Future<void>>[];
        for (int i = 0; i < 3; i++) {
          futures.add(rateLimiter.checkRateLimit(FirestorePath('/test/path$i'), 'test_action', batched: true));
        }

        // All should eventually complete
        await expectLater(Future.wait(futures), completes);
      });
    });

    group('removeCount', () {
      test('removes batch together', () async {
        rateLimiter = RateLimitManager(maxRequests: 3, rateLimitWindow: const Duration(seconds: 10));

        // Make 3 requests to reach the limit
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true).then((value) {
          // Simulate how the result of the release would also release the next request
          rateLimiter.release(FirestorePath('/test/path1'), 1);
        });
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true).then((value) {
          // Simulate how the result of the release would also release the next request
          rateLimiter.release(FirestorePath('/test/path1'), 1);
        });

        rateLimiter.release(FirestorePath('/test/path1'), 1); // Manually trigger the first release

        // Should now be able to make 2 more requests immediately
        final stopwatch = Stopwatch()..start();
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'test_action', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path3'), 'test_action', batched: true);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });

      test('removes specified number of request counts', () async {
        rateLimiter = RateLimitManager(maxRequests: 3);

        // Make 3 requests to reach the limit
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'test_action', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path3'), 'test_action', batched: true);

        // Remove 2 counts
        rateLimiter.release(FirestorePath('/test/path1'), 2);

        // Should now be able to make 2 more requests immediately
        final stopwatch = Stopwatch()..start();
        await rateLimiter.checkRateLimit(FirestorePath('/test/path4'), 'test_action', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path5'), 'test_action', batched: true);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });

      test('handles removing more counts than available', () async {
        rateLimiter = RateLimitManager(maxRequests: 3);

        // Make 1 request
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);

        // Try to remove 5 counts (more than available)
        rateLimiter.release(FirestorePath('/test/path1'), 5);

        // Should still be able to make requests
        final stopwatch = Stopwatch()..start();
        await rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'test_action', batched: true);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });

      test('releases pending requests after removing counts', () async {
        rateLimiter = RateLimitManager(
          maxRequests: 1,
          rateLimitWindow: const Duration(seconds: 2), // Long window
        );

        // First request to reach the limit
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);

        // Start a throttled request
        final throttledFuture = rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'test_action', batched: true);

        // Wait a bit to ensure it's queued
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Remove the count to free up space
        rateLimiter.release(FirestorePath('/test/path1'), 1);

        // The throttled request should now complete quickly
        final stopwatch = Stopwatch()..start();
        await throttledFuture;
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(200));
      });
    });

    group('rush', () {
      test('immediately completes all pending requests', () async {
        rateLimiter = RateLimitManager(
          maxRequests: 1,
          rateLimitWindow: const Duration(seconds: 10), // Long window
        );

        // First request to reach the limit
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);

        // Start multiple throttled requests
        final futures = <Future<void>>[];
        for (int i = 0; i < 3; i++) {
          futures.add(rateLimiter.checkRateLimit(FirestorePath('/test/path$i'), 'test_action', batched: true));
        }

        // Wait a bit to ensure they're queued
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Rush all pending requests
        final stopwatch = Stopwatch()..start();
        rateLimiter.rush();

        // All should complete immediately
        await Future.wait(futures);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      });

      test('handles rush when no pending requests', () {
        rateLimiter = RateLimitManager();

        // Should not throw when no pending requests
        expect(() => rateLimiter.rush(), returnsNormally);
      });

      test('handles rush with already completed requests', () async {
        rateLimiter = RateLimitManager(maxRequests: 2);

        // Make some requests that complete normally
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'test_action', batched: true);

        // Rush should not affect completed requests
        expect(() => rateLimiter.rush(), returnsNormally);
      });
    });

    group('dispose', () {
      test('cancels pending timers and completes pending requests', () async {
        rateLimiter = RateLimitManager(
          maxRequests: 1,
          rateLimitWindow: const Duration(seconds: 10),
        );

        // First request to reach the limit
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);

        // Start a throttled request
        final throttledFuture = rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'test_action', batched: true);

        // Wait a bit to ensure it's queued
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Dispose should complete the pending request
        rateLimiter.dispose();

        // The throttled request should complete
        await expectLater(throttledFuture, completes);
      });

      test('can be called multiple times safely', () {
        rateLimiter = RateLimitManager();

        // Multiple dispose calls should not throw
        expect(() {
          rateLimiter.dispose();
          rateLimiter.dispose();
          rateLimiter.dispose();
        }, returnsNormally);
      });
    });

    group('edge cases', () {
      test('handles very short rate limit window', () async {
        rateLimiter = RateLimitManager(
          maxRequests: 1,
          rateLimitWindow: const Duration(milliseconds: 1),
        );

        // First request
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);

        // Wait for window to expire
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Second request should be allowed
        final stopwatch = Stopwatch()..start();
        await rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'test_action', batched: true);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(50));
      });

      test('handles concurrent access with same lock', () async {
        rateLimiter = RateLimitManager(maxRequests: 2, rateLimitWindow: Duration(seconds: 2));

        // Start multiple concurrent requests
        final futures = <Future<void>>[];
        for (int i = 0; i < 5; i++) {
          futures.add(rateLimiter.checkRateLimit(FirestorePath('/test/path$i'), 'test_action', batched: true));
        }

        // All should eventually complete
        await expectLater(Future.wait(futures), completes);
      });

      test('maintains request order in queue', () async {
        rateLimiter = RateLimitManager(
          maxRequests: 1,
          rateLimitWindow: const Duration(milliseconds: 100),
        );

        // First request to reach the limit
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'test_action', batched: true);

        final completionOrder = <int>[];
        final futures = <Future<void>>[];

        // Start multiple throttled requests
        for (int i = 0; i < 3; i++) {
          final index = i;
          futures.add(
            rateLimiter.checkRateLimit(FirestorePath('/test/path$i'), 'test_action', batched: true).then((_) {
              completionOrder.add(index);
            }),
          );
        }

        // Wait for all to complete
        await Future.wait(futures);

        // Should complete in order (FIFO)
        expect(completionOrder, [0, 1, 2]);
      });
    });

    group('integration scenarios', () {
      test('simulates realistic database operation pattern', () async {
        rateLimiter = RateLimitManager(
          maxRequests: 3,
          rateLimitWindow: const Duration(milliseconds: 200),
        );

        final operations = <String>[];

        // Simulate burst of operations
        final futures = <Future<void>>[];
        for (int i = 0; i < 6; i++) {
          futures.add(
            rateLimiter.checkRateLimit(FirestorePath('/docs/doc$i'), 'write', batched: true).then((_) {
              operations.add('doc$i');
            }),
          );
        }

        await Future.wait(futures);

        // All operations should complete
        expect(operations.length, 6);
        expect(operations.toSet().length, 6); // All unique
      });

      test('handles mixed operations with removeCount', () async {
        rateLimiter = RateLimitManager(
          maxRequests: 2,
          rateLimitWindow: const Duration(milliseconds: 300),
        );

        // Fill up the rate limit
        await rateLimiter.checkRateLimit(FirestorePath('/test/path1'), 'write', batched: true);
        await rateLimiter.checkRateLimit(FirestorePath('/test/path2'), 'write', batched: true);

        // Start a throttled operation
        final throttledFuture = rateLimiter.checkRateLimit(FirestorePath('/test/path3'), 'write', batched: true);

        // Simulate a batch completion that frees up some quota
        await Future<void>.delayed(const Duration(milliseconds: 50));
        rateLimiter.release(FirestorePath('/test/path1'), 1);

        // The throttled operation should complete
        await expectLater(throttledFuture, completes);
      });
    });
  });
}
