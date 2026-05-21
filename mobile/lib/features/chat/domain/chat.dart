class ChatThread {
  const ChatThread({
    required this.id,
    required this.tripId,
    required this.title,
    required this.titleAr,
    required this.participantIds,
    required this.unreadCount,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.expenseId,
  });

  final String id;
  final String tripId;
  final String title;
  final String titleAr;
  final List<String> participantIds;
  final int unreadCount;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;

  /// Non-null when this thread is an admin → owner question scoped to a
  /// specific expense (per CLAUDE.md §5, EXPENSE_QUERY notification).
  final String? expenseId;

  bool get isGroup => participantIds.length > 2;
  bool get isExpenseQuery => expenseId != null;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.body,
    required this.sentAt,
    this.deliveredAt,
    this.readAt,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String body;
  final DateTime sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
}
