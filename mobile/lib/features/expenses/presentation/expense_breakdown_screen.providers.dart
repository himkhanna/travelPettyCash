import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_coordinator.dart';
import '../../auth/application/auth_providers.dart';
import '../application/expenses_providers.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';

final FutureProviderFamily<
  List<ExpenseSummary>,
  ({String tripId, ExpenseGroupBy groupBy})
>
mySummaryProvider =
    FutureProvider.family<
      List<ExpenseSummary>,
      ({String tripId, ExpenseGroupBy groupBy})
    >((Ref ref, ({String tripId, ExpenseGroupBy groupBy}) args) {
      ref.watch(fakeRoleProvider);
      ref.watch(syncStateProvider);
      final String userId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
      return ref
          .read(expenseRepositoryProvider)
          .summary(
            tripId: args.tripId,
            scope: ExpenseSummaryScope.mine,
            groupBy: args.groupBy,
            userId: userId,
          );
    });
