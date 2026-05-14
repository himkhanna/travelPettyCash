import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../auth/domain/user.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/funds_providers.dart';
import '../domain/funding.dart';
import 'manage_member_funds_modal.dart';

/// Screen-inventory #20 — Manage Funds overview. Leader sees current
/// allocations per member per source, can tap a member to add more.
class ManageFundsScreen extends ConsumerWidget {
  const ManageFundsScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Trip> tripAsync = ref.watch(tripDetailProvider(tripId));
    final AsyncValue<List<Allocation>> allocsAsync = ref.watch(
      tripAllocationsProvider(tripId),
    );
    final AsyncValue<List<Source>> sourcesAsync = ref.watch(sourcesProvider);
    final AsyncValue<Map<String, Money>> availableAsync = ref.watch(
      leaderAvailableBySourceProvider(tripId),
    );
    final DemoStore store = ref.read(demoStoreProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/m/trips/$tripId/dashboard'),
        ),
        title: const Text('MANAGE FUNDS'),
      ),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (Trip trip) => allocsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, _) => Center(child: Text('Error: $e')),
          data: (List<Allocation> allocs) => sourcesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object e, _) => Center(child: Text('Error: $e')),
            data: (List<Source> sources) => availableAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('Error: $e')),
              data: (Map<String, Money> avail) {
                final Money remaining = sources.fold<Money>(
                  Money.zero(trip.currency),
                  (Money acc, Source s) =>
                      acc + (avail[s.id] ?? Money.zero(trip.currency)),
                );
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _RemainingPill(remaining: remaining),
                      const SizedBox(height: AppSpacing.md),
                      _PerSourceBalances(sources: sources, available: avail),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: <Widget>[
                          Text(
                            'PER MEMBER',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1.6,
                                ),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('ALLOCATE NEW'),
                            onPressed: () => context.go(
                              '/m/trips/$tripId/allocate',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final String memberId in trip.memberIds)
                        _MemberRow(
                          tripId: tripId,
                          member: store.userById(memberId),
                          allocations: allocs
                              .where(
                                (Allocation a) =>
                                    a.toUserId == memberId &&
                                    a.fromUserId == trip.leaderId,
                              )
                              .toList(),
                          sources: sources,
                          currency: trip.currency,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RemainingPill extends StatelessWidget {
  const _RemainingPill({required this.remaining});
  final Money remaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandBrown,
        borderRadius: const BorderRadius.all(AppRadii.button),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'CURRENT TRIP BALANCE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.cream.withValues(alpha: 0.85),
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            remaining.format(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.cream,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'unallocated — held by you (Leader)',
            style: TextStyle(
              color: AppColors.cream.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _PerSourceBalances extends StatelessWidget {
  const _PerSourceBalances({required this.sources, required this.available});

  final List<Source> sources;
  final Map<String, Money> available;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final Source s in sources)
          Container(
            width: 150,
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
                  s.name,
                  maxLines: 2,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  (available[s.id] ?? Money.zero('SAR')).format(),
                  style: const TextStyle(
                    color: AppColors.brandBrown,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'available',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.tripId,
    required this.member,
    required this.allocations,
    required this.sources,
    required this.currency,
  });

  final String tripId;
  final User member;
  final List<Allocation> allocations;
  final List<Source> sources;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final Money total = allocations.fold<Money>(
      Money.zero(currency),
      (Money a, Allocation b) => a + b.amount,
    );
    final Map<String, Money> bySource = <String, Money>{};
    for (final Allocation a in allocations) {
      bySource.update(
        a.sourceId,
        (Money v) => v + a.amount,
        ifAbsent: () => a.amount,
      );
    }
    final int pending = allocations
        .where((Allocation a) => a.status == AllocationStatus.pending)
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.brandBrown,
                child: Text(
                  _initials(member.displayName),
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      member.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (pending > 0)
                      Text(
                        '$pending pending acceptance',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                total.format(),
                style: const TextStyle(
                  color: AppColors.brandBrown,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Add allocation',
                onPressed: () => _openModal(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final Source s in sources)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: Text(
                      s.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    (bySource[s.id] ?? Money.zero(currency)).format(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          if (allocations.length > 1) ...<Widget>[
            const Divider(height: AppSpacing.lg),
            Text(
              'HISTORY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            for (final Allocation a in allocations)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _statusColor(a.status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        DateFormat.yMMMd().format(a.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      a.amount.format(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(AllocationStatus s) {
    switch (s) {
      case AllocationStatus.accepted:
        return AppColors.success;
      case AllocationStatus.pending:
        return AppColors.warning;
      case AllocationStatus.declined:
        return AppColors.outflow;
    }
  }

  Future<void> _openModal(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext _) =>
          ManageMemberFundsModal(tripId: tripId, memberId: member.id),
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
