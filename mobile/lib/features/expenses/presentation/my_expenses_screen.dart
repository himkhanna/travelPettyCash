import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expense_paging_controller.dart';
import '../application/expenses_providers.dart';
import '../application/pending_receipt_uploads.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';
import 'widgets/expense_filter_sheet.dart';

/// Screen-inventory #7 — My Expenses list with filter (#8) and bulk source
/// reassignment (#25).
///
/// Slice 3A: list is now cursor-paginated via [pagingControllerProvider].
/// The previous one-shot fetch is replaced with a [ListView.builder] that
/// asks the controller for the next page when the viewport gets within
/// 200px of the bottom. Pull-to-refresh resets the cursor.
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
  final ScrollController _scrollCtrl = ScrollController();

  ExpensePagingKey get _key =>
      ExpensePagingKey(tripId: widget.tripId, scope: ExpenseSummaryScope.mine);

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final double remaining =
        _scrollCtrl.position.maxScrollExtent - _scrollCtrl.position.pixels;
    if (remaining < 200) {
      ref.read(pagingControllerProvider(_key).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExpensePagingState paging =
        ref.watch(pagingControllerProvider(_key));
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
            child: tripAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('Error: $e')),
              data: (Trip trip) => _PagedList(
                paging: paging,
                trip: trip,
                scrollCtrl: _scrollCtrl,
                filter: filter,
                editMode: _editMode,
                pendingSourceChange: _pendingSourceChange,
                onTapRow: (Expense e) => context.go(
                  '/m/trips/${widget.tripId}/expenses/${e.id}',
                ),
                onChangeSource: (Expense e, String newId) =>
                    setState(() {
                  if (newId == e.sourceId) {
                    _pendingSourceChange.remove(e.id);
                  } else {
                    _pendingSourceChange[e.id] = newId;
                  }
                }),
                onRefresh: () => ref
                    .read(pagingControllerProvider(_key).notifier)
                    .refresh(),
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
      ref.read(pagingControllerProvider(_key).notifier).refresh();
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

/// The list itself, factored out so [MyExpensesScreen] focuses on chrome.
class _PagedList extends StatelessWidget {
  const _PagedList({
    required this.paging,
    required this.trip,
    required this.scrollCtrl,
    required this.filter,
    required this.editMode,
    required this.pendingSourceChange,
    required this.onTapRow,
    required this.onChangeSource,
    required this.onRefresh,
  });

  final ExpensePagingState paging;
  final Trip trip;
  final ScrollController scrollCtrl;
  final ExpenseFilterState filter;
  final bool editMode;
  final Map<String, String> pendingSourceChange;
  final ValueChanged<Expense> onTapRow;
  final void Function(Expense expense, String newSourceId) onChangeSource;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);

    if (paging.loading && paging.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (paging.error != null && paging.items.isEmpty) {
      return Center(child: Text('${l.common_error}: ${paging.error}'));
    }

    // Filters apply client-side over the loaded items. The backend cursor
    // contract doesn't carry filter args yet (deferred — see comment on
    // [ExpenseRepository.pageForTrip]); composing filter-aware pagination
    // is a Phase 3 server task.
    final List<Expense> rows =
        filter.isEmpty ? paging.items : _applyFilter(paging.items, filter);

    if (rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: <Widget>[
            const SizedBox(height: 80),
            Center(
              child: Text(
                l.expense_list_empty,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    final int footerCount = _shouldShowFooter(paging) ? 1 : 0;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: rows.length + footerCount,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (BuildContext context, int i) {
          if (i >= rows.length) return _PagingFooter(paging: paging);
          final Expense e = rows[i];
          return _ExpenseRow(
            expense: e,
            trip: trip,
            editMode: editMode,
            pendingSourceId: pendingSourceChange[e.id],
            onTap: editMode ? null : () => onTapRow(e),
            onChangeSource: (String newId) => onChangeSource(e, newId),
          );
        },
      ),
    );
  }

  bool _shouldShowFooter(ExpensePagingState p) =>
      p.loadingMore || (!p.hasMore && p.items.isNotEmpty);

  List<Expense> _applyFilter(
    List<Expense> items,
    ExpenseFilterState filter,
  ) {
    return items.where((Expense e) {
      if (filter.categoryCodes.isNotEmpty &&
          !filter.categoryCodes.contains(e.categoryCode)) {
        return false;
      }
      if (filter.sourceIds.isNotEmpty &&
          !filter.sourceIds.contains(e.sourceId)) {
        return false;
      }
      if (filter.memberIds.isNotEmpty &&
          !filter.memberIds.contains(e.userId)) {
        return false;
      }
      if (filter.from != null && e.occurredAt.isBefore(filter.from!)) {
        return false;
      }
      if (filter.to != null && e.occurredAt.isAfter(filter.to!)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }
}

class _PagingFooter extends StatelessWidget {
  const _PagingFooter({required this.paging});
  final ExpensePagingState paging;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (paging.loadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              l.expense_list_loadingMore,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: Text(
          l.expense_list_endOfList,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 1.4,
              ),
        ),
      ),
    );
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
                    if (ref
                        .watch(pendingReceiptExpenseIdsProvider)
                        .contains(expense.id)) ...<Widget>[
                      const SizedBox(height: 6),
                      const _PendingReceiptChip(),
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

/// Slice 3C — sibling chip to [_PendingChip] when the receipt for an
/// expense is queued but the parent expense itself has already synced (or
/// when an online upload failed and is awaiting retry).
class _PendingReceiptChip extends StatelessWidget {
  const _PendingReceiptChip();
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.goldOlive.withValues(alpha: 0.18),
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.cloud_upload_outlined,
            size: 13,
            color: AppColors.goldOlive,
          ),
          const SizedBox(width: 4),
          Text(
            l.receipt_uploadPending,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.goldOlive,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
