import '../../features/auth/domain/user.dart';
import '../../features/chat/domain/chat.dart';
import '../../features/expenses/domain/expense.dart';
import '../../features/funds/domain/funding.dart';
import '../../features/notifications/domain/notification.dart';
import '../../features/trips/domain/trip.dart';
import '../money/money.dart';

/// Pure-Dart JSON parsers used by FakeRepositories to load `assets/demo/*.json`.
///
/// When the real API lands these are superseded by openapi-generator output,
/// but for the demo we hand-write them to avoid a build_runner dependency on
/// the first run.

User parseUser(Map<String, Object?> json) => User(
      id: json['id']! as String,
      username: json['username']! as String,
      displayName: json['displayName']! as String,
      displayNameAr: json['displayNameAr']! as String,
      email: json['email']! as String,
      role: UserRole.fromApiCode(json['role']! as String),
      isActive: json['isActive']! as bool,
    );

Source parseSource(Map<String, Object?> json) => Source(
      id: json['id']! as String,
      name: json['name']! as String,
      nameAr: json['nameAr']! as String,
      isActive: json['isActive']! as bool,
    );

ExpenseCategory parseCategory(Map<String, Object?> json) => ExpenseCategory(
      code: json['code']! as String,
      nameEn: json['nameEn']! as String,
      nameAr: json['nameAr']! as String,
      iconKey: json['iconKey']! as String,
      isActive: json['isActive']! as bool,
    );

Trip parseTrip(Map<String, Object?> json) {
  final String currency = json['currency']! as String;
  return Trip(
    id: json['id']! as String,
    name: json['name']! as String,
    countryCode: json['countryCode']! as String,
    countryName: json['countryName']! as String,
    currency: currency,
    status: _parseTripStatus(json['status']! as String),
    createdBy: json['createdBy']! as String,
    leaderId: json['leaderId']! as String,
    memberIds: (json['memberIds']! as List<Object?>).cast<String>(),
    totalBudget: Money(json['totalBudgetMinor']! as int, currency),
    createdAt: DateTime.parse(json['createdAt']! as String),
    closedAt: json['closedAt'] == null
        ? null
        : DateTime.parse(json['closedAt']! as String),
  );
}

Allocation parseAllocation(Map<String, Object?> json, {required String currency}) =>
    Allocation(
      id: json['id']! as String,
      tripId: json['tripId']! as String,
      fromUserId: json['fromUserId'] as String?,
      toUserId: json['toUserId']! as String,
      sourceId: json['sourceId']! as String,
      amount: Money(json['amountMinor']! as int, currency),
      status: _parseAllocationStatus(json['status']! as String),
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['createdAt']! as String),
      respondedAt: json['respondedAt'] == null
          ? null
          : DateTime.parse(json['respondedAt']! as String),
    );

Expense parseExpense(Map<String, Object?> json, {required String currency}) =>
    Expense(
      id: json['id']! as String,
      tripId: json['tripId']! as String,
      userId: json['userId']! as String,
      sourceId: json['sourceId']! as String,
      categoryCode: json['categoryCode']! as String,
      amount: Money(json['amountMinor']! as int, currency),
      quantity: (json['quantity'] as int?) ?? 1,
      details: (json['details'] as String?) ?? '',
      occurredAt: DateTime.parse(json['occurredAt']! as String),
      createdAt: DateTime.parse(json['createdAt']! as String),
      receiptObjectKey: json['receiptObjectKey'] as String?,
    );

ChatThread parseChatThread(Map<String, Object?> json) => ChatThread(
      id: json['id']! as String,
      tripId: json['tripId']! as String,
      title: json['title']! as String,
      titleAr: json['titleAr']! as String,
      participantIds: (json['participantIds']! as List<Object?>).cast<String>(),
      unreadCount: (json['unreadCount'] as int?) ?? 0,
      lastMessagePreview: json['lastMessagePreview'] as String?,
      lastMessageAt: json['lastMessageAt'] == null
          ? null
          : DateTime.parse(json['lastMessageAt']! as String),
    );

ChatMessage parseChatMessage(Map<String, Object?> json) => ChatMessage(
      id: json['id']! as String,
      threadId: json['threadId']! as String,
      senderId: json['senderId']! as String,
      body: json['body']! as String,
      sentAt: DateTime.parse(json['sentAt']! as String),
      deliveredAt: json['deliveredAt'] == null
          ? null
          : DateTime.parse(json['deliveredAt']! as String),
      readAt: json['readAt'] == null ? null : DateTime.parse(json['readAt']! as String),
    );

AppNotification parseNotification(Map<String, Object?> json) => AppNotification(
      id: json['id']! as String,
      userId: json['userId']! as String,
      type: _parseNotificationType(json['type']! as String),
      payload: Map<String, Object?>.from(json['payload']! as Map<Object?, Object?>),
      actionable: json['actionable']! as bool,
      state: _parseNotificationState(json['state']! as String),
      createdAt: DateTime.parse(json['createdAt']! as String),
    );

TripStatus _parseTripStatus(String code) {
  switch (code) {
    case 'DRAFT':
      return TripStatus.draft;
    case 'ACTIVE':
      return TripStatus.active;
    case 'CLOSED':
      return TripStatus.closed;
    default:
      throw ArgumentError('Unknown trip status: $code');
  }
}

AllocationStatus _parseAllocationStatus(String code) {
  switch (code) {
    case 'PENDING':
      return AllocationStatus.pending;
    case 'ACCEPTED':
      return AllocationStatus.accepted;
    case 'DECLINED':
      return AllocationStatus.declined;
    default:
      throw ArgumentError('Unknown allocation status: $code');
  }
}

NotificationType _parseNotificationType(String code) {
  switch (code) {
    case 'ALLOCATION_RECEIVED':
      return NotificationType.allocationReceived;
    case 'TRANSFER_RECEIVED':
      return NotificationType.transferReceived;
    case 'TRANSFER_ACCEPTED':
      return NotificationType.transferAccepted;
    case 'TRIP_ASSIGNED':
      return NotificationType.tripAssigned;
    case 'TRIP_CLOSED':
      return NotificationType.tripClosed;
    case 'EXPENSE_QUERY':
      return NotificationType.expenseQuery;
    default:
      throw ArgumentError('Unknown notification type: $code');
  }
}

NotificationState _parseNotificationState(String code) {
  switch (code) {
    case 'UNREAD':
      return NotificationState.unread;
    case 'READ':
      return NotificationState.read;
    case 'ACTED':
      return NotificationState.acted;
    default:
      throw ArgumentError('Unknown notification state: $code');
  }
}
