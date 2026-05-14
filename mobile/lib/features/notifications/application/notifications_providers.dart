import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../data/fake_notifications_repository.dart';
import '../data/notifications_repository.dart';
import '../domain/notification.dart';

final Provider<NotificationsRepository> notificationsRepositoryProvider =
    Provider<NotificationsRepository>(
      (Ref ref) => FakeNotificationsRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      ),
    );

/// Live stream of the current user's notifications. Recomputes when the
/// landing-page role switcher fires.
final StreamProvider<List<AppNotification>> myNotificationsProvider =
    StreamProvider<List<AppNotification>>((Ref ref) async* {
      final User? user = await ref.watch(currentUserProvider.future);
      if (user == null) {
        yield <AppNotification>[];
        return;
      }
      yield* ref
          .read(notificationsRepositoryProvider)
          .watch(userId: user.id);
    });

/// Synchronous unread count for app-bar/drawer badges.
final Provider<int> myUnreadCountProvider = Provider<int>((Ref ref) {
  final AsyncValue<List<AppNotification>> async = ref.watch(
    myNotificationsProvider,
  );
  return async.maybeWhen(
    data: (List<AppNotification> list) => list
        .where((AppNotification n) => n.state == NotificationState.unread)
        .length,
    orElse: () => 0,
  );
});
