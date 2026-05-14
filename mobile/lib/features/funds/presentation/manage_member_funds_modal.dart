import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/funds_providers.dart';
import '../domain/funding.dart';

/// Screen-inventory #21 — Per-member fund modal. Shows the member's current
/// accepted-allocation total + per-source breakdown, then lets the Leader
/// stack on another allocation slice (append-only model per CLAUDE.md §5).
class ManageMemberFundsModal extends ConsumerStatefulWidget {
  const ManageMemberFundsModal({
    super.key,
    required this.tripId,
    required this.memberId,
  });

  final String tripId;
  final String memberId;

  @override
  ConsumerState<ManageMemberFundsModal> createState() =>
      _ManageMemberFundsModalState();
}

class _ManageMemberFundsModalState
    extends ConsumerState<ManageMemberFundsModal> {
  final Map<String, TextEditingController> _ctrls =
      <String, TextEditingController>{};
  bool _saving = false;
  static const Uuid _uuid = Uuid();

  TextEditingController _ctrl(String sourceId) =>
      _ctrls.putIfAbsent(sourceId, () => TextEditingController());

  @override
  void dispose() {
    for (final TextEditingController c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Trip> tripAsync = ref.watch(
      tripDetailProvider(widget.tripId),
    );
    final AsyncValue<List<Allocation>> allocsAsync = ref.watch(
      tripAllocationsProvider(widget.tripId),
    );
    final AsyncValue<List<Source>> sourcesAsync = ref.watch(sourcesProvider);
    final AsyncValue<Map<String, Money>> availableAsync = ref.watch(
      leaderAvailableBySourceProvider(widget.tripId),
    );
    final DemoStore store = ref.read(demoStoreProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (BuildContext context, ScrollController scroll) {
        return tripAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, _) => Center(child: Text('Error: $e')),
          data: (Trip trip) {
            final String currency = trip.currency;
            return allocsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('Error: $e')),
              data: (List<Allocation> allocs) => sourcesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Center(child: Text('Error: $e')),
                data: (List<Source> sources) => availableAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (Object e, _) => Center(child: Text('Error: $e')),
                  data: (Map<String, Money> avail) {
                    final List<Allocation> mine = allocs
                        .where(
                          (Allocation a) =>
                              a.toUserId == widget.memberId &&
                              a.fromUserId == trip.leaderId,
                        )
                        .toList();
                    final Money total = mine.fold<Money>(
                      Money.zero(currency),
                      (Money a, Allocation b) => a + b.amount,
                    );
                    final Map<String, Money> bySource = <String, Money>{};
                    for (final Allocation a in mine) {
                      bySource.update(
                        a.sourceId,
                        (Money v) => v + a.amount,
                        ifAbsent: () => a.amount,
                      );
                    }
                    final String memberName = store
                        .userById(widget.memberId)
                        .displayName;

                    return Column(
                      children: <Widget>[
                        const _GrabHandle(),
                        _Header(
                          name: memberName,
                          onClose: () => Navigator.of(context).pop(),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView(
                            controller: scroll,
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            children: <Widget>[
                              Center(
                                child: _CurrentTotalBubble(amount: total),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _Section(label: 'BREAKDOWN'),
                              const SizedBox(height: AppSpacing.sm),
                              for (final Source s in sources)
                                _BreakdownRow(
                                  source: s,
                                  amount:
                                      bySource[s.id] ?? Money.zero(currency),
                                ),
                              const SizedBox(height: AppSpacing.lg),
                              _Section(label: 'ADD FUNDS'),
                              const SizedBox(height: AppSpacing.sm),
                              for (final Source s in sources)
                                _AddRow(
                                  source: s,
                                  controller: _ctrl(s.id),
                                  available:
                                      avail[s.id] ?? Money.zero(currency),
                                  currency: currency,
                                  onChange: () => setState(() {}),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: SafeArea(
                            top: false,
                            child: FilledButton.icon(
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.cream,
                                      ),
                                    )
                                  : const Icon(Icons.add),
                              label: Text(
                                'ADD ${_grandTotal(currency).format()}',
                              ),
                              onPressed: _saving || _grandTotal(currency).isZero
                                  ? null
                                  : () => _submit(trip),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Money _grandTotal(String currency) {
    Money total = Money.zero(currency);
    for (final TextEditingController c in _ctrls.values) {
      final String cleaned = c.text.replaceAll(',', '').trim();
      if (cleaned.isEmpty) continue;
      final double major = double.tryParse(cleaned) ?? 0;
      if (major > 0) total += Money.fromMajor(major, currency);
    }
    return total;
  }

  Future<void> _submit(Trip trip) async {
    final List<AllocationDraftRow> rows = <AllocationDraftRow>[];
    _ctrls.forEach((String sourceId, TextEditingController c) {
      final String cleaned = c.text.replaceAll(',', '').trim();
      if (cleaned.isEmpty) return;
      final double major = double.tryParse(cleaned) ?? 0;
      if (major <= 0) return;
      rows.add(
        AllocationDraftRow(
          toUserId: widget.memberId,
          sourceId: sourceId,
          amount: Money.fromMajor(major, trip.currency),
        ),
      );
    });
    if (rows.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(allocationRepositoryProvider)
          .createMany(
            tripId: trip.id,
            rows: rows,
            idempotencyKey: _uuid.v4(),
          );
      ref.invalidate(tripAllocationsProvider(trip.id));
      ref.invalidate(leaderAvailableBySourceProvider(trip.id));
      ref.invalidate(tripBalancesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sent ${rows.length} allocation${rows.length == 1 ? '' : 's'} for approval.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.onClose});
  final String name;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Text(name, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CurrentTotalBubble extends StatelessWidget {
  const _CurrentTotalBubble({required this.amount});
  final Money amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.goldOlive.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.goldOlive, width: 4),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'CURRENT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                amount.format(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.brandBrown,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.source, required this.amount});
  final Source source;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(source.name)),
          Text(
            amount.format(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.source,
    required this.controller,
    required this.available,
    required this.currency,
    required this.onChange,
  });

  final Source source;
  final TextEditingController controller;
  final Money available;
  final String currency;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  source.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Avail. ${available.format()}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => onChange(),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                prefixText: '$currency  ',
                hintText: '0',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
