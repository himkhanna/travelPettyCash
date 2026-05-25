/// Notification types per screen-inventory.md §16.
enum NotificationType {
  allocationReceived,
  transferReceived,
  transferAccepted,
  tripAssigned,
  tripClosed,
  expenseQuery,
  /// Fired when a report is ready for download — emitted on trip close
  /// (for the finance letter) and by the scheduled-delivery cron job.
  /// Payload carries `{scope, scopeId, kind, downloadUrl, generatedAt}`.
  reportReady,
  /// Fired when a peer posts to a trip chat thread. Payload carries
  /// `{threadId, tripId, tripName, senderId, snippet}`.
  chatMessage,
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
