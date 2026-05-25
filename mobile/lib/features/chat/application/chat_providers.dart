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

final FutureProviderFamily<List<ChatThread>, String> tripThreadsProvider =
    FutureProvider.family<List<ChatThread>, String>((
      Ref ref,
      String tripId,
    ) async {
      final User? user = await ref.watch(currentUserProvider.future);
      if (user == null) return <ChatThread>[];
      return ref.read(chatRepositoryProvider).threads(tripId: tripId);
    });

/// Global chat list — every thread the current user participates in, across
/// every trip. Backs the Chat screen reached from the Profile menu.
final FutureProvider<List<ChatThread>> allChatsProvider =
    FutureProvider<List<ChatThread>>((Ref ref) async {
  final User? user = await ref.watch(currentUserProvider.future);
  if (user == null) return <ChatThread>[];
  return ref.read(chatRepositoryProvider).threadsForUser(userId: user.id);
});

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
