import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/realtime/long_poll_client.dart';

/// Slice 3B — generic long-poll client behaviour.
///
/// We drive the client with a scripted poll function so we can deterministically
/// exercise: (1) two successful batches in order, (2) an error that triggers
/// backoff and retry, (3) reset of backoff after the next success, (4)
/// stop() cleanly terminates the loop.
void main() {
  group('LongPollClient', () {
    test('emits two batches in order, then retries after timeout', () async {
      final List<Duration> sleeps = <Duration>[];
      int call = 0;
      final List<DateTime?> sinceSeen = <DateTime?>[];

      final LongPollClient<List<String>> client = LongPollClient<List<String>>(
        sleep: (Duration d) async {
          sleeps.add(d);
        },
        poll: (DateTime? since) async {
          sinceSeen.add(since);
          call++;
          switch (call) {
            case 1:
              return LongPollResponse<List<String>>(
                items: <String>['a', 'b'],
                serverNow: DateTime.utc(2026, 5, 18, 10),
              );
            case 2:
              return LongPollResponse<List<String>>(
                items: <String>['c'],
                serverNow: DateTime.utc(2026, 5, 18, 11),
              );
            case 3:
              throw const _TimeoutSimulated();
            case 4:
              return LongPollResponse<List<String>>(
                items: <String>['d'],
                serverNow: DateTime.utc(2026, 5, 18, 12),
              );
            default:
              throw StateError('Too many calls');
          }
        },
      );

      // Collect the first three events (two payloads + one error).
      final List<List<String>> payloads = <List<String>>[];
      final List<Object> errors = <Object>[];
      final Completer<void> sawError = Completer<void>();
      final Completer<void> sawSecondPayload = Completer<void>();
      final Completer<void> sawFourthPayload = Completer<void>();

      final StreamSubscription<List<String>> sub = client.stream.listen(
        (List<String> e) {
          payloads.add(e);
          if (payloads.length == 2 && !sawSecondPayload.isCompleted) {
            sawSecondPayload.complete();
          }
          if (payloads.length == 3 && !sawFourthPayload.isCompleted) {
            sawFourthPayload.complete();
          }
        },
        onError: (Object e) {
          errors.add(e);
          if (!sawError.isCompleted) sawError.complete();
        },
      );

      client.start();

      await sawSecondPayload.future.timeout(const Duration(seconds: 2));
      expect(payloads, <List<String>>[
        <String>['a', 'b'],
        <String>['c'],
      ]);
      // First call had since=null, second call used the first response's
      // serverNow as `since`.
      expect(sinceSeen[0], isNull);
      expect(sinceSeen[1], DateTime.utc(2026, 5, 18, 10));

      await sawError.future.timeout(const Duration(seconds: 2));
      expect(errors.single, isA<_TimeoutSimulated>());
      // After the error we slept for exactly 1s (initialBackoff), then
      // retried with the previous serverNow.
      expect(sleeps.single, const Duration(seconds: 1));

      await sawFourthPayload.future.timeout(const Duration(seconds: 2));
      expect(payloads.last, <String>['d']);

      await client.dispose();
      await sub.cancel();
    });

    test('exponential backoff doubles, then caps at maxBackoff', () async {
      final List<Duration> sleeps = <Duration>[];
      int call = 0;
      final LongPollClient<List<String>> client = LongPollClient<List<String>>(
        initialBackoff: const Duration(seconds: 1),
        maxBackoff: const Duration(seconds: 4),
        sleep: (Duration d) async {
          sleeps.add(d);
        },
        poll: (DateTime? since) async {
          call++;
          throw _TimeoutSimulated('call $call');
        },
      );
      final List<Object> errors = <Object>[];
      final StreamSubscription<List<String>> sub = client.stream.listen(
        (_) {},
        onError: (Object e) => errors.add(e),
      );
      client.start();
      // Let it spin a few iterations.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await client.dispose();
      await sub.cancel();

      expect(errors.length, greaterThanOrEqualTo(3));
      // First few sleeps should follow 1s → 2s → 4s → 4s (capped).
      expect(sleeps[0], const Duration(seconds: 1));
      expect(sleeps[1], const Duration(seconds: 2));
      expect(sleeps[2], const Duration(seconds: 4));
      if (sleeps.length >= 4) {
        expect(sleeps[3], const Duration(seconds: 4));
      }
    });

    test('backoff resets to initialBackoff after a successful response',
        () async {
      final List<Duration> sleeps = <Duration>[];
      int call = 0;
      final LongPollClient<List<String>> client = LongPollClient<List<String>>(
        initialBackoff: const Duration(seconds: 1),
        maxBackoff: const Duration(seconds: 8),
        sleep: (Duration d) async {
          sleeps.add(d);
        },
        poll: (DateTime? since) async {
          call++;
          switch (call) {
            case 1:
            case 2:
              throw const _TimeoutSimulated();
            case 3:
              return LongPollResponse<List<String>>(
                items: <String>['ok'],
                serverNow: DateTime.utc(2026),
              );
            case 4:
            default:
              throw const _TimeoutSimulated();
          }
        },
      );
      final List<List<String>> payloads = <List<String>>[];
      final Completer<void> sawSuccess = Completer<void>();
      final Completer<void> sawPostSuccessError = Completer<void>();
      final StreamSubscription<List<String>> sub = client.stream.listen(
        (List<String> e) {
          payloads.add(e);
          if (!sawSuccess.isCompleted) sawSuccess.complete();
        },
        onError: (_) {
          // The 4th call (post-success) is an error. Wait for the sleep
          // it triggers before tearing down.
          if (call >= 4 && !sawPostSuccessError.isCompleted) {
            sawPostSuccessError.complete();
          }
        },
      );
      client.start();
      await sawSuccess.future.timeout(const Duration(seconds: 2));
      await sawPostSuccessError.future.timeout(const Duration(seconds: 2));
      // Allow the post-success backoff sleep to be recorded.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await client.dispose();
      await sub.cancel();

      // sleeps[0], sleeps[1] from the two errors before success: 1s, 2s.
      // sleeps[2] is the backoff after the post-success error — must be 1s,
      // proving the reset.
      expect(sleeps[0], const Duration(seconds: 1));
      expect(sleeps[1], const Duration(seconds: 2));
      expect(
        sleeps[2],
        const Duration(seconds: 1),
        reason: 'Backoff resets to initialBackoff after a successful response',
      );
    });

    test('stop() breaks the loop and the stream stays usable', () async {
      int call = 0;
      final LongPollClient<List<String>> client = LongPollClient<List<String>>(
        sleep: (Duration d) async {},
        poll: (DateTime? since) async {
          call++;
          return LongPollResponse<List<String>>(
            items: <String>['$call'],
            serverNow: DateTime.utc(2026, 5, 18, call),
          );
        },
      );
      final List<List<String>> received = <List<String>>[];
      final StreamSubscription<List<String>> sub =
          client.stream.listen(received.add);
      client.start();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      client.stop();
      final int snapshot = received.length;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // After stop, no new items should arrive.
      expect(received.length, snapshot);
      await sub.cancel();
      await client.dispose();
    });
  });
}

class _TimeoutSimulated implements Exception {
  const _TimeoutSimulated([this.message = 'timeout']);
  final String message;
  @override
  String toString() => '_TimeoutSimulated($message)';
}
