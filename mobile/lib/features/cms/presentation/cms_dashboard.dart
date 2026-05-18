import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/api/hydration_service.dart';
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
import 'add_category_dialog.dart';
import 'admin_expense_comment_dialog.dart';
import 'create_trip_dialog.dart';
import 'reports_dialog.dart';
import 'trip_admin_actions.dart';
import 'widgets/cms_layout.dart';

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
    final AsyncValue<User?> userAsync = ref.watch(currentUserProvider);
    final User? me = userAsync.valueOrNull;

    // If the user isn't loaded yet, OR resolved to null (role unset),
    // never show the empty CMS — show a spinner. If we know the role
    // is unset (hasValue + null), bounce back to the portal sign-in.
    if (me == null) {
      if (userAsync.hasValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/portal');
        });
      }
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              if (userAsync.hasValue)
                Column(
                  children: <Widget>[
                    const Text(
                      'Not logged in.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton(
                      onPressed: () => context.go('/portal'),
                      child: const Text('Sign in to Admin Portal'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    // Portal guard: only Admin / Super Admin belong in the CMS. A Member
    // or Leader who lands here (bookmark, link share) is bounced to the
    // wrong-portal screen rather than seeing an empty/forbidden state.
    if (me.role != UserRole.admin && me.role != UserRole.superAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go('/wrong-portal?expected=mobileApp');
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Wait for the API → DemoStore hydration to land before rendering pickers,
    // reports, etc. The user can hard-refresh straight to /cms with a stored
    // token; in that path login_screen never fires hydrateAll, so this gate
    // is the safety net.
    final AsyncValue<bool> hydrationAsync =
        ref.watch(authenticatedHydrationProvider);

    final AsyncValue<List<Trip>> tripsAsync = ref.watch(_allTripsProvider);

    return CmsLayout(
      active: CmsNavItem.dashboard,
      trailing: <Widget>[
        if (me.role == UserRole.admin)
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Add expense category',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (BuildContext _) => const AddCategoryDialog(),
            ),
          ),
        if (me.role == UserRole.admin && _selectedTripId != null)
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Reports for selected trip',
            onPressed: () {
              final Trip? t = tripsAsync.valueOrNull
                  ?.where((Trip t) => t.id == _selectedTripId)
                  .firstOrNull;
              if (t != null) showReportsCatalog(context, trip: t);
            },
          ),
      ],
      floatingActionButton: me.role == UserRole.admin
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.brandBrown,
              foregroundColor: AppColors.cream,
              icon: const Icon(Icons.add),
              label: const Text('CREATE TRIP'),
              onPressed: _openCreateTrip,
            )
          : null,
      child: hydrationAsync.when(
        loading: () => const _HydrationLoading(),
        error: (Object e, _) => Center(
          child: Text('Could not load reference data: $e'),
        ),
        data: (bool ready) => !ready
            ? const _HydrationLoading()
            : tripsAsync.when(
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

class _HydrationLoading extends StatelessWidget {
  const _HydrationLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Loading directory + trips…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
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
    // Expenses now come straight from the API via tripExpensesProvider —
    // previously this read store.expenses (DemoStore cache), so new member
    // expenses created on mobile never appeared here until next hydration.
    final AsyncValue<List<Expense>> expensesAsync =
        ref.watch(tripExpensesProvider(tripId));
    final DemoStore store = ref.read(demoStoreProvider);

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
                      if (trip.missionId != null) ...<Widget>[
                        const SizedBox(height: 6),
                        _MissionChip(missionId: trip.missionId!),
                      ],
                    ],
                  ),
                ),
                _StatusChip(status: trip.status),
              ],
            ),
            TripAdminActions(trip: trip),
            const SizedBox(height: AppSpacing.lg),
            balancesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
              error: (Object e, _) => Text('Balance error: $e'),
              data: (TripBalances b) =>
                  _BalanceCards(balances: b, tripId: tripId),
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
                        color: AppColors.textSecondary,
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
        ),
      ),
    );
  }
}

class _BalanceCards extends ConsumerWidget {
  const _BalanceCards({required this.balances, required this.tripId});
  final TripBalances balances;
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Admin top-ups create new admin→leader allocations but don't mutate the
    // trip's static `totalBudget` field. Sum every admin allocation (pending
    // + accepted) so this card reflects all the cash the admin has committed
    // to the trip, not just the value at create-time. Declined allocations
    // are excluded.
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
    // Prefer the larger of (static budget, sum of allocations). On a fresh
    // trip these are equal; after an Assign Additional Funds run the sum
    // overtakes the static field.
    final Money totalBudget =
        committed.amountMinor > balances.totalBudget.amountMinor
            ? committed
            : balances.totalBudget;

    // Pending top-ups not yet accepted — surfaced inline so the admin sees
    // the gap explicitly rather than wondering why nothing changed.
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
                color: AppColors.brandBrown,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatCard(
                label: 'TOTAL SPENT',
                value: balances.totalSpent.format(),
                color:
                    spentNonZero ? AppColors.outflow : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatCard(
                label: 'REMAINING',
                value: remaining.format(),
                color: remaining.isNegative
                    ? AppColors.outflow
                    : AppColors.success,
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
              color: AppColors.amberSoft,
              borderRadius: const BorderRadius.all(AppRadii.sm),
              border: Border.all(
                color: AppColors.amber.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.hourglass_top_outlined,
                  color: AppColors.goldDeep,
                  size: 16,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Pending leader acceptance: ${pendingTopup.format()}',
                    style: const TextStyle(
                      color: AppColors.goldDeep,
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
                SizedBox(width: 48, child: _Th(label: 'RX', align: TextAlign.center)),
                SizedBox(width: 48, child: _Th(label: 'CHAT', align: TextAlign.center)),
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
                  SizedBox(
                    width: 48,
                    child: _ReceiptCell(expense: e),
                  ),
                  SizedBox(
                    width: 48,
                    child: IconButton(
                      icon: const Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: AppColors.brandBrown,
                      ),
                      tooltip: 'Comment on this expense',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      // Inline comment dialog. Routing to /m/trips/<id>/chat
                      // here would bounce admin via the wrong-portal guard;
                      // the dialog posts straight to the trip chat thread.
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

/// "View receipt" affordance on each expense row. Empty when no receipt
/// is attached; tapping fetches a fresh presigned MinIO URL and opens it
/// in a new browser tab.
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
              color: AppColors.brandBrown,
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

/// Inline pill for the trip detail header that resolves a mission id into
/// its name + code. Falls back to "Mission" if the missions list hasn't
/// loaded yet (rare; missionsProvider is small and pre-warmed by hydration).
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
        color: AppColors.brandTint,
        borderRadius: const BorderRadius.all(AppRadii.chip),
        border: Border.all(color: AppColors.brandSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.flag_outlined, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text(
            mission != null
                ? '${mission.code} · ${mission.name}'
                : 'Mission',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}
