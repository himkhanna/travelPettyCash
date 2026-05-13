import '../domain/notification.dart';

abstract class NotificationsRepository {
  Stream<List<AppNotification>> watch({required String userId});
  Future<List<AppNotification>> list({String? cursor, int limit = 30});
  Future<AppNotification> markRead(String notificationId);
  Future<AppNotification> act({
    required String notificationId,
    required NotificationAction action,
  });
  Future<void> delete(String notificationId);
  Future<void> deleteAll();
}

enum NotificationAction { accept, decline }
