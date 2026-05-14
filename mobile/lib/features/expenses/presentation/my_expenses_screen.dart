import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expenses_providers.dart';
import '../domain/expense.dart';
import 'widgets/expense_filter_sheet.dart';

/// Screen-inventory #7 — My Expenses list with filter (#8) and bulk source
/// reassignment (#25).
class MyExpensesScreen extends ConsumerStatefulWidget {
  const MyExpensesScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<MyExpensesScreen> createState() => _MyExpensesScreenState();
}

class _MyExpensesScreenState extends ConsumerState<MyExpensesScreen> {
  bool _editMode = false;
  final Map<String, String> _pendingSourceChange = <String, String>{};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Expense>> expenses = ref.watch(
      myExpensesProvider(widget.tripId),
    );
    final AsyncValue<Trip> tripAsync = ref.watch(
      tripDetailProvider(widget.tripId),
    );
    final ExpenseFilterState filter = ref.watch(
      expenseFilterProvider(widget.tripId),
    );
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final bool canSeeTripScope =
        me?.role == UserRole.leader ||
        me?.role == UserRole.admin ||
        me?.role == UserRole.superAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MY EXPENSES'),
        actions: <Widget>[
          if (!_editMode) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit all (reassign sources)',
              onPressed: () => setState(() {
                _editMode = true;
                _pendingSourceChange.clear();
              }),
            ),
            IconButton(
              icon: const Icon(Icons.donut_large_outlined),
              tooltip: 'Chart view',
              onPressed: () => context.go(
                '/m/trips/${widget.tripId}/expenses/mine/chart',
              ),
            ),
            _FilterButton(
              filter: filter,
              onTap: () => showExpenseFilterSheet(
                context,
                tripId: widget.tripId,
              ),
            ),
          ] else ...<Widget>[
            TextButton(
              onPressed: () => setState(() {
                _editMode = false;
                _pendingSourceChange.clear();
              }),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: _pendingSourceChange.isEmpty || _saving
                  ? null
                  : _saveBulk,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'SAVE ${_pendingSourceChange.length}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ],
      ),
      body: Column(
        children: <Widget>[
          const SyncStatusBanner(),
          if (canSeeTripScope) _ScopeTabs(tripId: widget.tripId),
          if (filter.count > 0 && !_editMode)
            _ActiveFilterChip(filter: filter, tripId: widget.tripId),
          Expanded(
            child: expenses.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('Error: $e')),
              data: (List<Expense> rows) => tripAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Center(child: Text('Error: $e')),
                data: (Trip trip) => rows.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (BuildContext context, int i) {
                          final Expense e = rows[i];
                          return _ExpenseRow(
                            expense: e,
                            trip: trip,
                            editMode: _editMode,
                            pendingSourceId: _pendingSourceChange[e.id],
                            onTap: _editMode
                                ? null
                                : () => context.go(
                                    '/m/trips/${widget.tripId}/expenses/${e.id}',
                                  ),
                            onChangeSource: (String newId) => setState(() {
                              if (newId == e.sourceId) {
                                _pendingSourceChange.remove(e.id);
                              } else {
                                _pendingSourceChange[e.id] = newId;
                              }
                            }),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: TripBottomNav(
        tripId: widget.tripId,
        currentLocation: GoRouterState.of(context).matchedLocation,
      ),
    );
  }

  Future<void> _saveBulk() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(expenseRepositoryProvider)
          .bulkReassignSource(_pendingSourceChange);
      ref.invalidate(myExpensesProvider(widget.tripId));
      ref.invalidate(tripBalancesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reassigned ${_pendingSourceChange.length} expense${_pendingSourceChange.length == 1 ? '' : 's'}',
          ),
        ),
      );
      setState(() {
        _editMode = false;
        _pendingSourceChange.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Bulk save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.brandBrown,
                borderRadius: const BorderRadius.all(AppRadii.chip),
              ),
              alignment: Alignment.center,
              child: const Text(
                'MY EXPENSES',
                style: TextStyle(
                  color: AppColors.cream,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () =>
                  GoRouter.of(context).go('/m/trips/$tripId/expenses/all'),
              borderRadius: const BorderRadius.all(AppRadii.chip),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                child: Text(
                  'TRIP EXPENSES',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.filter, required this.onTap});

  final ExpenseFilterState filter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.filter_alt_outlined),
          tooltip: 'Filter',
          onPressed: onTap,
        ),
        if (filter.count > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: const BoxDecoration(
                color: AppColors.outflow,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Text(
                '${filter.count}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActiveFilterChip extends ConsumerWidget {
  const _ActiveFilterChip({required this.filter, required this.tripId});
  final ExpenseFilterState filter;
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.cream,
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.filter_alt,
            size: 16,
            color: AppColors.brandBrown,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${filter.count} filter${filter.count == 1 ? '' : 's'} active',
              style: const TextStyle(
                color: AppColors.brandBrown,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(expenseFilterProvider(tripId).notifier).state =
                    const ExpenseFilterState(),
            child: const Text('CLEAR'),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends ConsumerWidget {
  const _ExpenseRow({
    required this.expense,
    required this.trip,
    required this.editMode,
    required this.pendingSourceId,
    required this.onChangeSource,
    this.onTap,
  });

  final Expense expense;
  final Trip trip;
  final bool editMode;
  final String? pendingSourceId;
  final ValueChanged<String> onChangeSource;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String currentSourceId = pendingSourceId ?? expense.sourceId;
    final String dateStr = _shortDate(expense.occurredAt);
    final bool dirty = pendingSourceId != null;

    return Material(
      color: dirty ? AppColors.cream : AppColors.surfaceCard,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _AmountCircle(amount: expense.amount.format()),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.forCategory(expense.categoryCode),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          expense.categoryCode,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                letterSpacing: 1.2,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          dateStr,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      expense.details.isEmpty ? '(no details)' : expense.details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    if (editMode)
                      _SourceDropdown(
                        currentSourceId: currentSourceId,
                        originalSourceId: expense.sourceId,
                        onChange: onChangeSource,
                      )
                    else
                      _SourceLabel(sourceId: expense.sourceId),
                    if (expense.pendingSync) ...<Widget>[
                      const SizedBox(height: 6),
                      const _PendingChip(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortDate(DateTime d) {
    const List<String> months = <String>[
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

class _SourceLabel extends ConsumerWidget {
  const _SourceLabel({required this.sourceId});
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Source>> sources = ref.watch(sourcesProvider);
    final String name = sources.maybeWhen(
      data: (List<Source> list) => list
          .firstWhere(
            (Source s) => s.id == sourceId,
            orElse: () => const Source(
              id: '',
              name: '?',
              nameAr: '?',
              isActive: true,
            ),
          )
          .name,
      orElse: () => '…',
    );
    return Text(
      name,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.brandBrown,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _SourceDropdown extends ConsumerWidget {
  const _SourceDropdown({
    required this.currentSourceId,
    required this.originalSourceId,
    required this.onChange,
  });

  final String currentSourceId;
  final String originalSourceId;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Source>> sources = ref.watch(sourcesProvider);
    return sources.maybeWhen(
      data: (List<Source> list) => DropdownButton<String>(
        value: currentSourceId,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: <DropdownMenuItem<String>>[
          for (final Source s in list)
            DropdownMenuItem<String>(value: s.id, child: Text(s.name)),
        ],
        onChanged: (String? v) {
          if (v != null) onChange(v);
        },
      ),
      orElse: () => const LinearProgressIndicator(),
    );
  }
}

class _AmountCircle extends StatelessWidget {
  const _AmountCircle({required this.amount});
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.goldOlive.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.goldOlive, width: 2),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: FittedBox(
          child: Text(
            amount,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.brandBrown,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  const _PendingChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.18),
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.cloud_off, size: 13, color: AppColors.warning),
          const SizedBox(width: 4),
          Text(
            'Pending sync',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: AppColors.goldOlive,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No expenses for the current filter.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
