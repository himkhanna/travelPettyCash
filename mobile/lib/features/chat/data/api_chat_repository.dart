import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../domain/chat.dart';
import 'chat_repository.dart';

/// Real backend impl. Polls {@code /messages} every 3 s for new messages
/// while the user has the thread open — the websocket / SSE channel is
/// out of scope per CLAUDE.md §15.
class ApiChatRepository implements ChatRepository {
  ApiChatRepository({
    required Dio dio,
    Duration pollInterval = const Duration(seconds: 3),
  })  : _dio = dio,
        _pollInterval = pollInterval;

  final Dio _dio;
  final Duration _pollInterval;

  @override
  Future<List<ChatThread>> threads({required String tripId}) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/trips/$tripId/chat/threads',
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _threadFromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<ChatThread> teamThread({required String tripId}) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/trips/$tripId/chat/team',
      );
      return _threadFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<List<ChatThread>> threadsForUser({required String userId}) async {
    // userId is ignored on the wire — the backend derives it from the JWT
    // principal — but the interface keeps it explicit so the fake repo can
    // filter without an auth dependency.
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/chat/threads',
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _threadFromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String threadId) {
    final StreamController<List<ChatMessage>> ctrl =
        StreamController<List<ChatMessage>>.broadcast();
    Timer? timer;
    String? lastFingerprint;

    Future<void> tick() async {
      if (ctrl.isClosed) return;
      try {
        final List<ChatMessage> rows = await _messages(threadId);
        // Only re-emit when the result actually changed — avoids needlessly
        // rebuilding the chat ListView every 3 s.
        final String fp = '${rows.length}:${rows.isEmpty ? '' : rows.last.id}';
        if (fp != lastFingerprint) {
          lastFingerprint = fp;
          ctrl.add(rows);
        }
      } catch (e) {
        ctrl.addError(e);
      }
    }

    ctrl.onListen = () {
      tick();
      timer = Timer.periodic(_pollInterval, (_) => tick());
    };
    ctrl.onCancel = () {
      timer?.cancel();
      ctrl.close();
    };
    return ctrl.stream;
  }

  Future<List<ChatMessage>> _messages(String threadId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/chat/threads/$threadId/messages',
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _messageFromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<ChatMessage> send({
    required String threadId,
    required String senderId,
    required String body,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/chat/threads/$threadId/messages',
        data: <String, dynamic>{'body': body},
      );
      return _messageFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<void> markRead({
    required String threadId,
    required String userId,
  }) async {
    try {
      await _dio.patch<dynamic>('/api/v1/chat/threads/$threadId/read');
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  ChatThread _threadFromJson(Map<String, dynamic> j) {
    return ChatThread(
      id: j['id'] as String,
      tripId: j['tripId'] as String,
      title: j['title'] as String,
      titleAr: j['titleAr'] as String,
      participantIds: (j['participantIds'] as List<dynamic>).cast<String>(),
      unreadCount: j['unreadCount'] as int,
      lastMessagePreview: j['lastMessagePreview'] as String?,
      lastMessageAt: j['lastMessageAt'] == null
          ? null
          : DateTime.parse(j['lastMessageAt'] as String),
    );
  }

  ChatMessage _messageFromJson(Map<String, dynamic> j) {
    return ChatMessage(
      id: j['id'] as String,
      threadId: j['threadId'] as String,
      senderId: j['senderId'] as String,
      body: j['body'] as String,
      sentAt: DateTime.parse(j['sentAt'] as String),
      deliveredAt: j['deliveredAt'] == null
          ? null
          : DateTime.parse(j['deliveredAt'] as String),
      readAt: j['readAt'] == null
          ? null
          : DateTime.parse(j['readAt'] as String),
    );
  }
}
