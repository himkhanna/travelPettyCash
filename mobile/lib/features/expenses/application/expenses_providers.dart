import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
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
    FutureProvider.family<List<Expense>, String>(
  (Ref ref, String tripId) {
    ref.watch(fakeRoleProvider);
    final String userId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
    return ref.read(expenseRepositoryProvider).list(tripId: tripId, userId: userId);
  },
);
