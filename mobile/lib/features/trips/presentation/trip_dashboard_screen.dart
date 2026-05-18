import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/pdd_primitives.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../funds/presentation/pending_allocations_banner.dart';
import '../../notifications/application/notifications_providers.dart';
import '../../notifications/domain/notification.dart';
import '../application/trips_providers.dart';
import '../domain/trip.dart';
import 'trip_drawer.dart';

/// Trip Dashboard per the design handoff (`screens-trip.jsx → TripDashboard`).
///
/// Layout:
/// 1. [PddTopBar] with leadingBack + trip name + "code · dates" subtitle
/// 2. [PendingAllocationsBanner] (kept — surfaces pending allocs/transfers)
/// 3. Balance card — member sees personal wallet, leader/admin sees trip
///    total with progress bar
/// 4. Donut + top-4 category breakdown card
/// 5. Team activity (leader/admin/super only) — per-member spent/allocated
///    with colored progress bar
/// 6. Recent expenses (4 latest)
/// 7. FAB `+` for member/leader (bottom-right, 56×56)
class TripDashboardScreen extends ConsumerWidget {
  const TripDashboardScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Trip> tripAsync = ref.watch(tripDetailProvider(tripId));
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final bool isLeaderPlus =
        me?.role == UserRole.leader ||
        me?.role == UserRole.admin ||
        me?.role == UserRole.superAdmin;

    // Notifications bell — red dot if any unread.
    final List<AppNotification> notifs =
        ref.watch(myNotificationsProvider).valueOrNull ??
            const <AppNotification>[];
    final bool hasUnread =
        notifs.any((AppNotification n) => n.state == NotificationState.unread);

    final bool canAddExpense =
        me?.role == UserRole.member || me?.role == UserRole.leader;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      drawer: TripDrawer(tripId: tripId),
      body: SafeArea(
        bottom: false,
        child: tripAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, _) => Center(child: Text('Error: $e')),
          data: (Trip trip) => Stack(
            children: <Widget>[
              CustomScrollView(
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: PddTopBar(
                      user: me,
                      leadingBack: true,
                      onBack: () => context.go('/m/trips'),
                      title: trip.name,
                      subtitle: '${_tripCode(trip)} · ${_dateRange(trip)}',
                      onNotifs: () => context.go('/m/notifications'),
                      hasNotif: hasUnread,
                      actions: <Widget>[
                        PddTopBarIconButton(
                          icon: Icons.chat_bubble_outline,
                          tooltip: 'Trip chat',
                          onTap: () => context.go('/m/trips/$tripId/chat'),
                        ),
                      ],
                    ),
                  ),
                  const SliverToBoxAdapter(child: SyncStatusBanner()),
                  SliverToBoxAdapter(
                    child: PendingAllocationsBanner(tripId: tripId),
                  ),
                  // Balance card(s)
                  SliverToBoxAdapter(
                    child: _BalanceSection(
                      tripId: tripId,
                      trip: trip,
                      isLeaderPlus: isLeaderPlus,
                    ),
                  ),
                  // Leader-only Allocate funds entry. Lives here (inside the
                  // trip) instead of on the trips list — those actions were
                  // contextless when a leader had multiple active delegations.
                  if (me?.role == UserRole.leader &&
                      trip.status != TripStatus.closed)
                    SliverToBoxAdapter(
                      child: _AllocateActionRow(tripId: tripId),
                    ),
                  // Donut + categories
                  SliverToBoxAdapter(
                    child: _BreakdownCard(
                      tripId: tripId,
                      trip: trip,
                      isLeaderPlus: isLeaderPlus,
                      meId: me?.id,
                    ),
                  ),
                  // Team activity
                  if (isLeaderPlus) ...<Widget>[
                    SliverToBoxAdapter(
                      child: PddSectionLabel(
                        label: 'Team activity',
                        trailing: TextButton(
                          onPressed: () =>
                              context.go('/m/trips/$tripId/expenses/all'),
                          child: const Text('View all →'),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _TeamActivityCard(tripId: tripId, trip: trip),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: PddSectionLabel(
                      label: isLeaderPlus ? 'Recent expenses' : 'Your expenses',
                      trailing: TextButton(
                        onPressed: () => context.go(
                          isLeaderPlus
                              ? '/m/trips/$tripId/expenses/all'
                              : '/m/trips/$tripId/expenses/mine',
                        ),
                        child: const Text('See all →'),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _RecentExpenses(
                      tripId: tripId,
                      trip: trip,
                      meId: me?.id,
                      isLeaderPlus: isLeaderPlus,
                    ),
                  ),
                  if (trip.status == TripStatus.closed)
                    const SliverToBoxAdapter(child: _ClosedBanner()),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
              if (canAddExpense)
                Positioned(
                  right: 20,
                  bottom: 24,
                  child: _AddExpenseFab(
                    onTap: () =>
                        context.go('/m/trips/$tripId/expenses/new'),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: TripBottomNav(
        tripId: tripId,
        currentLocation: GoRouterState.of(context).matchedLocation,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Balance section
// ────────────────────────────────────────────────────────────────────

class _BalanceSection extends ConsumerWidget {
  const _BalanceSection({
    required this.tripId,
    required this.trip,
    required this.isLeaderPlus,
  });
  final String tripId;
  final Trip trip;
  final bool isLeaderPlus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TripBalances> meBalancesAsync = ref.watch(
      tripBalancesProvider((tripId: tripId, scope: BalanceScope.me)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        children: <Widget>[
          meBalancesAsync.maybeWhen(
            data: (TripBalances b) => _PersonalWalletCard(
              balance: b.totalBalance,
              spent: b.totalSpent,
              allocated: b.totalBalance + b.totalSpent,
              currency: trip.currency,
              isLeader: isLeaderPlus,
            ),
            orElse: () => const _BalancePlaceholder(),
          ),
          if (isLeaderPlus) ...<Widget>[
            const SizedBox(height: 10),
            _LeaderTripTotal(tripId: tripId, trip: trip),
          ],
        ],
      ),
    );
  }
}

/// Trip-wide total card shown only for leader/admin/super-admin roles.
/// Pulled out so the watch on the trip-scope provider lives only on the
/// path that needs it.
class _LeaderTripTotal extends ConsumerWidget {
  const _LeaderTripTotal({required this.tripId, required this.trip});
  final String tripId;
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TripBalances> async = ref.watch(
      tripBalancesProvider((tripId: tripId, scope: BalanceScope.trip)),
    );
    return async.maybeWhen(
      data: (TripBalances b) => _TripTotalCard(
        spent: b.totalSpent,
        budget: trip.totalBudget,
        onTap: () =>
            GoRouter.of(context).go('/m/trips/$tripId/expenses/all'),
      ),
      orElse: () => const _BalancePlaceholder(),
    );
  }
}

/// Personal wallet hero — forest-green gradient. Used for Member + Leader.
class _PersonalWalletCard extends StatelessWidget {
  const _PersonalWalletCard({
    required this.balance,
    required this.spent,
    required this.allocated,
    required this.currency,
    required this.isLeader,
  });

  final Money balance;
  final Money spent;
  final Money allocated;
  final String currency;
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.brandDeep,
            AppColors.brand,
            Color(0xFF155049),
          ],
          stops: <double>[0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isLeader ? 'Your wallet' : 'Your balance',
            style: AppTypography.geist(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.06 * 11,
              color: AppColors.bgCard.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  _amountOnly(balance),
                  style: AppTypography.geistMono(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: AppColors.bgCard,
                    letterSpacing: -0.02 * 32,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                currency,
                style: AppTypography.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.bgCard.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _walletStat(label: 'Spent', amount: spent, currency: currency),
              Container(
                width: 1,
                height: 26,
                color: AppColors.bgCard.withValues(alpha: 0.15),
                margin: const EdgeInsets.symmetric(horizontal: 14),
              ),
              _walletStat(
                label: 'Allocated',
                amount: allocated,
                currency: currency,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _walletStat({
    required String label,
    required Money amount,
    required String currency,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: AppTypography.geist(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.06 * 11,
            color: AppColors.bgCard.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _amountOnly(amount),
          style: AppTypography.geistMono(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.bgCard,
          ),
        ),
      ],
    );
  }
}

/// Trip-wide total card — white background, brand→gold gradient bar.
class _TripTotalCard extends StatelessWidget {
  const _TripTotalCard({
    required this.spent,
    required this.budget,
    required this.onTap,
  });

  final Money spent;
  final Money budget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double pct = budget.isZero
        ? 0
        : (spent.amountMinor / budget.amountMinor).clamp(0.0, 1.0);
    final Money remaining = budget - spent;
    return Material(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'TRIP TOTAL',
                style: AppTypography.microLabel(),
              ),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: _amountOnly(spent),
                      style: AppTypography.geistMono(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink1,
                        letterSpacing: -0.02 * 28,
                      ),
                    ),
                    TextSpan(
                      text: '  ${spent.currencyCode}',
                      style: AppTypography.geist(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 6,
                  color: AppColors.bgInset,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: pct,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[AppColors.brand, AppColors.gold],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${(pct * 100).round()}% of ${_amountOnly(budget)} ${budget.currencyCode}',
                      style: AppTypography.geist(
                        fontSize: 11,
                        color: AppColors.ink3,
                      ),
                    ),
                  ),
                  Text(
                    '${_amountOnly(remaining)} left',
                    style: AppTypography.geistMono(
                      fontSize: 11,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalancePlaceholder extends StatelessWidget {
  const _BalancePlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: AppColors.bgInset,
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Donut + category breakdown
// ────────────────────────────────────────────────────────────────────

class _BreakdownCard extends ConsumerWidget {
  const _BreakdownCard({
    required this.tripId,
    required this.trip,
    required this.isLeaderPlus,
    required this.meId,
  });

  final String tripId;
  final Trip trip;
  final bool isLeaderPlus;
  final String? meId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Member sees only their own expenses for the breakdown; leader+ sees all.
    final AsyncValue<List<Expense>> expsAsync = isLeaderPlus
        ? ref.watch(tripExpensesProvider(tripId))
        : ref.watch(myExpensesProvider(tripId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: expsAsync.maybeWhen(
        data: (List<Expense> expenses) {
          final Money total = expenses.fold<Money>(
            Money.zero(trip.currency),
            (Money a, Expense e) => a + e.amount,
          );
          // Top 4 categories by total spent.
          final Map<String, Money> byCat = <String, Money>{};
          for (final Expense e in expenses) {
            byCat.update(
              e.categoryCode,
              (Money v) => v + e.amount,
              ifAbsent: () => e.amount,
            );
          }
          final List<MapEntry<String, Money>> sorted = byCat.entries
              .where((MapEntry<String, Money> e) => !e.value.isZero)
              .toList()
            ..sort((MapEntry<String, Money> a, MapEntry<String, Money> b) =>
                b.value.amountMinor.compareTo(a.value.amountMinor));
          final List<MapEntry<String, Money>> top4 = sorted.take(4).toList();

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                PddDonut(
                  spent: total.amountMinor.toDouble(),
                  allocated: trip.totalBudget.amountMinor.toDouble(),
                  size: 130,
                  strokeWidth: 14,
                  label: 'spent',
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: top4.isEmpty
                      ? Text(
                          'No expenses yet',
                          style: AppTypography.geist(
                            fontSize: 13,
                            color: AppColors.ink3,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (final MapEntry<String, Money> e in top4)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _CategoryRow(
                                  code: e.key,
                                  amount: e.value,
                                  ref: ref,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
        orElse: () => const _BreakdownPlaceholder(),
      ),
    );
  }
}

class _BreakdownPlaceholder extends StatelessWidget {
  const _BreakdownPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 162,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.code,
    required this.amount,
    required this.ref,
  });
  final String code;
  final Money amount;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final DemoStore store = ref.read(demoStoreProvider);
    String name;
    try {
      name = store.categoryByCode(code).nameEn;
    } catch (_) {
      name = code;
    }
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.forCategory(code),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            style: AppTypography.geist(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.ink2,
            ),
          ),
        ),
        Text(
          _amountOnly(amount),
          style: AppTypography.geistMono(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ink1,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Team activity
// ────────────────────────────────────────────────────────────────────

class _TeamActivityCard extends ConsumerWidget {
  const _TeamActivityCard({required this.tripId, required this.trip});
  final String tripId;
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Expense>> expsAsync =
        ref.watch(tripExpensesProvider(tripId));
    final AsyncValue<List<Allocation>> allocsAsync =
        ref.watch(tripAllocationsProvider(tripId));
    final DemoStore store = ref.read(demoStoreProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Builder(builder: (BuildContext context) {
          final List<Expense> expenses = expsAsync.valueOrNull ?? <Expense>[];
          final List<Allocation> allocs =
              allocsAsync.valueOrNull ?? <Allocation>[];

          // Pre-compute per-user spent and allocated.
          final Map<String, Money> spent = <String, Money>{};
          for (final Expense e in expenses) {
            spent.update(
              e.userId,
              (Money v) => v + e.amount,
              ifAbsent: () => e.amount,
            );
          }
          final Map<String, Money> allocated = <String, Money>{};
          for (final Allocation a in allocs) {
            if (a.status != AllocationStatus.accepted) continue;
            allocated.update(
              a.toUserId,
              (Money v) => v + a.amount,
              ifAbsent: () => a.amount,
            );
          }

          // The team is the leader + memberIds. Show up to 4.
          final List<String> teamIds = <String>[
            trip.leaderId,
            ...trip.memberIds,
          ].take(4).toList();

          return Column(
            children: <Widget>[
              for (int i = 0; i < teamIds.length; i++)
                _TeamRow(
                  user: _safeUser(store, teamIds[i]),
                  spent: spent[teamIds[i]] ?? Money.zero(trip.currency),
                  allocated:
                      allocated[teamIds[i]] ?? Money.zero(trip.currency),
                  showDivider: i > 0,
                ),
            ],
          );
        }),
      ),
    );
  }

  User _safeUser(DemoStore store, String id) {
    try {
      return store.userById(id);
    } catch (_) {
      return User(
        id: id,
        username: 'unknown',
        displayName: 'Unknown',
        displayNameAr: '',
        email: '',
        role: UserRole.member,
        isActive: true,
      );
    }
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.user,
    required this.spent,
    required this.allocated,
    required this.showDivider,
  });

  final User user;
  final Money spent;
  final Money allocated;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final double pct = allocated.isZero
        ? 0
        : (spent.amountMinor / allocated.amountMinor).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(top: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Row(
        children: <Widget>[
          PddAvatar(user: user, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user.displayName,
                  style: AppTypography.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 4,
                    color: AppColors.bgInset,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: pct,
                        child: Container(color: PddAvatar.colorFor(user.id)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                _amountOnly(spent),
                style: AppTypography.geistMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink1,
                ),
              ),
              Text(
                'of ${_amountOnly(allocated)}',
                style: AppTypography.geistMono(
                  fontSize: 10,
                  color: AppColors.ink3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Recent expenses
// ────────────────────────────────────────────────────────────────────

class _RecentExpenses extends ConsumerWidget {
  const _RecentExpenses({
    required this.tripId,
    required this.trip,
    required this.meId,
    required this.isLeaderPlus,
  });
  final String tripId;
  final Trip trip;
  final String? meId;
  final bool isLeaderPlus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Expense>> expsAsync = isLeaderPlus
        ? ref.watch(tripExpensesProvider(tripId))
        : ref.watch(myExpensesProvider(tripId));
    final DemoStore store = ref.read(demoStoreProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: expsAsync.when(
        loading: () => _placeholder(),
        error: (Object e, _) => _placeholder(),
        data: (List<Expense> list) {
          final List<Expense> sorted = <Expense>[...list]
            ..sort((Expense a, Expense b) =>
                b.occurredAt.compareTo(a.occurredAt));
          final List<Expense> recent = sorted.take(4).toList();

          return Container(
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: recent.isEmpty
                ? const PddEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No expenses yet',
                    body: 'Add your first expense to get started.',
                  )
                : Column(
                    children: <Widget>[
                      for (int i = 0; i < recent.length; i++) ...<Widget>[
                        if (i > 0)
                          const Divider(height: 1, color: AppColors.line),
                        PddExpenseRow(
                          categoryCode: recent[i].categoryCode,
                          categoryLabel: _catLabel(store, recent[i].categoryCode),
                          vendor: recent[i].details.isEmpty
                              ? _catLabel(store, recent[i].categoryCode)
                              : recent[i].details,
                          timeLabel: DateFormat('d MMM, HH:mm')
                              .format(recent[i].occurredAt),
                          amountFormatted: _amountOnly(recent[i].amount),
                          currency: recent[i].amount.currencyCode,
                          hasReceipt: recent[i].receiptObjectKey != null,
                          userInitials: isLeaderPlus
                              ? _initials(store, recent[i].userId)
                              : null,
                          onTap: () => GoRouter.of(context).go(
                            '/m/trips/$tripId/expenses/${recent[i].id}',
                          ),
                        ),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }

  String _catLabel(DemoStore store, String code) {
    try {
      return store.categoryByCode(code).nameEn;
    } catch (_) {
      return code;
    }
  }

  String? _initials(DemoStore store, String userId) {
    try {
      final User u = store.userById(userId);
      final List<String> parts = u.displayName.split(' ');
      if (parts.isEmpty || parts.first.isEmpty) return null;
      if (parts.length == 1) return parts.first[0].toUpperCase();
      return (parts.first[0] + parts.last[0]).toUpperCase();
    } catch (_) {
      return null;
    }
  }

  Widget _placeholder() => Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
}

// ────────────────────────────────────────────────────────────────────
// Allocate funds entry (leader, inside trip)
// ────────────────────────────────────────────────────────────────────

class _AllocateActionRow extends StatelessWidget {
  const _AllocateActionRow({required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _DashboardAction(
              label: 'Allocate funds',
              sub: 'Hand cash to a member',
              icon: Icons.account_balance_wallet_outlined,
              onTap: () => GoRouter.of(context).go('/m/trips/$tripId/allocate'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DashboardAction(
              label: 'Manage funds',
              sub: 'See balances by source',
              icon: Icons.tune,
              onTap: () =>
                  GoRouter.of(context).go('/m/trips/$tripId/manage-funds'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardAction extends StatelessWidget {
  const _DashboardAction({
    required this.label,
    required this.sub,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final String sub;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.brandTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: AppColors.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      style: AppTypography.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: AppTypography.geist(
                        fontSize: 11,
                        color: AppColors.ink3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Floating action button
// ────────────────────────────────────────────────────────────────────

class _AddExpenseFab extends StatelessWidget {
  const _AddExpenseFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.fab,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.add, color: AppColors.bgCard, size: 26),
        ),
      ),
    );
  }
}

class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.redSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.lock_outline, color: AppColors.red, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'This trip is closed. Expenses are read-only.',
                style: AppTypography.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Shared helpers
// ────────────────────────────────────────────────────────────────────

String _amountOnly(Money m) =>
    NumberFormat.decimalPattern('en_US').format(m.amountMinor / 100.0);

String _tripCode(Trip t) {
  final String tail =
      t.id.length >= 4 ? t.id.substring(t.id.length - 4).toUpperCase() : t.id;
  return '${t.countryCode.toUpperCase()}-$tail';
}

String _dateRange(Trip t) {
  final DateFormat fmt = DateFormat('d MMM yyyy');
  if (t.closedAt != null) {
    return '${fmt.format(t.createdAt)} – ${fmt.format(t.closedAt!)}';
  }
  return 'From ${fmt.format(t.createdAt)}';
}

