import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../data/chat_repository.dart';
import '../data/fake_chat_repository.dart';
import '../domain/chat.dart';

final Provider<ChatRepository> chatRepositoryProvider = Provider<ChatRepository>(
  (Ref ref) => FakeChatRepository(
    ref.watch(demoStoreProvider),
    ref.watch(fakeConfigProvider),
  ),
);

final FutureProviderFamily<List<ChatThread>, String> tripThreadsProvider =
    FutureProvider.family<List<ChatThread>, String>((
      Ref ref,
      String tripId,
    ) async {
      final User? user = await ref.watch(currentUserProvider.future);
      if (user == null) return <ChatThread>[];
      return ref.read(chatRepositoryProvider).threads(tripId: tripId);
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
