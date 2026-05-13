import '../domain/chat.dart';

abstract class ChatRepository {
  Future<List<ChatThread>> threads({required String tripId});
  Stream<List<ChatMessage>> watchMessages(String threadId);
  Future<ChatMessage> send({
    required String threadId,
    required String senderId,
    required String body,
  });
  Future<void> markRead({required String threadId, required String userId});
}
