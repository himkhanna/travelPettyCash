import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_coordinator.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
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
    >((Ref ref, ({String tripId, ExpenseGroupBy groupBy}) args) async {
      final User? user = await ref.watch(currentUserProvider.future);
      if (user == null) return <ExpenseSummary>[];
      ref.watch(syncStateProvider);
      return ref
          .read(expenseRepositoryProvider)
          .summary(
            tripId: args.tripId,
            scope: ExpenseSummaryScope.mine,
            groupBy: args.groupBy,
            userId: user.id,
          );
    });
