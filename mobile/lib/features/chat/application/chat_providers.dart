import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_config.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../data/api_chat_repository.dart';
import '../data/chat_repository.dart';
import '../data/fake_chat_repository.dart';
import '../domain/chat.dart';

final Provider<ChatRepository> chatRepositoryProvider =
    Provider<ChatRepository>((Ref ref) {
  final BackendMode mode = ref.watch(backendModeProvider);
  switch (mode) {
    case BackendMode.fake:
      return FakeChatRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      );
    case BackendMode.api:
      return ApiChatRepository(dio: ref.watch(dioProvider));
  }
});

/// Poll cadence for the chat-list streams. Matches the
/// notifications inbox so the chat list's unread badge and the
/// home activity feed stay in sync. 5 s is short enough to feel
/// fresh during a demo, long enough to not hammer the API while
/// the user is sitting on a list screen.
const Duration _chatsPollInterval = Duration(seconds: 5);

/// Per-trip chat list. StreamProvider that polls every 5 s so the
/// unread badge on each thread row updates when peers post messages
/// — the previous FutureProvider only refetched on cold load, which
/// left users staring at stale "0 unread" counts.
final StreamProviderFamily<List<ChatThread>, String> tripThreadsProvider =
    StreamProvider.family<List<ChatThread>, String>((
      Ref ref,
      String tripId,
    ) async* {
  final User? user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield <ChatThread>[];
    return;
  }
  yield* _poll(
    () => ref.read(chatRepositoryProvider).threads(tripId: tripId),
    ref,
  );
});

/// Global chat list — every thread the current user participates in, across
/// every trip. Backs the Chat screen reached from the Profile menu. Polls
/// on the same cadence as the per-trip list (see [_chatsPollInterval]).
final StreamProvider<List<ChatThread>> allChatsProvider =
    StreamProvider<List<ChatThread>>((Ref ref) async* {
  final User? user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    yield <ChatThread>[];
    return;
  }
  yield* _poll(
    () =>
        ref.read(chatRepositoryProvider).threadsForUser(userId: user.id),
    ref,
  );
});

/// Shared poll-and-emit loop for both chat-list providers. Emits once
/// immediately, then every [_chatsPollInterval], deduping on a simple
/// fingerprint so the UI doesn't rebuild when nothing changed.
Stream<List<ChatThread>> _poll(
  Future<List<ChatThread>> Function() fetch,
  Ref ref,
) async* {
  String lastFingerprint = '';
  Future<List<ChatThread>>? inflight;
  while (true) {
    try {
      inflight = fetch();
      final List<ChatThread> rows = await inflight;
      final String fp = rows
          .map((ChatThread t) =>
              '${t.id}:${t.unreadCount}:${t.lastMessageAt?.millisecondsSinceEpoch ?? 0}')
          .join('|');
      if (fp != lastFingerprint) {
        lastFingerprint = fp;
        yield rows;
      }
    } catch (_) {
      // Swallow transient errors so the poll loop keeps trying.
    }
    await Future<void>.delayed(_chatsPollInterval);
  }
}

/// The canonical "team chat" thread for a trip — leader + all members in
/// one group. Created lazily on the backend, so this is also the path that
/// guarantees the thread exists before the user is sent into it.
final FutureProviderFamily<ChatThread, String> teamChatProvider =
    FutureProvider.family<ChatThread, String>((Ref ref, String tripId) async {
  final User? user = await ref.watch(currentUserProvider.future);
  if (user == null) {
    throw StateError('No current user — cannot resolve team chat.');
  }
  return ref.read(chatRepositoryProvider).teamThread(tripId: tripId);
});

final StreamProviderFamily<List<ChatMessage>, String> threadMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((
      Ref ref,
      String threadId,
    ) async* {
      final User? user = await ref.watch(currentUserProvider.future);
      if (user == null) {
        yield <ChatMessage>[];
        return;
      }
      yield* ref.read(chatRepositoryProvider).watchMessages(threadId);
    });
