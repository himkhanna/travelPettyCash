import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../auth/domain/user.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/funds_providers.dart';
import '../domain/funding.dart';

/// Screen-inventory #18 + #19 — Leader allocates funds to members per source,
/// with a review step before commit.
class AllocateFundsScreen extends ConsumerStatefulWidget {
  const AllocateFundsScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<AllocateFundsScreen> createState() =>
      _AllocateFundsScreenState();
}

class _AllocateFundsScreenState extends ConsumerState<AllocateFundsScreen> {
  /// memberId -> sourceId -> minor-unit input string (user edits text, we
  /// keep raw strings to preserve focus state in the form).
  final Map<String, Map<String, TextEditingController>> _controllers =
      <String, Map<String, TextEditingController>>{};
  bool _review = false;
  bool _saving = false;
  static const Uuid _uuid = Uuid();

  @override
  void dispose() {
    for (final Map<String, TextEditingController> row in _controllers.values) {
      for (final TextEditingController c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  TextEditingController _ctrl(String memberId, String sourceId) {
    final Map<String, TextEditingController> row = _controllers.putIfAbsent(
      memberId,
      () => <String, TextEditingController>{},
    );
    return row.putIfAbsent(sourceId, () => TextEditingController());
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Trip> tripAsync = ref.watch(
      tripDetailProvider(widget.tripId),
    );
    final AsyncValue<List<Source>> sourcesAsync = ref.watch(sourcesProvider);
    final AsyncValue<Map<String, Money>> availableAsync = ref.watch(
      leaderAvailableBySourceProvider(widget.tripId),
    );
    final DemoStore store = ref.read(demoStoreProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_review ? Icons.arrow_back : Icons.close),
          onPressed: () {
            if (_review) {
              setState(() => _review = false);
            } else {
              context.go('/m/trips/${widget.tripId}/dashboard');
            }
          },
        ),
        title: Text(_review ? 'CONFIRM ALLOCATION' : 'ALLOCATE FUNDS'),
      ),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (Trip trip) => sourcesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, _) => Center(child: Text('Error: $e')),
          data: (List<Source> sources) => availableAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object e, _) => Center(child: Text('Error: $e')),
            data: (Map<String, Money> avail) {
              final List<User> members = trip.memberIds
                  .map((String id) => store.userById(id))
                  .toList();
              return Column(
                children: <Widget>[
                  if (_review) const _ReviewBanner(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _BudgetPill(
                            label: _review
                                ? 'REMAINING AFTER ALLOCATION'
                                : 'CURRENT TRIP BALANCE',
                            amount: _remaining(sources, avail, trip.currency),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: <Widget>[
                              for (final Source s in sources)
                                _SourceSummary(
                                  source: s,
                                  available:
                                      avail[s.id] ??
                                      Money.zero(trip.currency),
                                  reservedInForm: _sumForSource(
                                    s.id,
                                    trip.currency,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            'PER MEMBER',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1.6,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          for (final User m in members)
                            _MemberRow(
                              member: m,
                              sources: sources,
                              currency: trip.currency,
                              review: _review,
                              ctrlFor: (String sid) => _ctrl(m.id, sid),
                              onChange: () => setState(() {}),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _Footer(
                    review: _review,
                    saving: _saving,
                    totalLabel: _grandTotal(trip.currency).format(),
                    onPrimary: _review
                        ? () => _confirm(trip)
                        : _enterReview,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Money _remaining(
    List<Source> sources,
    Map<String, Money> avail,
    String currency,
  ) {
    Money total = Money.zero(currency);
    for (final Source s in sources) {
      final Money sourceAvail = avail[s.id] ?? Money.zero(currency);
      final Money committed = _sumForSource(s.id, currency);
      total += sourceAvail - committed;
    }
    return total;
  }

  Money _sumForSource(String sourceId, String currency) {
    Money total = Money.zero(currency);
    for (final Map<String, TextEditingController> row in _controllers.values) {
      total += _parseMinor(row[sourceId]?.text ?? '', currency);
    }
    return total;
  }

  Money _grandTotal(String currency) {
    Money total = Money.zero(currency);
    for (final Map<String, TextEditingController> row in _controllers.values) {
      for (final TextEditingController c in row.values) {
        total += _parseMinor(c.text, currency);
      }
    }
    return total;
  }

  Money _parseMinor(String text, String currency) {
    final String cleaned = text.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return Money.zero(currency);
    final double major = double.tryParse(cleaned) ?? 0;
    if (major <= 0) return Money.zero(currency);
    return Money.fromMajor(major, currency);
  }

  void _enterReview() {
    if (_grandTotal('SAR').isZero) {
      // Currency doesn't matter here — we just want zero check.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one amount to allocate.')),
      );
      return;
    }
    setState(() => _review = true);
  }

  Future<void> _confirm(Trip trip) async {
    final List<AllocationDraftRow> rows = <AllocationDraftRow>[];
    _controllers.forEach((
      String memberId,
      Map<String, TextEditingController> sources,
    ) {
      sources.forEach((String sourceId, TextEditingController c) {
        final Money amount = _parseMinor(c.text, trip.currency);
        if (!amount.isZero) {
          rows.add(
            AllocationDraftRow(
              toUserId: memberId,
              sourceId: sourceId,
              amount: amount,
            ),
          );
        }
      });
    });

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sent ${rows.length} allocation${rows.length == 1 ? '' : 's'} for approval.',
          ),
        ),
      );
      context.go('/m/trips/${trip.id}/manage-funds');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Allocation failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      color: AppColors.success.withValues(alpha: 0.18),
      child: Text(
        'PLEASE REVIEW AND CONFIRM',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.success,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _BudgetPill extends StatelessWidget {
  const _BudgetPill({required this.label, required this.amount});
  final String label;
  final Money amount;

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
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.cream.withValues(alpha: 0.85),
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            amount.format(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: amount.isNegative ? AppColors.outflow : AppColors.cream,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceSummary extends StatelessWidget {
  const _SourceSummary({
    required this.source,
    required this.available,
    required this.reservedInForm,
  });

  final Source source;
  final Money available;
  final Money reservedInForm;

  @override
  Widget build(BuildContext context) {
    final Money remaining = available - reservedInForm;
    return Container(
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
            source.name,
            maxLines: 2,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            remaining.format(),
            style: TextStyle(
              color: remaining.isNegative
                  ? AppColors.outflow
                  : AppColors.brandBrown,
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
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.sources,
    required this.currency,
    required this.review,
    required this.ctrlFor,
    required this.onChange,
  });

  final User member;
  final List<Source> sources;
  final String currency;
  final bool review;
  final TextEditingController Function(String sourceId) ctrlFor;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    Money rowTotal = Money.zero(currency);
    for (final Source s in sources) {
      final String text = ctrlFor(s.id).text.replaceAll(',', '').trim();
      final double major = double.tryParse(text) ?? 0;
      if (major > 0) rowTotal += Money.fromMajor(major, currency);
    }

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
                child: Text(
                  member.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                rowTotal.format(),
                style: TextStyle(
                  color: rowTotal.isZero
                      ? AppColors.textSecondary
                      : AppColors.brandBrown,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final Source s in sources)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
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
                  Expanded(
                    flex: 3,
                    child: review
                        ? Text(
                            _previewAmount(ctrlFor(s.id), currency),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : TextField(
                            controller: ctrlFor(s.id),
                            onChanged: (_) => onChange(),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
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
            ),
        ],
      ),
    );
  }

  String _previewAmount(TextEditingController c, String currency) {
    final String cleaned = c.text.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return '$currency 0';
    final double major = double.tryParse(cleaned) ?? 0;
    return Money.fromMajor(major, currency).format();
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

class _Footer extends StatelessWidget {
  const _Footer({
    required this.review,
    required this.saving,
    required this.totalLabel,
    required this.onPrimary,
  });

  final bool review;
  final bool saving;
  final String totalLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'TOTAL',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  totalLabel,
                  style: const TextStyle(
                    color: AppColors.brandBrown,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.cream,
                      ),
                    )
                  : Icon(review ? Icons.check : Icons.arrow_forward),
              label: Text(review ? 'CONFIRM' : 'REVIEW'),
              onPressed: saving ? null : onPrimary,
            ),
          ],
        ),
      ),
    );
  }
}
