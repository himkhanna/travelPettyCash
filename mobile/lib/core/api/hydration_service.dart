import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/data/user_directory_repository.dart';
import '../../features/auth/domain/user.dart';
import '../../features/chat/data/api_chat_repository.dart';
import '../../features/chat/domain/chat.dart';
import '../../features/expenses/data/api_category_repository.dart';
import '../../features/expenses/data/api_expense_repository.dart';
import '../../features/expenses/domain/expense.dart';
import '../../features/funds/data/api_allocation_repository.dart';
import '../../features/funds/data/api_source_repository.dart';
import '../../features/funds/data/api_transfer_repository.dart';
import '../../features/funds/domain/funding.dart';
import '../../features/notifications/data/api_notifications_repository.dart';
import '../../features/notifications/domain/notification.dart';
import '../../features/trips/data/api_trip_repository.dart';
import '../../features/trips/domain/trip.dart';
import '../fake/demo_store.dart';
import 'api_config.dart';
import 'dio_client.dart';

/// Drives a one-shot pull of every dataset the UI reads from DemoStore
/// when the app is in [BackendMode.api]. After this completes, every
/// existing screen that reads `store.userById(...)`,
/// `store.tripById(...)`, `store.allocations` etc. resolves
/// correctly against backend-sourced data.
///
/// In [BackendMode.fake] this is a no-op — the prototype's JSON assets
/// already populate the store.
class HydrationService {
  HydrationService(this.ref);

  final Ref ref;

  /// Guard so concurrent calls (e.g. login + the hydration gate firing on
  /// the same authenticated resolve) don't fire two parallel passes.
  Future<void>? _inflight;

  /// Replaces every DemoStore collection with API-sourced rows.
  Future<void> hydrateAll() async {
    final Future<void>? running = _inflight;
    if (running != null) return running;
    final Future<void> next = _hydrateAllOnce();
    _inflight = next;
    try {
      await next;
    } finally {
      _inflight = null;
    }
  }

  Future<void> _hydrateAllOnce() async {
    final ApiConfig api = ref.read(apiConfigProvider);
    if (api.mode != BackendMode.api) return;

    final DemoStore store = ref.read(demoStoreProvider);
    final Dio dio = ref.read(dioProvider);

    // 1. Reference data — fetched in parallel; everything else depends on
    //    trip currency, so we need at least sources + trips before per-trip
    //    fetches can interpret amounts.
    final ApiUserDirectoryRepository userRepo =
        ApiUserDirectoryRepository(dio: dio);
    final ApiSourceRepository sourceRepo = ApiSourceRepository(dio: dio);
    final ApiCategoryRepository categoryRepo = ApiCategoryRepository(dio: dio);
    final ApiTripRepository tripRepo = ApiTripRepository(dio: dio);

    final List<dynamic> refData = await Future.wait<dynamic>(<Future<dynamic>>[
      userRepo.all(),
      sourceRepo.all(),
      categoryRepo.all(),
      tripRepo.allTrips(),
    ]);
    final List<User> users = refData[0] as List<User>;
    final List<Source> sources = refData[1] as List<Source>;
    final List<ExpenseCategory> categories = refData[2] as List<ExpenseCategory>;
    final List<Trip> trips = refData[3] as List<Trip>;

    store.users
      ..clear()
      ..addAll(users);
    store.sources
      ..clear()
      ..addAll(sources);
    store.categories
      ..clear()
      ..addAll(categories);
    store.trips
      ..clear()
      ..addAll(trips);

    // 2. Per-trip dynamic data — allocations, transfers, expenses, chat
    //    threads, chat messages. Each runs in parallel across trips.
    final ApiAllocationRepository allocRepo = ApiAllocationRepository(dio: dio);
    final ApiTransferRepository xferRepo = ApiTransferRepository(dio: dio);
    final ApiExpenseRepository expRepo = ApiExpenseRepository(dio: dio);
    final ApiChatRepository chatRepo = ApiChatRepository(dio: dio);

    final List<Allocation> allocs = <Allocation>[];
    final List<Transfer> xfers = <Transfer>[];
    final List<Expense> exps = <Expense>[];
    final List<ChatThread> threads = <ChatThread>[];

    await Future.wait<void>(trips.map((Trip t) async {
      final List<dynamic> trip = await Future.wait<dynamic>(<Future<dynamic>>[
        allocRepo.forTrip(t.id),
        xferRepo.forTrip(t.id),
        expRepo.list(tripId: t.id, limit: 1000),
        chatRepo.threads(tripId: t.id),
      ]);
      allocs.addAll(trip[0] as List<Allocation>);
      xfers.addAll(trip[1] as List<Transfer>);
      exps.addAll(trip[2] as List<Expense>);
      threads.addAll(trip[3] as List<ChatThread>);
    }));

    store.allocations
      ..clear()
      ..addAll(allocs);
    store.transfers
      ..clear()
      ..addAll(xfers);
    store.expenses
      ..clear()
      ..addAll(exps);
    store.chatThreads
      ..clear()
      ..addAll(threads);

    // 3. Per-thread chat messages — separate pass so we have the thread ids.
    final List<List<ChatMessage>> messageBatches = await Future.wait(
      threads.map((ChatThread th) => _loadMessages(chatRepo, th.id)),
    );
    store.chatMessages
      ..clear()
      ..addAll(messageBatches.expand((List<ChatMessage> m) => m));

    // 4. Notifications inbox for the caller.
    final ApiNotificationsRepository notifRepo =
        ApiNotificationsRepository(dio: dio);
    final List<AppNotification> notifs = await notifRepo.list(limit: 200);
    store.notifications
      ..clear()
      ..addAll(notifs);

    // 5. Mark loaded so callers that go through ensureLoaded() short-circuit.
    store.markLoadedAfterApiHydration();
    store.emit(DemoStoreEvent.tripsChanged);
    store.emit(DemoStoreEvent.expensesChanged);
    store.emit(DemoStoreEvent.allocationsChanged);
    store.emit(DemoStoreEvent.transfersChanged);
    store.emit(DemoStoreEvent.chatChanged);
    store.emit(DemoStoreEvent.notificationsChanged);

    debugPrint(
      'Hydration done: ${users.length} users, ${trips.length} trips, '
      '${exps.length} expenses, ${allocs.length} allocations, '
      '${xfers.length} transfers, ${threads.length} threads, '
      '${notifs.length} notifications.',
    );
  }

  Future<List<ChatMessage>> _loadMessages(
    ApiChatRepository repo,
    String threadId,
  ) async {
    // Repo exposes watchMessages as a Stream; for hydration we want one snapshot.
    final Stream<List<ChatMessage>> stream = repo.watchMessages(threadId);
    return stream.first;
  }
}

final Provider<HydrationService> hydrationServiceProvider =
    Provider<HydrationService>((Ref ref) => HydrationService(ref));

/// Resolves when DemoStore is ready for the current authenticated user.
///
/// Watch this on any post-login screen (CMS dashboard, mobile trip list,
/// etc.) and gate rendering on it — in API mode it triggers
/// [HydrationService.hydrateAll] as a side effect the first time a
/// non-null user resolves. In fake mode it short-circuits to `true`
/// since the JSON-asset load handles caching on its own.
final FutureProvider<bool> authenticatedHydrationProvider =
    FutureProvider<bool>((Ref ref) async {
  // We need a user before hydrating: the API repos use the bearer token
  // attached by the Dio interceptor, which only exists post-login.
  final User? user = await ref.watch(currentUserProvider.future);
  if (user == null) return false;
  final ApiConfig api = ref.read(apiConfigProvider);
  if (api.mode == BackendMode.fake) return true;
  await ref.read(hydrationServiceProvider).hydrateAll();
  return true;
});
