import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart' show AppSpacing, AppRadii;
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../missions/application/mission_providers.dart';
import '../../missions/domain/mission.dart';
import '../../reports/presentation/save_to_disk.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import 'admin_expense_comment_dialog.dart';
import 'reports_dialog.dart';
import 'trip_admin_actions.dart';
import 'widgets/cms_layout.dart';
import 'widgets/cms_theme.dart';

/// Trip detail page reached from the CMS dashboard's card grid. Shows the
/// trip's balances, people, and expenses table. Was previously inline on
/// the dashboard as the right-hand pane of a two-column split — promoted
/// to its own route so the dashboard can be a single-column overview.
class CmsTripDetailScreen extends ConsumerWidget {
  const CmsTripDetailScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Trip> tripAsync = ref.watch(tripDetailProvider(tripId));
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final bool isAdmin = me?.role == UserRole.admin;

    return tripAsync.when(
      loading: () => const CmsLayout(
        active: CmsNavItem.home,
        title: 'Loading trip…',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, _) => CmsLayout(
        active: CmsNavItem.home,
        title: 'Trip not found',
        child: Center(child: Text('Error: $e')),
      ),
      data: (Trip trip) => CmsLayout(
        active: CmsNavItem.home,
        title: trip.name,
        titleSubtitle:
            '${trip.countryName} · ${trip.currency} · ${trip.status.name.toUpperCase()}',
        trailing: <Widget>[
          TextButton.icon(
            onPressed: () => context.go('/cms'),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('All trips'),
            style: TextButton.styleFrom(
              foregroundColor: CmsColors.surfaceCard,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(
                Icons.description_outlined,
                color: CmsColors.surfaceCard,
              ),
              tooltip: 'Reports for this trip',
              onPressed: () => showReportsCatalog(context, trip: trip),
            ),
        ],
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: _TripBody(trip: trip),
          ),
        ),
      ),
    );
  }
}

class _TripBody extends ConsumerWidget {
  const _TripBody({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TripBalances> balancesAsync = ref.watch(
      tripBalancesProvider((tripId: trip.id, scope: BalanceScope.trip)),
    );
    final AsyncValue<List<Expense>> expensesAsync =
        ref.watch(tripExpensesProvider(trip.id));
    final DemoStore store = ref.read(demoStoreProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (trip.missionId != null) _MissionChip(missionId: trip.missionId!),
        const SizedBox(height: AppSpacing.md),
        TripAdminActions(trip: trip),
        const SizedBox(height: AppSpacing.lg),
        balancesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: LinearProgressIndicator(),
          ),
          error: (Object e, _) => Text('Balance error: $e'),
          data: (TripBalances b) =>
              _BalanceCards(balances: b, tripId: trip.id),
        ),
        const SizedBox(height: AppSpacing.lg),
        _PeopleSection(trip: trip, store: store),
        const SizedBox(height: AppSpacing.lg),
        expensesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: LinearProgressIndicator(),
          ),
          error: (Object e, _) => Text('Expense load error: $e'),
          data: (List<Expense> list) {
            final List<Expense> sorted = <Expense>[...list]
              ..sort((Expense a, Expense b) =>
                  b.occurredAt.compareTo(a.occurredAt));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'EXPENSES (${sorted.length})',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: CmsColors.textSecondary,
                        letterSpacing: 1.6,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _ExpensesTable(
                  expenses: sorted,
                  currency: trip.currency,
                  store: store,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BalanceCards extends ConsumerWidget {
  const _BalanceCards({required this.balances, required this.tripId});
  final TripBalances balances;
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Allocation> allocs =
        ref.watch(tripAllocationsProvider(tripId)).valueOrNull ??
            const <Allocation>[];
    final Money committed = allocs
        .where((Allocation a) =>
            a.fromUserId == null &&
            a.status != AllocationStatus.declined)
        .fold<Money>(
          balances.totalBudget.isZero
              ? Money.zero(balances.totalSpent.currencyCode)
              : Money.zero(balances.totalBudget.currencyCode),
          (Money acc, Allocation a) => acc + a.amount,
        );
    final Money totalBudget =
        committed.amountMinor > balances.totalBudget.amountMinor
            ? committed
            : balances.totalBudget;
    final Money pendingTopup = allocs
        .where((Allocation a) =>
            a.fromUserId == null &&
            a.status == AllocationStatus.pending)
        .fold<Money>(
          Money.zero(totalBudget.currencyCode),
          (Money acc, Allocation a) => acc + a.amount,
        );
    final Money remaining = totalBudget - balances.totalSpent;
    final bool spentNonZero = !balances.totalSpent.isZero;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                label: 'TOTAL BUDGET',
                value: totalBudget.format(),
                color: CmsColors.brand,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatCard(
                label: 'TOTAL SPENT',
                value: balances.totalSpent.format(),
                color:
                    spentNonZero ? CmsColors.outflow : CmsColors.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatCard(
                label: 'REMAINING',
                value: remaining.format(),
                color: remaining.isNegative
                    ? CmsColors.outflow
                    : CmsColors.success,
              ),
            ),
          ],
        ),
        if (!pendingTopup.isZero) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: CmsColors.amberSoft,
              borderRadius: const BorderRadius.all(AppRadii.sm),
              border: Border.all(
                color: CmsColors.amber.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.hourglass_top_outlined,
                  color: CmsColors.goldDeep,
                  size: 16,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Pending leader acceptance: ${pendingTopup.format()}',
                    style: const TextStyle(
                      color: CmsColors.goldDeep,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CmsColors.textSecondary,
                  letterSpacing: 1.4,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _PeopleSection extends StatelessWidget {
  const _PeopleSection({required this.trip, required this.store});
  final Trip trip;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    final User leader = store.userById(trip.leaderId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'PEOPLE',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: CmsColors.textSecondary,
                letterSpacing: 1.6,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            _PersonChip(user: leader, role: 'Leader'),
            for (final String id in trip.memberIds)
              _PersonChip(user: store.userById(id), role: 'Member'),
          ],
        ),
      ],
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.user, required this.role});
  final User user;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.chip),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircleAvatar(
            radius: 14,
            backgroundColor:
                role == 'Leader' ? CmsColors.brand : CmsColors.gold,
            child: Text(
              _initials(user.displayName),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                user.displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: CmsColors.textPrimary,
                ),
              ),
              Text(
                role,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: CmsColors.textSecondary,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final List<String> parts =
        name.split(' ').where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _ExpensesTable extends ConsumerWidget {
  const _ExpensesTable({
    required this.expenses,
    required this.currency,
    required this.store,
  });
  final List<Expense> expenses;
  final String currency;
  final DemoStore store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (expenses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: CmsColors.surfaceCard,
          borderRadius: const BorderRadius.all(AppRadii.card),
          border: Border.all(color: CmsColors.divider),
        ),
        child: Center(
          child: Text(
            'No expenses logged on this trip yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: CmsColors.textSecondary,
                ),
          ),
        ),
      );
    }

    final Money total = expenses.fold(
      Money.zero(currency),
      (Money a, Expense e) => a + e.amount,
    );

    return Container(
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 10,
            ),
            decoration: const BoxDecoration(
              color: CmsColors.bgElev,
              borderRadius: BorderRadius.vertical(top: AppRadii.card),
            ),
            child: Row(
              children: const <Widget>[
                Expanded(flex: 2, child: _Th(label: 'DATE')),
                Expanded(flex: 3, child: _Th(label: 'USER')),
                Expanded(flex: 2, child: _Th(label: 'CATEGORY')),
                Expanded(flex: 3, child: _Th(label: 'SOURCE')),
                Expanded(flex: 4, child: _Th(label: 'DETAILS')),
                Expanded(
                  flex: 2,
                  child: _Th(label: 'AMOUNT', align: TextAlign.right),
                ),
                SizedBox(width: 48, child: _Th(label: 'RX', align: TextAlign.center)),
                SizedBox(width: 48, child: _Th(label: 'CHAT', align: TextAlign.center)),
              ],
            ),
          ),
          for (final Expense e in expenses) ...<Widget>[
            const Divider(height: 1, color: CmsColors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 12,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: Text(
                      DateFormat.yMMMd().format(e.occurredAt),
                      style: const TextStyle(color: CmsColors.textBody),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      store.userById(e.userId).displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _categoryColor(e.categoryCode),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            store.categoryByCode(e.categoryCode).nameEn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      store.sourceById(e.sourceId).name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      e.details.isEmpty ? '—' : e.details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      e.amount.format(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(width: 48, child: _ReceiptCell(expense: e)),
                  SizedBox(
                    width: 48,
                    child: IconButton(
                      icon: const Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: CmsColors.brand,
                      ),
                      tooltip: 'Comment on this expense',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            AdminExpenseCommentDialog(expense: e),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1, color: CmsColors.divider),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 12,
            ),
            decoration: const BoxDecoration(
              color: CmsColors.bgElev,
              borderRadius: BorderRadius.vertical(bottom: AppRadii.card),
            ),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: CmsColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  total.format(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: CmsColors.brand,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Local category color mapping — keeps cms_trip_detail self-contained
  // and lets the CMS palette stay separate from the mobile AppColors.
  Color _categoryColor(String code) {
    switch (code.toUpperCase()) {
      case 'FOOD':
        return CmsColors.amber;
      case 'TRANSPORT':
        return CmsColors.blue;
      case 'HOTEL':
        return const Color(0xFF7E4B2E);
      case 'PHONE':
        return CmsColors.textBody;
      case 'ENTERTAINMENT':
        return const Color(0xFF7B5BA8);
      case 'TIPS':
        return CmsColors.red;
      case 'TRAVEL':
        return CmsColors.green;
      case 'OTHERS':
      default:
        return CmsColors.textSecondary;
    }
  }
}

class _Th extends StatelessWidget {
  const _Th({required this.label, this.align = TextAlign.left});
  final String label;
  final TextAlign align;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: align,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: CmsColors.textSecondary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _ReceiptCell extends ConsumerStatefulWidget {
  const _ReceiptCell({required this.expense});
  final Expense expense;

  @override
  ConsumerState<_ReceiptCell> createState() => _ReceiptCellState();
}

class _ReceiptCellState extends ConsumerState<_ReceiptCell> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (widget.expense.receiptObjectKey == null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: CmsColors.brand,
            ),
      tooltip: 'View receipt',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: _busy ? null : _open,
    );
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final String url = await ref
          .read(expenseRepositoryProvider)
          .receiptUrl(widget.expense.id);
      openUrl(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open receipt: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _MissionChip extends ConsumerWidget {
  const _MissionChip({required this.missionId});
  final String missionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Mission>? missions =
        ref.watch(missionsProvider).valueOrNull;
    final Mission? mission =
        missions?.where((Mission m) => m.id == missionId).firstOrNull;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: CmsColors.brandTint,
        borderRadius: const BorderRadius.all(AppRadii.chip),
        border: Border.all(color: CmsColors.brandSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.flag_outlined, size: 14, color: CmsColors.brand),
          const SizedBox(width: 6),
          Text(
            mission != null
                ? '${mission.code} · ${mission.name}'
                : 'Mission',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: CmsColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}
