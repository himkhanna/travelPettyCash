import '../domain/chat.dart';

abstract class ChatRepository {
  Future<List<ChatThread>> threads({required String tripId});

  /// Every thread the current user participates in, across all trips. Backs
  /// the global Chat screen reached from the Profile menu.
  Future<List<ChatThread>> threadsForUser({required String userId});

  /// Find-or-create the canonical "team chat" for the trip — the group
  /// thread containing the leader + every member. Lazy so existing trips
  /// (created before the team-thread feature) self-heal on first access.
  Future<ChatThread> teamThread({required String tripId});

  Stream<List<ChatMessage>> watchMessages(String threadId);
  Future<ChatMessage> send({
    required String threadId,
    required String senderId,
    required String body,
  });
  Future<void> markRead({required String threadId, required String userId});
}
