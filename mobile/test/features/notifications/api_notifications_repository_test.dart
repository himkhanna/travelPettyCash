import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/features/notifications/data/api_notifications_repository.dart';
import 'package:pdd_petty_cash/features/notifications/data/notifications_repository.dart';
import 'package:pdd_petty_cash/features/notifications/domain/notification.dart';

void main() {
  late _FakeAdapter adapter;
  late ApiNotificationsRepository repo;

  setUp(() {
    adapter = _FakeAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
    dio.httpClientAdapter = adapter;
    repo = ApiNotificationsRepository(
      dio: dio,
      pollInterval: const Duration(milliseconds: 50),
    );
  });

  Map<String, dynamic> notif({
    String id = 'n-1',
    String type = 'ALLOCATION_RECEIVED',
    String state = 'UNREAD',
    Map<String, dynamic>? payload,
    bool actionable = true,
  }) =>
      <String, dynamic>{
        'id': id,
        'userId': 'u-fatima',
        'type': type,
        'actionable': actionable,
        'state': state,
        'refType': 'ALLOCATION',
        'refId': 'a-1',
        'payload': payload ??
            <String, dynamic>{
              'allocationId': 'a-1',
              'tripId': 'trip-ksa',
            },
        'createdAt': '2026-05-15T10:00:00Z',
        'readAt': null,
        'actedAt': null,
      };

  group('list', () {
    test('parses notifications', () async {
      adapter.respond(
        path: '/api/v1/notifications',
        body: <Map<String, dynamic>>[notif()],
      );
      final List<AppNotification> rows = await repo.list();
      expect(rows, hasLength(1));
      expect(rows.first.type, NotificationType.allocationReceived);
      expect(rows.first.state, NotificationState.unread);
      expect(rows.first.actionable, true);
      expect(rows.first.payload['allocationId'], 'a-1');
    });
  });

  group('markRead', () {
    test('PATCHes the row and parses READ state', () async {
      adapter.respond(
        path: '/api/v1/notifications/n-1/read',
        body: notif(state: 'READ'),
      );
      final AppNotification n = await repo.markRead('n-1');
      expect(n.state, NotificationState.read);
    });
  });

  group('act', () {
    test('allocationReceived → POSTs alloc respond then refetches ACTED', () async {
      // The notification list is fetched twice: once to look up the
      // allocationId, once after the respond to find the updated row.
      adapter.respond(
        path: '/api/v1/notifications',
        body: <Map<String, dynamic>>[notif(state: 'UNREAD')],
      );
      adapter.respond(
        path: '/api/v1/allocations/a-1/respond',
        body: <String, dynamic>{
          'id': 'a-1', 'tripId': 'trip-ksa',
          'toUserId': 'u-fatima', 'sourceId': 'src',
          'amount': <String, dynamic>{'amount': 1, 'currency': 'SAR'},
          'status': 'ACCEPTED',
          'createdAt': '2026-05-15T10:00:00Z',
          'respondedAt': '2026-05-15T10:01:00Z',
        },
      );
      // Queue the post-respond list response with ACTED state.
      adapter.respond(
        path: '/api/v1/notifications',
        body: <Map<String, dynamic>>[notif(state: 'ACTED')],
      );

      final AppNotification updated = await repo.act(
        notificationId: 'n-1',
        action: NotificationAction.accept,
      );
      expect(updated.state, NotificationState.acted);
    });

    test('non-actionable type falls through to markRead', () async {
      adapter.respond(
        path: '/api/v1/notifications',
        body: <Map<String, dynamic>>[notif(
          id: 'n-2',
          type: 'TRIP_CLOSED',
          actionable: false,
          payload: <String, dynamic>{'tripId': 'trip-x'},
        )],
      );
      adapter.respond(
        path: '/api/v1/notifications/n-2/read',
        body: notif(
          id: 'n-2',
          type: 'TRIP_CLOSED',
          state: 'READ',
          actionable: false,
          payload: <String, dynamic>{'tripId': 'trip-x'},
        ),
      );
      final AppNotification n = await repo.act(
        notificationId: 'n-2',
        action: NotificationAction.accept,
      );
      expect(n.state, NotificationState.read);
    });
  });

  group('watch (poll)', () {
    test('emits a list on subscribe and again on the next tick', () async {
      adapter.respond(
        path: '/api/v1/notifications',
        body: <Map<String, dynamic>>[notif()],
      );
      adapter.respond(
        path: '/api/v1/notifications',
        body: <Map<String, dynamic>>[notif(state: 'READ')],
      );
      final List<AppNotification> first = await repo
          .watch(userId: 'u-fatima')
          .take(2)
          .skip(1)
          .first;
      expect(first, hasLength(1));
      expect(first.first.state, NotificationState.read);
    });
  });

  group('unsupported deletes', () {
    test('delete throws UnsupportedError', () {
      expect(() => repo.delete('n-1'), throwsA(isA<UnsupportedError>()));
    });
    test('deleteAll throws UnsupportedError', () {
      expect(() => repo.deleteAll(), throwsA(isA<UnsupportedError>()));
    });
  });
}

/// FIFO-per-path canned adapter — successive requests to the same path pop the
/// next response off the queue (lets watch() poll twice and see different
/// states).
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, List<_Canned>> _byPath = <String, List<_Canned>>{};

  void respond({
    required String path,
    int status = 200,
    required Object body,
  }) {
    _byPath.putIfAbsent(path, () => <_Canned>[]).add(_Canned(status, body));
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final List<_Canned>? queued = _byPath[options.path];
    if (queued == null || queued.isEmpty) {
      throw StateError('No canned response for ${options.method} ${options.path}');
    }
    final _Canned c = queued.length == 1
        ? queued.first // sticky once the queue is down to one
        : queued.removeAt(0);
    final List<int> bytes = utf8.encode(jsonEncode(c.body));
    return ResponseBody.fromBytes(
      bytes,
      c.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}

class _Canned {
  const _Canned(this.status, this.body);
  final int status;
  final Object body;
}
