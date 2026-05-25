import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/funds_providers.dart';
import '../data/funds_repository.dart';
import '../domain/funding.dart';

/// Banner shown at the top of the trip dashboard whenever the current user
/// has pending allocations OR transfers on this trip. Explains why their
/// balance is zero (incoming funds need to be accepted to preserve the audit
/// chain) and gives them a one-tap path to accept all of them.
class PendingAllocationsBanner extends ConsumerWidget {
  const PendingAllocationsBanner({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final AsyncValue<List<Allocation>> allocsAsync =
        ref.watch(tripAllocationsProvider(tripId));
    final AsyncValue<List<Transfer>> transfersAsync =
        ref.watch(tripTransfersProvider(tripId));

    if (me == null) return const SizedBox.shrink();
    final List<Allocation>? allAllocs = allocsAsync.valueOrNull;
    final List<Transfer>? allTransfers = transfersAsync.valueOrNull;
    if (allAllocs == null && allTransfers == null) {
      return const SizedBox.shrink();
    }

    final List<Allocation> pendingAllocs = (allAllocs ?? const <Allocation>[])
        .where((Allocation a) =>
            a.toUserId == me.id && a.status == AllocationStatus.pending)
        .toList();
    final List<Transfer> pendingTransfers =
        (allTransfers ?? const <Transfer>[])
            .where((Transfer t) =>
                t.toUserId == me.id && t.status == AllocationStatus.pending)
            .toList();
    final int totalCount = pendingAllocs.length + pendingTransfers.length;
    if (totalCount == 0) return const SizedBox.shrink();

    // Currency from whichever pending item exists; both flows in a single
    // trip share the trip's currency so any pick is fine.
    final String currency = pendingAllocs.isNotEmpty
        ? pendingAllocs.first.amount.currencyCode
        : pendingTransfers.first.amount.currencyCode;
    Money total = Money.zero(currency);
    for (final Allocation a in pendingAllocs) {
      total += a.amount;
    }
    for (final Transfer t in pendingTransfers) {
      total += t.amount;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: Material(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(AppRadii.card),
        child: InkWell(
          borderRadius: const BorderRadius.all(AppRadii.card),
          onTap: () => _open(
            context,
            ref,
            pendingAllocs: pendingAllocs,
            pendingTransfers: pendingTransfers,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(AppRadii.card),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_outlined,
                    color: AppColors.warning,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '$totalCount pending '
                        '${totalCount == 1 ? "fund" : "funds"}'
                        ' · ${total.format()}',
                        style: const TextStyle(
                          color: AppColors.brandBrownDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _previewLine(ref, pendingAllocs, pendingTransfers),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.brandBrown,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _previewLine(
    WidgetRef ref,
    List<Allocation> allocs,
    List<Transfer> transfers,
  ) {
    final DemoStore store = ref.read(demoStoreProvider);
    final List<String> parts = <String>[];
    for (final Allocation a in allocs) {
      String src;
      try {
        src = store.sourceById(a.sourceId).name;
      } catch (_) {
        src = 'Source';
      }
      parts.add('$src ${a.amount.format()}');
    }
    for (final Transfer t in transfers) {
      String from;
      try {
        from = store.userById(t.fromUserId).displayName.split(' ').first;
      } catch (_) {
        from = 'Peer';
      }
      parts.add('from $from ${t.amount.format()}');
    }
    return parts.join(' · ');
  }

  void _open(
    BuildContext context,
    WidgetRef ref, {
    required List<Allocation> pendingAllocs,
    required List<Transfer> pendingTransfers,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (BuildContext _) => _ReviewSheet(
        tripId: tripId,
        pendingAllocs: pendingAllocs,
        pendingTransfers: pendingTransfers,
      ),
    );
  }
}

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({
    required this.tripId,
    required this.pendingAllocs,
    required this.pendingTransfers,
  });
  final String tripId;
  final List<Allocation> pendingAllocs;
  final List<Transfer> pendingTransfers;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final DemoStore store = ref.read(demoStoreProvider);
    final String currency = widget.pendingAllocs.isNotEmpty
        ? widget.pendingAllocs.first.amount.currencyCode
        : widget.pendingTransfers.first.amount.currencyCode;
    Money total = Money.zero(currency);
    for (final Allocation a in widget.pendingAllocs) {
      total += a.amount;
    }
    for (final Transfer t in widget.pendingTransfers) {
      total += t.amount;
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Funds awaiting your approval',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Accepting adds the funds to your balance. Each acceptance is '
              'recorded in the audit log.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final Allocation a in widget.pendingAllocs)
              _IncomingRow(
                kind: 'Allocation',
                source: _safeSource(store, a.sourceId),
                from: a.fromUserId == null
                    ? 'Admin'
                    : _safeUser(store, a.fromUserId!),
                amount: a.amount,
                onDecline: _busy
                    ? null
                    : () => _respondAllocs(
                          <Allocation>[a],
                          AllocationStatus.declined,
                        ),
              ),
            for (final Transfer t in widget.pendingTransfers)
              _IncomingRow(
                kind: 'Transfer',
                source: _safeSource(store, t.sourceId),
                from: _safeUser(store, t.fromUserId),
                amount: t.amount,
                onDecline: _busy
                    ? null
                    : () => _respondTransfers(
                          <Transfer>[t],
                          AllocationStatus.declined,
                        ),
              ),
            const Divider(height: AppSpacing.lg * 2),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'TOTAL',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                Text(
                  total.format(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBrown,
                  ),
                ),
              ],
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.outflow.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.all(AppRadii.chip),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.outflow),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                _busy ? 'ACCEPTING…' : 'ACCEPT ALL',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              onPressed: _busy ? null : _acceptAll,
            ),
          ],
        ),
      ),
    );
  }

  String _safeSource(DemoStore store, String id) {
    try {
      return store.sourceById(id).name;
    } catch (_) {
      return 'Source';
    }
  }

  String _safeUser(DemoStore store, String id) {
    try {
      return store.userById(id).displayName;
    } catch (_) {
      return 'Sender';
    }
  }

  Future<void> _acceptAll() async {
    await _respondAllocs(widget.pendingAllocs, AllocationStatus.accepted);
    if (mounted && _error == null) {
      await _respondTransfers(widget.pendingTransfers, AllocationStatus.accepted);
    }
  }

  Future<void> _respondAllocs(
    List<Allocation> targets,
    AllocationStatus response,
  ) async {
    if (targets.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AllocationRepository repo =
          ref.read(allocationRepositoryProvider);
      for (final Allocation a in targets) {
        await repo.respond(allocationId: a.id, response: response);
      }
      _refreshProviders();
      if (!mounted) return;
      if (widget.pendingTransfers.isEmpty || response == AllocationStatus.declined) {
        Navigator.of(context).pop();
      } else {
        setState(() => _busy = false);
      }
    } catch (e) {
      setState(() {
        _error = 'Could not save allocation response: $e';
        _busy = false;
      });
    }
  }

  Future<void> _respondTransfers(
    List<Transfer> targets,
    AllocationStatus response,
  ) async {
    if (targets.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final TransferRepository repo =
          ref.read(transferRepositoryProvider);
      for (final Transfer t in targets) {
        await repo.respond(transferId: t.id, response: response);
      }
      _refreshProviders();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'Could not save transfer response: $e';
        _busy = false;
      });
    }
  }

  void _refreshProviders() {
    ref.invalidate(tripAllocationsProvider(widget.tripId));
    ref.invalidate(tripTransfersProvider(widget.tripId));
    ref.invalidate(tripBalancesProvider(
        (tripId: widget.tripId, scope: BalanceScope.me)));
    ref.invalidate(tripBalancesProvider(
        (tripId: widget.tripId, scope: BalanceScope.trip)));
    ref.read(demoStoreProvider).emit(DemoStoreEvent.allocationsChanged);
  }
}

class _IncomingRow extends StatelessWidget {
  const _IncomingRow({
    required this.kind,
    required this.source,
    required this.from,
    required this.amount,
    required this.onDecline,
  });

  /// "Allocation" (from a leader/admin) or "Transfer" (peer-to-peer).
  final String kind;
  final String source;
  final String from;
  final Money amount;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final bool isTransfer = kind == 'Transfer';
    final Color kindColor =
        isTransfer ? AppColors.brandBrown : AppColors.goldOlive;
    // Two-row card layout — the previous single-Row arrangement kept
    // overflowing every time a source name, person name, or amount got
    // longer than the phone viewport's available width. Splitting top
    // (icon + name + kind) from bottom (amount + decline) makes the
    // sheet robust regardless of string length on any phone size.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: const BorderRadius.all(AppRadii.card),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Top row — icon + name/from stack + kind chip on the right
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: const BorderRadius.all(AppRadii.chip),
                  ),
                  child: Icon(
                    isTransfer
                        ? Icons.swap_horiz
                        : Icons.account_balance_wallet_outlined,
                    color: AppColors.brandBrown,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'From $from',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: kindColor.withValues(alpha: 0.18),
                    borderRadius: const BorderRadius.all(AppRadii.chip),
                  ),
                  child: Text(
                    kind.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: kindColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Bottom row — amount on the left, decline on the right.
            // Amount is in a Flexible+FittedBox so even an extreme amount
            // string scales rather than overflowing.
            Row(
              children: <Widget>[
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      amount.format(),
                      maxLines: 1,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandBrown,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onDecline,
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('DECLINE'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.outflow,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
