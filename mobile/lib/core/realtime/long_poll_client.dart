import 'dart:async';

import 'package:flutter/foundation.dart';

/// Generic long-polling primitive.
///
/// Backend slice 3B exposes `GET /notifications/poll?since=...&timeoutSeconds=25`
/// and `GET /chat/threads/{id}/poll?since=...&timeoutSeconds=25`, each
/// returning `{ items: [...], serverNow: ISO8601 }`. The client opens one
/// request at a time, emits each batch via [stream], then immediately
/// re-issues the next request using the returned `serverNow` as the next
/// `since`. On any error it backs off (1s → 2s → 4s → … capped at 30s)
/// and retries; backoff resets after the first successful response.
///
/// Wire it like this from a repository's `watch()` method:
///
/// ```dart
/// Stream<List<Notification>> watch() {
///   final client = LongPollClient<List<Notification>>(
///     poll: (DateTime? since) => _api.pollNotifications(since: since),
///   );
///   client.start(since: null);
///   return client.stream;
/// }
/// ```
///
/// The repository is responsible for calling [stop] when the consumer
/// cancels its subscription.
class LongPollClient<T> {
  LongPollClient({
    required this.poll,
    this.initialBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
    @visibleForTesting Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  /// One round-trip. The implementation should honour [since] as a cursor
  /// hint to the server. It should NOT retry on error — that's the
  /// [LongPollClient]'s job.
  final Future<LongPollResponse<T>> Function(DateTime? since) poll;

  /// First backoff interval after the first error.
  final Duration initialBackoff;

  /// Cap for exponential backoff. 30s is a sensible default for a sovereign
  /// deployment where flaky links during overseas trips are the norm.
  final Duration maxBackoff;

  final Future<void> Function(Duration) _sleep;

  final StreamController<T> _ctrl = StreamController<T>.broadcast();
  Stream<T> get stream => _ctrl.stream;

  bool _running = false;
  bool _disposed = false;
  DateTime? _since;
  Completer<void>? _cancelSignal;

  /// Starts (or restarts) the polling loop. Calling [start] twice without
  /// an intervening [stop] is a no-op.
  void start({DateTime? since}) {
    if (_running || _disposed) return;
    _running = true;
    _since = since;
    _cancelSignal = Completer<void>();
    unawaited(_loop());
  }

  /// Cancels the in-flight request (best effort) and breaks the loop. The
  /// stream itself stays open so a subsequent [start] can resume — call
  /// [dispose] to permanently shut down.
  void stop() {
    if (!_running) return;
    _running = false;
    if (_cancelSignal?.isCompleted == false) {
      _cancelSignal!.complete();
    }
  }

  /// Permanently closes the stream. After this, the client cannot be
  /// restarted.
  Future<void> dispose() async {
    _disposed = true;
    stop();
    if (!_ctrl.isClosed) await _ctrl.close();
  }

  Future<void> _loop() async {
    Duration backoff = initialBackoff;
    while (_running && !_disposed) {
      try {
        final LongPollResponse<T> response = await poll(_since);
        if (!_running || _disposed) return;
        _ctrl.add(response.items);
        _since = response.serverNow;
        // First success — reset backoff so the next transient blip starts
        // from 1s again rather than wherever we left off.
        backoff = initialBackoff;
      } catch (e, st) {
        if (!_running || _disposed) return;
        _ctrl.addError(e, st);
        await _sleep(backoff);
        backoff = _nextBackoff(backoff);
      }
    }
  }

  Duration _nextBackoff(Duration current) {
    final Duration doubled = current * 2;
    return doubled > maxBackoff ? maxBackoff : doubled;
  }
}

/// Single long-poll response. [items] is the batch the server is handing
/// back (possibly empty if the request timed out without new data);
/// [serverNow] is the cursor for the next request.
@immutable
class LongPollResponse<T> {
  const LongPollResponse({required this.items, required this.serverNow});

  final T items;
  final DateTime serverNow;
}
