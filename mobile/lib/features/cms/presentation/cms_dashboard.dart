import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/domain/expense.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import 'create_trip_dialog.dart';

/// Admin / Super Admin console. Trip list on the left, selected-trip
/// expenses + balances on the right.
class CmsDashboard extends ConsumerStatefulWidget {
  const CmsDashboard({super.key});

  @override
  ConsumerState<CmsDashboard> createState() => _CmsDashboardState();
}

class _CmsDashboardState extends ConsumerState<CmsDashboard> {
  String? _selectedTripId;

  @override
  Widget build(BuildContext context) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final AsyncValue<List<Trip>> tripsAsync = ref.watch(_allTripsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Row(
          children: <Widget>[
            const Icon(Icons.shield_outlined, color: AppColors.brandBrown),
            const SizedBox(width: AppSpacing.sm),
            const Text('PDD Petty Cash — Admin Console'),
            const SizedBox(width: AppSpacing.md),
            if (me != null)
              Chip(
                label: Text(
                  '${me.displayName} · ${_roleLabel(me.role)}',
                ),
                backgroundColor: AppColors.cream,
              ),
          ],
        ),
        actions: <Widget>[
          if (me?.role == UserRole.admin) ...<Widget>[
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('CREATE TRIP'),
              onPressed: () => _openCreateTrip(),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
        ],
      ),
      body: tripsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (List<Trip> trips) {
          if (_selectedTripId == null && trips.isNotEmpty) {
            // Pick the first active trip as the default selection.
            _selectedTripId = trips
                .firstWhere(
                  (Trip t) => t.status == TripStatus.active,
                  orElse: () => trips.first,
                )
                .id;
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: 360,
                child: _TripsList(
                  trips: trips,
                  selectedId: _selectedTripId,
                  onSelect: (String id) =>
                      setState(() => _selectedTripId = id),
                ),
              ),
              const VerticalDivider(width: 1, color: AppColors.divider),
              Expanded(
                child: _selectedTripId == null
                    ? const _EmptyDetail()
                    : _TripDetail(tripId: _selectedTripId!),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openCreateTrip() async {
    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) => const CreateTripDialog(),
    );
    if (created == true && mounted) {
      ref.invalidate(_allTripsProvider);
    }
  }

  String _roleLabel(UserRole r) {
    switch (r) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.superAdmin:
        return 'Director General';
      default:
        return r.apiCode;
    }
  }
}

/// All trips visible to Admin/SuperAdmin (status-agnostic).
final FutureProvider<List<Trip>> _allTripsProvider = FutureProvider<List<Trip>>((
  Ref ref,
) async {
  final User? user = await ref.watch(currentUserProvider.future);
  if (user == null) return <Trip>[];
  return ref.read(tripRepositoryProvider).allTrips();
});

class _TripsList extends StatelessWidget {
  const _TripsList({
    required this.trips,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Trip> trips;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  'TRIPS',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 1.6,
                  ),
                ),
                const Spacer(),
                Text(
                  '${trips.length} total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: trips.isEmpty
                ? const Center(child: Text('No trips yet.'))
                : ListView.separated(
                    itemCount: trips.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (BuildContext context, int i) {
                      final Trip t = trips[i];
                      return _TripRow(
                        trip: t,
                        selected: selectedId == t.id,
                        onTap: () => onSelect(t.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({
    required this.trip,
    required this.selected,
    required this.onTap,
  });

  final Trip trip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.cream : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Text(
                _flagFor(trip.countryCode),
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      trip.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${trip.countryName} · ${trip.currency} · ${trip.memberIds.length + 1} member${trip.memberIds.length == 0 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: trip.status),
            ],
          ),
        ),
      ),
    );
  }

  String _flagFor(String code) {
    if (code.length != 2) return '🏳️';
    const int base = 0x1F1E6;
    final int a = code.toUpperCase().codeUnitAt(0) - 0x41 + base;
    final int b = code.toUpperCase().codeUnitAt(1) - 0x41 + base;
    return String.fromCharCodes(<int>[a, b]);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final TripStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      TripStatus.active => AppColors.success,
      TripStatus.draft => AppColors.warning,
      TripStatus.closed => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.flight, size: 56, color: AppColors.goldOlive),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Select a trip on the left to view expenses.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripDetail extends ConsumerWidget {
  const _TripDetail({required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Trip> tripAsync = ref.watch(tripDetailProvider(tripId));
    final AsyncValue<TripBalances> balancesAsync = ref.watch(
      tripBalancesProvider((tripId: tripId, scope: BalanceScope.trip)),
    );
    final DemoStore store = ref.read(demoStoreProvider);
    final List<Expense> tripExpenses =
        store.expenses.where((Expense e) => e.tripId == tripId).toList()
          ..sort((Expense a, Expense b) => b.occurredAt.compareTo(a.occurredAt));

    return tripAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => Center(child: Text('Error: $e')),
      data: (Trip trip) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        trip.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${trip.countryName} · ${trip.currency} · created ${DateFormat.yMMMd().format(trip.createdAt)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: trip.status),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            balancesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
              error: (Object e, _) => Text('Balance error: $e'),
              data: (TripBalances b) => _BalanceCards(balances: b),
            ),
            const SizedBox(height: AppSpacing.lg),
            _PeopleSection(trip: trip, store: store),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'EXPENSES (${tripExpenses.length})',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ExpensesTable(
              expenses: tripExpenses,
              currency: trip.currency,
              store: store,
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCards extends StatelessWidget {
  const _BalanceCards({required this.balances});
  final TripBalances balances;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatCard(
            label: 'TOTAL BUDGET',
            value: balances.totalBudget.format(),
            color: AppColors.brandBrown,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatCard(
            label: 'TOTAL SPENT',
            value: balances.totalSpent.format(),
            color: AppColors.outflow,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatCard(
            label: 'REMAINING',
            value: balances.totalBalance.format(),
            color: balances.totalBalance.isNegative
                ? AppColors.outflow
                : AppColors.success,
          ),
        ),
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
        color: AppColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
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
            color: AppColors.textSecondary,
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
        color: AppColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.chip),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircleAvatar(
            radius: 14,
            backgroundColor: role == 'Leader'
                ? AppColors.brandBrown
                : AppColors.goldOlive,
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
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                role,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final List<String> parts = name
        .split(' ')
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _ExpensesTable extends StatelessWidget {
  const _ExpensesTable({
    required this.expenses,
    required this.currency,
    required this.store,
  });

  final List<Expense> expenses;
  final String currency;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: const BorderRadius.all(AppRadii.card),
          border: Border.all(color: AppColors.divider),
        ),
        child: Center(
          child: Text(
            'No expenses logged on this trip yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
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
        color: AppColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.cream,
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
              ],
            ),
          ),
          for (final Expense e in expenses) ...<Widget>[
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: Text(DateFormat.yMMMd().format(e.occurredAt)),
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
                            color: AppColors.forCategory(e.categoryCode),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          store.categoryByCode(e.categoryCode).nameEn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                ],
              ),
            ),
          ],
          const Divider(height: 1, color: AppColors.divider),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.cream,
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
                    ),
                  ),
                ),
                Text(
                  total.format(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBrown,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
        color: AppColors.textSecondary,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
