import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../auth/application/auth_providers.dart';
import '../data/category_repository.dart';
import '../data/expense_repository.dart';
import '../data/fake_category_repository.dart';
import '../data/fake_expense_repository.dart';
import '../domain/expense.dart';

final Provider<ExpenseRepository> expenseRepositoryProvider =
    Provider<ExpenseRepository>(
      (Ref ref) => FakeExpenseRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      ),
    );

final Provider<CategoryRepository> categoryRepositoryProvider =
    Provider<CategoryRepository>(
      (Ref ref) => FakeCategoryRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      ),
    );

final FutureProvider<List<ExpenseCategory>> categoriesProvider =
    FutureProvider<List<ExpenseCategory>>(
      (Ref ref) => ref.read(categoryRepositoryProvider).all(),
    );

final FutureProviderFamily<List<Expense>, String> myExpensesProvider =
    FutureProvider.family<List<Expense>, String>((Ref ref, String tripId) {
      // Rebuild when role flips, when pending queue drains, or when an expense
      // is created/updated/deleted.
      ref.watch(fakeRoleProvider);
      ref.watch(syncStateProvider);
      final String userId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
      return ref
          .read(expenseRepositoryProvider)
          .list(tripId: tripId, userId: userId);
    });

/// Per-trip view of pending expenses (for "X pending" banners).
final ProviderFamily<int, String> pendingCountForTripProvider =
    Provider.family<int, String>((Ref ref, String tripId) {
      ref.watch(syncStateProvider);
      final DemoStore store = ref.read(demoStoreProvider);
      final String userId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
      return store.pendingExpenses
          .where((Expense e) => e.tripId == tripId && e.userId == userId)
          .length;
    });
