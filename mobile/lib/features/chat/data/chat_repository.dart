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

  /// Find an existing admin↔owner thread for [expenseId], or create a fresh
  /// one. Idempotent.
  Future<ChatThread> getOrCreateExpenseThread({
    required String expenseId,
    required String tripId,
    required String adminUserId,
    required String ownerUserId,
    required String expenseLabel,
    required String expenseLabelAr,
  });
}
