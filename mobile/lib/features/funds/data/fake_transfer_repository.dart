import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/money/money.dart';
import '../../notifications/domain/notification.dart';
import '../domain/funding.dart';
import 'funds_repository.dart';

class FakeTransferRepository implements TransferRepository {
  FakeTransferRepository(this._store, this._cfg);

  final DemoStore _store;
  final FakeConfig _cfg;

  @override
  Future<List<Transfer>> forTrip(String tripId) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    return _store.transfers
        .where((Transfer t) => t.tripId == tripId)
        .toList(growable: false);
  }

  @override
  Future<Transfer> create({
    required String clientUuid,
    required String tripId,
    required String fromUserId,
    required String toUserId,
    required String sourceId,
    required Money amount,
    String? note,
    required String idempotencyKey,
  }) async {
    await _store.ensureLoaded();

    // Idempotency: replaying returns existing row.
    final int existing = _store.transfers.indexWhere(
      (Transfer t) => t.id == clientUuid,
    );
    if (existing >= 0) return _store.transfers[existing];

    if (!_cfg.offlineMode) {
      await _cfg.waitLatency();
      _cfg.maybeFail(op: 'transfers.create');
    }

    final DateTime now = _cfg.now();
    final Transfer t = Transfer(
      id: clientUuid,
      tripId: tripId,
      fromUserId: fromUserId,
      toUserId: toUserId,
      sourceId: sourceId,
      amount: amount,
      status: AllocationStatus.pending,
      note: note,
      createdAt: now,
    );
    _store.transfers.add(t);

    // Drop a TRANSFER_RECEIVED notification on the recipient.
    _store.notifications.add(
      AppNotification(
        id: 'notif-${clientUuid.substring(0, 8)}',
        userId: toUserId,
        type: NotificationType.transferReceived,
        payload: <String, Object?>{
          'transferId': clientUuid,
          'fromUserId': fromUserId,
          'tripId': tripId,
          'sourceId': sourceId,
          'amountMinor': amount.amountMinor,
          'currency': amount.currencyCode,
          'note': note,
        },
        actionable: true,
        state: NotificationState.unread,
        createdAt: now,
      ),
    );

    _store.emit(DemoStoreEvent.transfersChanged);
    _store.emit(DemoStoreEvent.notificationsChanged);
    return t;
  }

  @override
  Future<Transfer> respond({
    required String transferId,
    required AllocationStatus response,
  }) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    _cfg.maybeFail(op: 'transfers.respond');

    final int i = _store.transfers.indexWhere(
      (Transfer t) => t.id == transferId,
    );
    if (i < 0) throw StateError('Transfer not found: $transferId');
    final Transfer old = _store.transfers[i];
    final DateTime now = _cfg.now();
    final Transfer updated = Transfer(
      id: old.id,
      tripId: old.tripId,
      fromUserId: old.fromUserId,
      toUserId: old.toUserId,
      sourceId: old.sourceId,
      amount: old.amount,
      status: response,
      note: old.note,
      createdAt: old.createdAt,
      respondedAt: now,
    );
    _store.transfers[i] = updated;

    // Tell the sender what happened.
    _store.notifications.add(
      AppNotification(
        id: 'notif-resp-${transferId.substring(0, 8)}',
        userId: old.fromUserId,
        type: response == AllocationStatus.accepted
            ? NotificationType.transferAccepted
            : NotificationType.transferReceived,
        payload: <String, Object?>{
          'transferId': transferId,
          'byUserId': old.toUserId,
          'tripId': old.tripId,
          'amountMinor': old.amount.amountMinor,
          'currency': old.amount.currencyCode,
          'response': response.name,
        },
        actionable: false,
        state: NotificationState.unread,
        createdAt: now,
      ),
    );

    _store.emit(DemoStoreEvent.transfersChanged);
    _store.emit(DemoStoreEvent.notificationsChanged);
    return updated;
  }
}
