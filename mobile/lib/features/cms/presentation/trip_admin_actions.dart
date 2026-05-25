import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import 'widgets/cms_theme.dart';
import '../../../core/money/money.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/data/funds_repository.dart';
import '../../funds/domain/funding.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import 'edit_trip_dialog.dart';

/// Action bar on the CMS trip-detail pane. Visible to Admin only;
/// Super Admin sees the trip read-only.
class TripAdminActions extends ConsumerWidget {
  const TripAdminActions({super.key, required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    if (me?.role != UserRole.admin) return const SizedBox.shrink();
    final bool isActive = trip.status == TripStatus.active;
    if (!isActive) return const SizedBox.shrink();

    // The global OutlinedButton theme stretches every button to full width
    // — fine on the phone screens, but on the desktop CMS we want a compact
    // toolbar. Override with intrinsic-sized buttons.
    final ButtonStyle compact = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      foregroundColor: CmsColors.brandBrown,
      side: const BorderSide(color: CmsColors.brandBrown),
    );
    final ButtonStyle compactDanger = compact.copyWith(
      foregroundColor: const WidgetStatePropertyAll<Color>(CmsColors.outflow),
      side: const WidgetStatePropertyAll<BorderSide>(
        BorderSide(color: CmsColors.outflow),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          OutlinedButton.icon(
            style: compact,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('EDIT TRIP'),
            onPressed: () => _openEditTrip(context, ref),
          ),
          OutlinedButton.icon(
            style: compact,
            icon: const Icon(Icons.add_card_outlined, size: 16),
            label: const Text('ASSIGN ADDITIONAL FUNDS'),
            onPressed: () => _openAssignFunds(context, ref),
          ),
          OutlinedButton.icon(
            style: compactDanger,
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('CLOSE TRIP'),
            onPressed: () => _confirmCloseTrip(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCloseTrip(BuildContext context, WidgetRef ref) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Close trip?'),
        content: Text(
          'This locks "${trip.name}" — members can no longer add or edit '
          'expenses. A TRIP_CLOSED notification is sent to all participants. '
          'This cannot be undone in the demo.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: CmsColors.outflow),
            child: const Text('CLOSE TRIP'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(tripRepositoryProvider).closeTrip(trip.id);
      ref.invalidate(tripDetailProvider(trip.id));
      ref.invalidate(activeTripsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Trip "${trip.name}" closed.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to close: $e')));
    }
  }

  Future<void> _openAssignFunds(BuildContext context, WidgetRef ref) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext _) => _AssignFundsDialog(trip: trip),
    );
  }

  Future<void> _openEditTrip(BuildContext context, WidgetRef ref) async {
    final Object? result = await showDialog<Object>(
      context: context,
      builder: (BuildContext _) => EditTripDialog(trip: trip),
    );
    if (!context.mounted) return;
    if (result == 'deleted') {
      // Trip no longer exists — bounce the admin back to the trip list so
      // the now-stale detail view doesn't render an error.
      GoRouter.of(context).go('/cms');
      return;
    }
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Trip "${trip.name}" updated.')),
      );
    }
  }
}

class _AssignFundsDialog extends ConsumerStatefulWidget {
  const _AssignFundsDialog({required this.trip});
  final Trip trip;

  @override
  ConsumerState<_AssignFundsDialog> createState() => _AssignFundsDialogState();
}

class _AssignFundsDialogState extends ConsumerState<_AssignFundsDialog> {
  final Map<String, TextEditingController> _ctrls =
      <String, TextEditingController>{};
  bool _saving = false;

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
    final AsyncValue<List<Source>> sourcesAsync = ref.watch(sourcesProvider);
    final DemoStore store = ref.read(demoStoreProvider);
    final String leaderName = store.userById(widget.trip.leaderId).displayName;

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.add_card_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Assign Additional Funds',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Top up the source pool for "${widget.trip.name}". Funds are credited to $leaderName (Leader) and added to TOTAL TRIP BUDGET. Members are unaffected — Leader can sub-allocate from Manage Funds.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CmsColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              sourcesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (Object e, _) => Text('Error: $e'),
                data: (List<Source> sources) => Column(
                  children: <Widget>[
                    for (final Source s in sources)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    s.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    s.nameAr,
                                    style: Theme.of(context).textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: CmsColors.textSecondary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _ctrl(s.id),
                                onChanged: (_) => setState(() {}),
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
                                  prefixText: '${widget.trip.currency}  ',
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
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'NEW INFLOW',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: CmsColors.textSecondary,
                        ),
                      ),
                      Text(
                        _grandTotal(widget.trip.currency).format(),
                        style: const TextStyle(
                          color: CmsColors.brandBrown,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Compact styles override the global theme's
                  // Size(double.infinity, 52) minimumSize — without these,
                  // CANCEL claims full width and pushes ASSIGN off the right
                  // edge of the dialog footer.
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: CmsColors.brandBrown,
                      foregroundColor: CmsColors.cream,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: CmsColors.cream,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: const Text(
                      'ASSIGN',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    onPressed:
                        _saving || _grandTotal(widget.trip.currency).isZero
                        ? null
                        : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final DemoStore store = ref.read(demoStoreProvider);
      Money inflow = Money.zero(widget.trip.currency);
      final List<AllocationDraftRow> rows = <AllocationDraftRow>[];

      _ctrls.forEach((String sourceId, TextEditingController c) {
        final String cleaned = c.text.replaceAll(',', '').trim();
        if (cleaned.isEmpty) return;
        final double major = double.tryParse(cleaned) ?? 0;
        if (major <= 0) return;
        final Money amount = Money.fromMajor(major, widget.trip.currency);
        inflow += amount;
        rows.add(AllocationDraftRow(
          toUserId: widget.trip.leaderId,
          sourceId: sourceId,
          amount: amount,
        ));
      });

      if (rows.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      // POST /api/v1/trips/{id}/allocations (admin pool → leader), one
      // bulk call. The repo's createMany also covers fake mode by writing
      // straight to DemoStore.
      final AllocationRepository repo =
          ref.read(allocationRepositoryProvider);
      final List<Allocation> created = await repo.createMany(
        tripId: widget.trip.id,
        rows: rows,
        idempotencyKey:
            'assign-funds-${widget.trip.id}-${DateTime.now().microsecondsSinceEpoch}',
      );
      store.allocations.addAll(created);

      store.emit(DemoStoreEvent.allocationsChanged);
      store.emit(DemoStoreEvent.tripsChanged);

      ref.invalidate(tripDetailProvider(widget.trip.id));
      ref.invalidate(tripBalancesProvider);
      ref.invalidate(tripAllocationsProvider(widget.trip.id));
      ref.invalidate(leaderAvailableBySourceProvider(widget.trip.id));

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Topped up ${inflow.format()} on ${widget.trip.name}.'),
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
