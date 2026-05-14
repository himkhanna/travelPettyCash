import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/funds_providers.dart';

/// Screen-inventory #12/#13 — Peer-to-peer Transfer + success modal.
///
/// Creates a Transfer (pending) in the demo store, drops a TRANSFER_RECEIVED
/// notification on the recipient. The recipient accepts from the Notifications
/// screen — only then do balances update.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  static const Uuid _uuid = Uuid();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  String? _sourceId;
  String? _toUserId;
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Trip> tripAsync = ref.watch(
      tripDetailProvider(widget.tripId),
    );
    final AsyncValue<TripBalances> balancesAsync = ref.watch(
      tripBalancesProvider((tripId: widget.tripId, scope: BalanceScope.me)),
    );
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final DemoStore store = ref.read(demoStoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('TRANSFER')),
      body: Column(
        children: <Widget>[
          const SyncStatusBanner(),
          Expanded(
            child: tripAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('Error: $e')),
              data: (Trip trip) => SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'TRANSFER FROM',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    balancesAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (Object e, _) => Text('Error: $e'),
                      data: (TripBalances b) => _SourceTiles(
                        balances: b.perSource,
                        selectedId: _sourceId,
                        onPick: (String id) =>
                            setState(() => _sourceId = id),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'TO',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _RecipientPicker(
                      trip: trip,
                      store: store,
                      excludeUserId: me?.id,
                      selected: _toUserId,
                      onPick: (String id) =>
                          setState(() => _toUserId = id),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'AMOUNT',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: AppColors.brandBrown,
                            fontWeight: FontWeight.w700,
                          ),
                      decoration: InputDecoration(
                        prefixText: '${trip.currency}  ',
                        hintText: '0',
                        border: const UnderlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: _submitting ? null : () => _submit(trip),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.cream,
                              ),
                            )
                          : const Text('TRANSFER'),
                    ),
                  ],
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

  Future<void> _submit(Trip trip) async {
    if (_sourceId == null) {
      _toast('Pick a source');
      return;
    }
    if (_toUserId == null) {
      _toast('Pick a recipient');
      return;
    }
    final String raw = _amountCtrl.text.replaceAll(',', '');
    final double major = double.tryParse(raw) ?? 0;
    if (major <= 0) {
      _toast('Amount must be greater than 0');
      return;
    }
    final Money amount = Money.fromMajor(major, trip.currency);
    final User? me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(transferRepositoryProvider)
          .create(
            clientUuid: _uuid.v4(),
            tripId: trip.id,
            fromUserId: me.id,
            toUserId: _toUserId!,
            sourceId: _sourceId!,
            amount: amount,
            note: _noteCtrl.text.trim().isEmpty
                ? null
                : _noteCtrl.text.trim(),
            idempotencyKey: _uuid.v4(),
          );
      ref.invalidate(
        tripBalancesProvider((tripId: trip.id, scope: BalanceScope.me)),
      );
      if (!mounted) return;
      await _showSuccessModal(trip);
    } catch (e) {
      _toast('Transfer failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showSuccessModal(Trip trip) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(AppRadii.card),
        ),
        icon: const Icon(
          Icons.check_circle,
          color: AppColors.success,
          size: 48,
        ),
        title: const Text('TRANSFER SENT', textAlign: TextAlign.center),
        content: const Text(
          'The recipient will see it in their notifications and can accept or decline.',
          textAlign: TextAlign.center,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _resetForm();
            },
            child: const Text('TRANSFER MORE'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/m/trips/${trip.id}/dashboard');
            },
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  void _resetForm() {
    _amountCtrl.clear();
    _noteCtrl.clear();
    setState(() {
      _sourceId = null;
      _toUserId = null;
    });
  }
}

class _SourceTiles extends StatelessWidget {
  const _SourceTiles({
    required this.balances,
    required this.selectedId,
    required this.onPick,
  });

  final List<SourceBalance> balances;
  final String? selectedId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final SourceBalance b in balances)
          _SourceTile(
            balance: b,
            selected: selectedId == b.sourceId,
            onTap: () => onPick(b.sourceId),
          ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.balance,
    required this.selected,
    required this.onTap,
  });

  final SourceBalance balance;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBrown : AppColors.surfaceCard,
          borderRadius: const BorderRadius.all(AppRadii.card),
          border: Border.all(
            color: selected ? AppColors.brandBrown : AppColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              balance.sourceName,
              maxLines: 2,
              style: TextStyle(
                color: selected ? AppColors.cream : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              balance.balance.format(),
              style: TextStyle(
                color: selected ? AppColors.cream : AppColors.brandBrown,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            Text(
              'available',
              style: TextStyle(
                color: selected
                    ? AppColors.cream.withValues(alpha: 0.7)
                    : AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipientPicker extends StatelessWidget {
  const _RecipientPicker({
    required this.trip,
    required this.store,
    required this.excludeUserId,
    required this.selected,
    required this.onPick,
  });

  final Trip trip;
  final DemoStore store;
  final String? excludeUserId;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final List<String> candidateIds = <String>[
      trip.leaderId,
      ...trip.memberIds,
    ].where((String id) => id != excludeUserId).toSet().toList();

    if (candidateIds.isEmpty) {
      return Text(
        'No other participants in this trip.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final String id in candidateIds)
          ChoiceChip(
            avatar: CircleAvatar(
              backgroundColor: id == selected
                  ? AppColors.cream
                  : AppColors.brandBrown,
              child: Text(
                _initials(store.userById(id).displayName),
                style: TextStyle(
                  color: id == selected
                      ? AppColors.brandBrown
                      : AppColors.cream,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            label: Text(store.userById(id).displayName),
            selected: selected == id,
            onSelected: (_) => onPick(id),
            selectedColor: AppColors.brandBrown,
            labelStyle: TextStyle(
              color: selected == id ? AppColors.cream : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
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
