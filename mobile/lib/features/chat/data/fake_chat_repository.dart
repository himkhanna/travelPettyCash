import 'dart:async';
import 'dart:math';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../domain/chat.dart';
import 'chat_repository.dart';

/// In-memory chat backed by DemoStore. For the demo, after the user sends a
/// message we inject a scripted reply from another thread participant ~2s
/// later so live demos feel alive.
class FakeChatRepository implements ChatRepository {
  FakeChatRepository(this._store, this._cfg);

  final DemoStore _store;
  final FakeConfig _cfg;
  static final Random _rng = Random();

  @override
  Future<List<ChatThread>> threads({required String tripId}) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    return _store.chatThreads
        .where((ChatThread t) => t.tripId == tripId)
        .toList()
      ..sort(
        (ChatThread a, ChatThread b) =>
            (b.lastMessageAt ?? DateTime(0)).compareTo(
              a.lastMessageAt ?? DateTime(0),
            ),
      );
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String threadId) {
    Future<List<ChatMessage>> snapshot() async {
      await _store.ensureLoaded();
      return _store.chatMessages
          .where((ChatMessage m) => m.threadId == threadId)
          .toList()
        ..sort(
          (ChatMessage a, ChatMessage b) => a.sentAt.compareTo(b.sentAt),
        );
    }

    final StreamController<List<ChatMessage>> ctrl =
        StreamController<List<ChatMessage>>.broadcast();
    StreamSubscription<DemoStoreEvent>? sub;
    ctrl.onListen = () async {
      ctrl.add(await snapshot());
      sub = _store.events.listen((DemoStoreEvent e) async {
        if (e == DemoStoreEvent.chatChanged) {
          ctrl.add(await snapshot());
        }
      });
    };
    ctrl.onCancel = () => sub?.cancel();
    return ctrl.stream;
  }

  @override
  Future<ChatMessage> send({
    required String threadId,
    required String senderId,
    required String body,
  }) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    final DateTime now = _cfg.now();
    final ChatMessage msg = ChatMessage(
      id: 'msg-${now.microsecondsSinceEpoch}',
      threadId: threadId,
      senderId: senderId,
      body: body,
      sentAt: now,
      deliveredAt: now,
    );
    _store.chatMessages.add(msg);
    _touchThread(threadId, body, now);
    _store.emit(DemoStoreEvent.chatChanged);

    // Scripted reply ~2s later to give the live demo some movement.
    _scheduleReply(threadId, senderId);

    return msg;
  }

  @override
  Future<void> markRead({
    required String threadId,
    required String userId,
  }) async {
    await _store.ensureLoaded();
    final int i = _store.chatThreads.indexWhere(
      (ChatThread t) => t.id == threadId,
    );
    if (i < 0) return;
    final ChatThread old = _store.chatThreads[i];
    if (old.unreadCount == 0) return;
    _store.chatThreads[i] = ChatThread(
      id: old.id,
      tripId: old.tripId,
      title: old.title,
      titleAr: old.titleAr,
      participantIds: old.participantIds,
      unreadCount: 0,
      lastMessagePreview: old.lastMessagePreview,
      lastMessageAt: old.lastMessageAt,
    );
    _store.emit(DemoStoreEvent.chatChanged);
  }

  void _touchThread(String threadId, String preview, DateTime at) {
    final int i = _store.chatThreads.indexWhere(
      (ChatThread t) => t.id == threadId,
    );
    if (i < 0) return;
    final ChatThread old = _store.chatThreads[i];
    _store.chatThreads[i] = ChatThread(
      id: old.id,
      tripId: old.tripId,
      title: old.title,
      titleAr: old.titleAr,
      participantIds: old.participantIds,
      unreadCount: old.unreadCount,
      lastMessagePreview: preview.length > 50
          ? '${preview.substring(0, 50)}…'
          : preview,
      lastMessageAt: at,
    );
  }

  void _scheduleReply(String threadId, String senderId) {
    Future<void>.delayed(const Duration(seconds: 2), () async {
      final int i = _store.chatThreads.indexWhere(
        (ChatThread t) => t.id == threadId,
      );
      if (i < 0) return;
      final ChatThread thread = _store.chatThreads[i];
      final List<String> others = thread.participantIds
          .where((String id) => id != senderId)
          .toList();
      if (others.isEmpty) return;
      final String replier = others[_rng.nextInt(others.length)];
      const List<String> scripts = <String>[
        'Got it, thanks!',
        'OK, on my way.',
        'Will check and revert in 10 minutes.',
        'Acknowledged.',
        'Please share the receipt when you can.',
        'Confirmed.',
        'Will discuss with the team.',
      ];
      final String body = scripts[_rng.nextInt(scripts.length)];
      final DateTime now = DateTime.now();
      final ChatMessage reply = ChatMessage(
        id: 'msg-reply-${now.microsecondsSinceEpoch}',
        threadId: threadId,
        senderId: replier,
        body: body,
        sentAt: now,
        deliveredAt: now,
      );
      _store.chatMessages.add(reply);
      _touchThread(threadId, body, now);
      _store.emit(DemoStoreEvent.chatChanged);
    });
  }
}
