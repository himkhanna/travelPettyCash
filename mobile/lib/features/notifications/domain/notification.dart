/// Notification types per screen-inventory.md §16.
enum NotificationType {
  allocationReceived,
  transferReceived,
  transferAccepted,
  tripAssigned,
  tripClosed,
  expenseQuery,
}

enum NotificationState { unread, read, acted }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.payload,
    required this.actionable,
    required this.state,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final NotificationType type;
  final Map<String, Object?> payload;
  final bool actionable;
  final NotificationState state;
  final DateTime createdAt;
}
