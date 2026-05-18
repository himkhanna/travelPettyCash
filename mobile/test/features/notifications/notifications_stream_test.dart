import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/features/notifications/data/fake_notifications_repository.dart';
import 'package:pdd_petty_cash/features/notifications/domain/notification.dart';

/// Slice 3B — notifications stream emits on DemoStore mutations.
///
/// The real impl uses [LongPollClient] against `/notifications/poll`; the
/// fake hooks DemoStore events so seed notifications surface live in the
/// demo. This test pumps a new notification into the store and asserts the
/// watch stream emits an updated list with the unread item present.
void main() {
  group('FakeNotificationsRepository.watch', () {
    late DemoStore store;
    late FakeConfig cfg;
    late FakeNotificationsRepository repo;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      store = DemoStore.instance;
      store.resetForTest();
      store.markLoadedForTest();
      cfg = FakeConfig.instance
        ..setLatency(Duration.zero)
        ..setFailureRate(0)
        ..setOfflineMode(value: false);
      repo = FakeNotificationsRepository(store, cfg);
    });

    test('stream emits initial snapshot and updates on store events',
        () async {
      // Seed an initial unread notification.
      store.notifications.add(
        AppNotification(
          id: 'n-1',
          userId: 'u-1',
          type: NotificationType.transferReceived,
          payload: <String, Object?>{'amountMinor': 100, 'currency': 'SAR'},
          actionable: true,
          state: NotificationState.unread,
          createdAt: DateTime(2026, 5, 18, 9),
        ),
      );

      final Stream<List<AppNotification>> stream = repo.watch(userId: 'u-1');
      final List<List<AppNotification>> emissions =
          <List<AppNotification>>[];
      final Future<void> done = stream
          .take(2)
          .listen(emissions.add)
          .asFuture<void>();

      // Pump a brief delay so the broadcast controller's onListen fires
      // and queues the initial snapshot.
      await Future<void>.delayed(Duration.zero);

      // Now simulate a new transferReceived notification landing in the
      // store (e.g. another member accepted, an allocation came in).
      store.notifications.add(
        AppNotification(
          id: 'n-2',
          userId: 'u-1',
          type: NotificationType.allocationReceived,
          payload: <String, Object?>{'amountMinor': 500, 'currency': 'SAR'},
          actionable: true,
          state: NotificationState.unread,
          createdAt: DateTime(2026, 5, 18, 10),
        ),
      );
      store.emit(DemoStoreEvent.notificationsChanged);

      await done.timeout(const Duration(seconds: 2));

      expect(emissions, hasLength(2));
      expect(emissions[0].map((AppNotification n) => n.id), <String>['n-1']);
      // Sorted createdAt DESC per the fake's watch implementation.
      expect(
        emissions[1].map((AppNotification n) => n.id),
        <String>['n-2', 'n-1'],
      );
      // Unread badge count would jump from 1 → 2 — drives the drawer dot.
      final int unread2 = emissions[1]
          .where(
            (AppNotification n) => n.state == NotificationState.unread,
          )
          .length;
      expect(unread2, 2);
    });

    test('events from other users are filtered out', () async {
      final Stream<List<AppNotification>> stream = repo.watch(userId: 'u-1');
      final List<List<AppNotification>> emissions =
          <List<AppNotification>>[];
      final Future<void> done = stream
          .take(2)
          .listen(emissions.add)
          .asFuture<void>();
      await Future<void>.delayed(Duration.zero);
      // Add a notification for a different user.
      store.notifications.add(
        AppNotification(
          id: 'n-other',
          userId: 'u-other',
          type: NotificationType.tripAssigned,
          payload: <String, Object?>{},
          actionable: false,
          state: NotificationState.unread,
          createdAt: DateTime(2026, 5, 18, 10),
        ),
      );
      // Add one for our user too so .take(2) completes.
      store.notifications.add(
        AppNotification(
          id: 'n-mine',
          userId: 'u-1',
          type: NotificationType.tripAssigned,
          payload: <String, Object?>{},
          actionable: false,
          state: NotificationState.unread,
          createdAt: DateTime(2026, 5, 18, 11),
        ),
      );
      store.emit(DemoStoreEvent.notificationsChanged);
      await done.timeout(const Duration(seconds: 2));
      // Only n-mine should show up — n-other belongs to another user.
      expect(
        emissions[1].map((AppNotification n) => n.id),
        <String>['n-mine'],
      );
    });
  });
}
