import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/user.dart';
import '../../features/chat/domain/chat.dart';
import '../../features/expenses/domain/expense.dart';
import '../../features/funds/domain/funding.dart';
import '../../features/notifications/domain/notification.dart';
import '../../features/trips/domain/trip.dart';
import '../api/json_parsers.dart';

/// Single source of truth for the demo. All FakeXxxRepository implementations
/// read and mutate this store; that way an offline expense created in one
/// fake is visible from every other read.
class DemoStore {
  DemoStore._();

  static final DemoStore instance = DemoStore._();

  final List<User> users = <User>[];
  final List<Source> sources = <Source>[];
  final List<ExpenseCategory> categories = <ExpenseCategory>[];
  final List<Trip> trips = <Trip>[];
  final List<Allocation> allocations = <Allocation>[];
  final List<Transfer> transfers = <Transfer>[];
  final List<Expense> expenses = <Expense>[];

  /// Expenses created while FakeConfig.offlineMode == true.
  /// Drained by SyncCoordinator when connectivity returns; in the real app
  /// this is backed by a Drift `pending_expenses` table (Phase 3).
  final List<Expense> pendingExpenses = <Expense>[];

  final List<ChatThread> chatThreads = <ChatThread>[];
  final List<ChatMessage> chatMessages = <ChatMessage>[];
  final List<AppNotification> notifications = <AppNotification>[];

  /// Broadcasts whenever the store mutates, so providers can refresh.
  final StreamController<DemoStoreEvent> _events =
      StreamController<DemoStoreEvent>.broadcast();
  Stream<DemoStoreEvent> get events => _events.stream;
  void emit(DemoStoreEvent e) => _events.add(e);

  bool _loaded = false;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    users
      ..clear()
      ..addAll(await _readList('assets/demo/users.json', parseUser));
    sources
      ..clear()
      ..addAll(await _readList('assets/demo/sources.json', parseSource));
    categories
      ..clear()
      ..addAll(await _readList('assets/demo/categories.json', parseCategory));
    trips
      ..clear()
      ..addAll(await _readList('assets/demo/trips.json', parseTrip));

    final Map<String, String> tripCurrency = <String, String>{
      for (final Trip t in trips) t.id: t.currency,
    };

    final List<Map<String, Object?>> allocRaw = await _readRaw(
      'assets/demo/allocations.json',
    );
    allocations
      ..clear()
      ..addAll(
        allocRaw.map((Map<String, Object?> j) {
          final String currency = tripCurrency[j['tripId']]!;
          return parseAllocation(j, currency: currency);
        }),
      );

    final List<Map<String, Object?>> expRaw = await _readRaw(
      'assets/demo/expenses.json',
    );
    expenses
      ..clear()
      ..addAll(
        expRaw.map((Map<String, Object?> j) {
          final String currency = tripCurrency[j['tripId']]!;
          return parseExpense(j, currency: currency);
        }),
      );

    chatThreads
      ..clear()
      ..addAll(
        await _readList('assets/demo/chat_threads.json', parseChatThread),
      );
    chatMessages
      ..clear()
      ..addAll(
        await _readList('assets/demo/chat_messages.json', parseChatMessage),
      );
    notifications
      ..clear()
      ..addAll(
        await _readList('assets/demo/notifications.json', parseNotification),
      );

    _loaded = true;
  }

  Future<List<Map<String, Object?>>> _readRaw(String path) async {
    final String raw = await rootBundle.loadString(path);
    final List<Object?> decoded = jsonDecode(raw) as List<Object?>;
    return decoded.cast<Map<String, Object?>>();
  }

  Future<List<T>> _readList<T>(
    String path,
    T Function(Map<String, Object?>) parser,
  ) async {
    final List<Map<String, Object?>> raw = await _readRaw(path);
    return raw.map(parser).toList(growable: false);
  }

  // ---------- helpers shared across fake repos ----------

  User userById(String id) => users.firstWhere(
    (User u) => u.id == id,
    orElse: () => throw StateError('User not found: $id'),
  );

  Trip tripById(String id) => trips.firstWhere(
    (Trip t) => t.id == id,
    orElse: () => throw StateError('Trip not found: $id'),
  );

  Source sourceById(String id) => sources.firstWhere(
    (Source s) => s.id == id,
    orElse: () => throw StateError('Source not found: $id'),
  );

  ExpenseCategory categoryByCode(String code) => categories.firstWhere(
    (ExpenseCategory c) => c.code == code,
    orElse: () => throw StateError('Category not found: $code'),
  );

  int unreadNotificationCount(String userId, {String? tripId}) {
    return notifications.where((AppNotification n) {
      if (n.userId != userId) return false;
      if (n.state != NotificationState.unread) return false;
      if (tripId != null) {
        final Object? notifTripId = n.payload['tripId'];
        if (notifTripId != tripId) return false;
      }
      return true;
    }).length;
  }
}

/// Lightweight event taxonomy for invalidating providers when fakes mutate.
enum DemoStoreEvent {
  expensesChanged,
  pendingExpensesChanged,
  allocationsChanged,
  transfersChanged,
  notificationsChanged,
  chatChanged,
  tripsChanged,
}

final Provider<DemoStore> demoStoreProvider = Provider<DemoStore>(
  (Ref ref) => DemoStore.instance,
);
