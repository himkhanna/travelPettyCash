import 'dart:async';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../funds/data/fake_allocation_repository.dart';
import '../../funds/data/fake_transfer_repository.dart';
import '../../funds/data/funds_repository.dart';
import '../../funds/domain/funding.dart';
import '../domain/notification.dart';
import 'notifications_repository.dart';

class FakeNotificationsRepository implements NotificationsRepository {
  FakeNotificationsRepository(this._store, this._cfg);

  final DemoStore _store;
  final FakeConfig _cfg;

  late final TransferRepository _transfers = FakeTransferRepository(
    _store,
    _cfg,
  );

  late final AllocationRepository _allocations = FakeAllocationRepository(
    _store,
    _cfg,
  );

  @override
  Stream<List<AppNotification>> watch({required String userId}) {
    Future<List<AppNotification>> snapshot() async {
      await _store.ensureLoaded();
      return _store.notifications
          .where((AppNotification n) => n.userId == userId)
          .toList()
        ..sort(
          (AppNotification a, AppNotification b) =>
              b.createdAt.compareTo(a.createdAt),
        );
    }

    final StreamController<List<AppNotification>> controller =
        StreamController<List<AppNotification>>.broadcast();
    StreamSubscription<DemoStoreEvent>? sub;
    controller.onListen = () async {
      controller.add(await snapshot());
      sub = _store.events.listen((DemoStoreEvent e) async {
        if (e == DemoStoreEvent.notificationsChanged) {
          controller.add(await snapshot());
        }
      });
    };
    controller.onCancel = () => sub?.cancel();
    return controller.stream;
  }

  @override
  Future<List<AppNotification>> list({String? cursor, int limit = 30}) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    return _store.notifications.toList(growable: false);
  }

  @override
  Future<AppNotification> markRead(String notificationId) async {
    await _store.ensureLoaded();
    return _mutate(
      notificationId,
      (AppNotification n) => _copyWith(n, state: NotificationState.read),
    );
  }

  @override
  Future<AppNotification> act({
    required String notificationId,
    required NotificationAction action,
  }) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    _cfg.maybeFail(op: 'notifications.act');

    final int i = _store.notifications.indexWhere(
      (AppNotification n) => n.id == notificationId,
    );
    if (i < 0) throw StateError('Notification not found: $notificationId');
    final AppNotification n = _store.notifications[i];

    // Side-effect: drive the underlying transfer / allocation to the
    // right status when the user accepts or declines.
    if (n.type == NotificationType.transferReceived) {
      final String? transferId = n.payload['transferId'] as String?;
      if (transferId != null) {
        await _transfers.respond(
          transferId: transferId,
          response: action == NotificationAction.accept
              ? AllocationStatus.accepted
              : AllocationStatus.declined,
        );
      }
    }
    if (n.type == NotificationType.allocationReceived) {
      final String? allocationId = n.payload['allocationId'] as String?;
      if (allocationId != null) {
        await _allocations.respond(
          allocationId: allocationId,
          response: action == NotificationAction.accept
              ? AllocationStatus.accepted
              : AllocationStatus.declined,
        );
      }
    }

    final AppNotification updated = _copyWith(
      n,
      state: NotificationState.acted,
    );
    _store.notifications[i] = updated;
    _store.emit(DemoStoreEvent.notificationsChanged);
    return updated;
  }

  @override
  Future<void> delete(String notificationId) async {
    await _store.ensureLoaded();
    _store.notifications.removeWhere(
      (AppNotification n) => n.id == notificationId,
    );
    _store.emit(DemoStoreEvent.notificationsChanged);
  }

  @override
  Future<void> deleteAll() async {
    await _store.ensureLoaded();
    _store.notifications.clear();
    _store.emit(DemoStoreEvent.notificationsChanged);
  }

  AppNotification _mutate(
    String id,
    AppNotification Function(AppNotification) f,
  ) {
    final int i = _store.notifications.indexWhere(
      (AppNotification n) => n.id == id,
    );
    if (i < 0) throw StateError('Notification not found: $id');
    final AppNotification updated = f(_store.notifications[i]);
    _store.notifications[i] = updated;
    _store.emit(DemoStoreEvent.notificationsChanged);
    return updated;
  }

  AppNotification _copyWith(
    AppNotification n, {
    NotificationState? state,
  }) => AppNotification(
    id: n.id,
    userId: n.userId,
    type: n.type,
    payload: n.payload,
    actionable: n.actionable,
    state: state ?? n.state,
    createdAt: n.createdAt,
  );
}
