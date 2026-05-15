import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/api/api_error.dart';
import 'package:pdd_petty_cash/features/chat/data/api_chat_repository.dart';
import 'package:pdd_petty_cash/features/chat/domain/chat.dart';

void main() {
  late _FakeAdapter adapter;
  late ApiChatRepository repo;

  setUp(() {
    adapter = _FakeAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
    dio.httpClientAdapter = adapter;
    repo = ApiChatRepository(
      dio: dio,
      pollInterval: const Duration(milliseconds: 50),
    );
  });

  Map<String, dynamic> threadJson({
    String id = 't-1',
    String tripId = 'trip-ksa',
    int unread = 0,
    int participants = 2,
  }) =>
      <String, dynamic>{
        'id': id,
        'tripId': tripId,
        'title': 'KSA Delegation',
        'titleAr': 'وفد السعودية',
        'participantIds': List<String>.generate(participants, (int i) => 'u-$i'),
        'unreadCount': unread,
        'lastMessagePreview': 'hello',
        'lastMessageAt': '2026-05-15T10:00:00Z',
      };

  Map<String, dynamic> messageJson({
    String id = 'm-1',
    String threadId = 't-1',
    String sender = 'u-fatima',
    String body = 'Hello',
    String sentAt = '2026-05-15T10:00:00Z',
  }) =>
      <String, dynamic>{
        'id': id,
        'threadId': threadId,
        'senderId': sender,
        'body': body,
        'sentAt': sentAt,
        'deliveredAt': sentAt,
        'readAt': null,
      };

  group('threads', () {
    test('parses participants + unread count', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/chat/threads',
        body: <Map<String, dynamic>>[threadJson(unread: 2, participants: 4)],
      );
      final List<ChatThread> rows = await repo.threads(tripId: 'trip-ksa');
      expect(rows, hasLength(1));
      expect(rows.first.unreadCount, 2);
      expect(rows.first.participantIds, hasLength(4));
      expect(rows.first.isGroup, true);
    });
  });

  group('send', () {
    test('POSTs body and parses returned message', () async {
      adapter.respond(
        path: '/api/v1/chat/threads/t-1/messages',
        body: messageJson(body: 'Heading over'),
      );
      final ChatMessage m = await repo.send(
        threadId: 't-1',
        senderId: 'u-fatima',
        body: 'Heading over',
      );
      expect(m.body, 'Heading over');
      expect(adapter.lastBody['body'], 'Heading over');
    });

    test('404 chat/thread-not-found surfaces as ApiError', () async {
      adapter.respond(
        path: '/api/v1/chat/threads/t-1/messages',
        status: 404,
        body: <String, dynamic>{
          'code': 'chat/thread-not-found',
          'title': 'Thread not found',
          'status': 404,
          'detail': 'x',
        },
      );
      await expectLater(
        repo.send(threadId: 't-1', senderId: 'u-fatima', body: 'hi'),
        throwsA(isA<ApiError>().having(
          (ApiError e) => e.code, 'code', 'chat/thread-not-found',
        )),
      );
    });
  });

  group('markRead', () {
    test('PATCHes the thread', () async {
      adapter.respond(
        path: '/api/v1/chat/threads/t-1/read',
        body: <String, dynamic>{},
      );
      await repo.markRead(threadId: 't-1', userId: 'u-fatima');
      // No throw == passed.
    });
  });

  group('watchMessages (poll)', () {
    test('emits on subscribe and again when the list changes', () async {
      // First poll: 1 message. Second poll: 2 messages.
      adapter.respond(
        path: '/api/v1/chat/threads/t-1/messages',
        body: <Map<String, dynamic>>[messageJson()],
      );
      adapter.respond(
        path: '/api/v1/chat/threads/t-1/messages',
        body: <Map<String, dynamic>>[
          messageJson(),
          messageJson(id: 'm-2', body: 'On my way', sentAt: '2026-05-15T10:01:00Z'),
        ],
      );
      final Stream<List<ChatMessage>> stream = repo.watchMessages('t-1');
      final List<List<ChatMessage>> seen = await stream.take(2).toList();
      expect(seen[0], hasLength(1));
      expect(seen[1], hasLength(2));
    });
  });
}

/// FIFO-per-path canned adapter; sticky to the last queued response so polls
/// that exceed the queued count still get something.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, List<_Canned>> _byPath = <String, List<_Canned>>{};
  Map<String, dynamic> lastBody = <String, dynamic>{};

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
    if (options.data is Map<String, dynamic>) {
      lastBody = Map<String, dynamic>.from(options.data as Map<String, dynamic>);
    }
    final List<_Canned>? queued = _byPath[options.path];
    if (queued == null || queued.isEmpty) {
      throw StateError('No canned response for ${options.method} ${options.path}');
    }
    final _Canned c = queued.length == 1 ? queued.first : queued.removeAt(0);
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
