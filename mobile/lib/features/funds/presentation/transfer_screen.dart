import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/pdd_primitives.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/funds_providers.dart';

/// Three-step transfer wizard per the handoff
/// (`screens-actions.jsx → TransferScreen`):
///
/// 1. Pick recipient (list of team members)
/// 2. Enter amount + reason (with quick-amount chips)
/// 3. Success — checkmark, "Transfer sent", new balance, Another / Done
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  static const Uuid _uuid = Uuid();
  int _step = 1;

  String? _toUserId;
  String? _sourceId;
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _reasonCtrl = TextEditingController();
  Money? _sentAmount; // captured for the success screen
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
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
      backgroundColor: AppColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: tripAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, _) => Center(child: Text('Error: $e')),
          data: (Trip trip) {
            switch (_step) {
              case 1:
                return _Step1PickRecipient(
                  trip: trip,
                  me: me,
                  store: store,
                  onBack: () => context.go('/m/trips/${trip.id}/dashboard'),
                  onPick: (String id) => setState(() {
                    _toUserId = id;
                    _step = 2;
                  }),
                );
              case 2:
                return _Step2Amount(
                  trip: trip,
                  me: me,
                  recipient: _toUserId == null
                      ? null
                      : _safeUser(store, _toUserId!),
                  amountCtrl: _amountCtrl,
                  reasonCtrl: _reasonCtrl,
                  balancesAsync: balancesAsync,
                  submitting: _submitting,
                  selectedSourceId: _sourceId,
                  onSourcePick: (String id) =>
                      setState(() => _sourceId = id),
                  onBack: () => setState(() => _step = 1),
                  onContinue: () => _submit(trip),
                );
              case 3:
              default:
                return _Step3Success(
                  trip: trip,
                  recipientName: _toUserId == null
                      ? 'Recipient'
                      : _safeUser(store, _toUserId!).displayName,
                  amount: _sentAmount ?? Money.zero(trip.currency),
                  balancesAsync: balancesAsync,
                  onAnother: () => setState(() {
                    _step = 1;
                    _toUserId = null;
                    _sourceId = null;
                    _amountCtrl.clear();
                    _reasonCtrl.clear();
                    _sentAmount = null;
                  }),
                  onDone: () =>
                      context.go('/m/trips/${widget.tripId}/dashboard'),
                );
            }
          },
        ),
      ),
    );
  }

  Future<void> _submit(Trip trip) async {
    if (_toUserId == null) return;
    final double major =
        double.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
    if (major <= 0) {
      showPddToast(context, 'Amount must be greater than 0');
      return;
    }
    if (_sourceId == null) {
      showPddToast(context, 'Pick a source to transfer from');
      return;
    }
    final Money amount = Money.fromMajor(major, trip.currency);
    final User? me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(transferRepositoryProvider).create(
            clientUuid: _uuid.v4(),
            tripId: trip.id,
            fromUserId: me.id,
            toUserId: _toUserId!,
            sourceId: _sourceId!,
            amount: amount,
            note: _reasonCtrl.text.trim().isEmpty
                ? null
                : _reasonCtrl.text.trim(),
            idempotencyKey: _uuid.v4(),
          );
      ref.invalidate(
        tripBalancesProvider((tripId: trip.id, scope: BalanceScope.me)),
      );
      if (!mounted) return;
      setState(() {
        _sentAmount = amount;
        _step = 3;
      });
    } catch (e) {
      if (mounted) showPddToast(context, 'Transfer failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

// ────────────────────────────────────────────────────────────────────
// Step 1 — pick recipient
// ────────────────────────────────────────────────────────────────────

class _Step1PickRecipient extends StatelessWidget {
  const _Step1PickRecipient({
    required this.trip,
    required this.me,
    required this.store,
    required this.onBack,
    required this.onPick,
  });
  final Trip trip;
  final User? me;
  final DemoStore store;
  final VoidCallback onBack;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final List<String> ids = <String>[
      trip.leaderId,
      ...trip.memberIds,
    ].where((String id) => id != me?.id).toSet().toList();

    return Column(
      children: <Widget>[
        PddTopBar(
          user: me,
          leadingBack: true,
          onBack: onBack,
          title: 'Transfer to',
          subtitle: 'Step 1 of 3 · Pick recipient',
        ),
        const SyncStatusBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < ids.length; i++) ...<Widget>[
                      if (i > 0)
                        const Divider(height: 1, color: AppColors.line),
                      _RecipientTile(
                        user: _safeUser(store, ids[i]),
                        isLeader: ids[i] == trip.leaderId,
                        onTap: () => onPick(ids[i]),
                      ),
                    ],
                    if (ids.isEmpty)
                      const PddEmptyState(
                        icon: Icons.group_outlined,
                        title: 'No one else on this trip',
                        body:
                            'Transfers move money between trip members. Ask the admin to add more members.',
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    required this.user,
    required this.isLeader,
    required this.onTap,
  });
  final User user;
  final bool isLeader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: <Widget>[
            PddAvatar(user: user, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isLeader ? 'Trip Leader' : 'Team Member',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.geist(
                      fontSize: 12,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Step 2 — amount + reason
// ────────────────────────────────────────────────────────────────────

class _Step2Amount extends StatelessWidget {
  const _Step2Amount({
    required this.trip,
    required this.me,
    required this.recipient,
    required this.amountCtrl,
    required this.reasonCtrl,
    required this.balancesAsync,
    required this.submitting,
    required this.selectedSourceId,
    required this.onSourcePick,
    required this.onBack,
    required this.onContinue,
  });

  final Trip trip;
  final User? me;
  final User? recipient;
  final TextEditingController amountCtrl;
  final TextEditingController reasonCtrl;
  final AsyncValue<TripBalances> balancesAsync;
  final bool submitting;
  final String? selectedSourceId;
  final ValueChanged<String> onSourcePick;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final double major =
        double.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
    final Money myBalance =
        balancesAsync.maybeWhen(
          data: (TripBalances b) => b.totalBalance,
          orElse: () => Money.zero(trip.currency),
        );
    final List<SourceBalance> sources =
        balancesAsync.maybeWhen(
          data: (TripBalances b) => b.perSource,
          orElse: () => const <SourceBalance>[],
        );
    final bool canContinue =
        major > 0 &&
            selectedSourceId != null &&
            major <= myBalance.amountMinor / 100.0 &&
            !submitting;

    return Column(
      children: <Widget>[
        PddTopBar(
          user: me,
          leadingBack: true,
          onBack: onBack,
          title: 'Amount',
          subtitle:
              'Step 2 of 3 · To ${recipient?.displayName.split(" ").first ?? ""}',
        ),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (recipient != null)
                    _RecipientChip(recipient: recipient!, onChange: onBack),
                const SizedBox(height: 14),
                // Big amount input
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    children: <Widget>[
                      Text('AMOUNT', style: AppTypography.microLabel()),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            trip.currency,
                            style: AppTypography.geist(
                              fontSize: 16,
                              color: AppColors.ink3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          IntrinsicWidth(
                            child: TextField(
                              controller: amountCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              textAlign: TextAlign.center,
                              style: AppTypography.geistMono(
                                fontSize: 44,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink1,
                                letterSpacing: -0.03 * 44,
                              ),
                              decoration: const InputDecoration(
                                hintText: '0',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isCollapsed: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: 'Your balance: ',
                              style: AppTypography.geist(
                                fontSize: 12,
                                color: AppColors.ink3,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '${_fmt(myBalance)} ${trip.currency}',
                              style: AppTypography.geistMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.ink1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: <Widget>[
                          for (final int v in <int>[500, 1000, 5000, 10000])
                            _QuickAmountChip(
                              value: v,
                              onTap: () {
                                amountCtrl.text = v.toString();
                                amountCtrl.selection =
                                    TextSelection.fromPosition(
                                  TextPosition(
                                    offset: amountCtrl.text.length,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text('DEDUCT FROM SOURCE',
                      style: AppTypography.microLabel()),
                ),
                if (sources.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.bgInset,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'No source balances available yet.',
                      style: AppTypography.geist(
                        fontSize: 12,
                        color: AppColors.ink3,
                      ),
                    ),
                  )
                else
                  Row(
                    children: <Widget>[
                      for (int i = 0; i < sources.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _SourceTile(
                            label: sources[i].sourceName,
                            available: sources[i].received - sources[i].spent,
                            currency: trip.currency,
                            selected:
                                selectedSourceId == sources[i].sourceId,
                            onTap: () => onSourcePick(sources[i].sourceId),
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text('REASON', style: AppTypography.microLabel()),
                ),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    hintText: "What's this for?",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Opacity(
                  opacity: canContinue ? 1.0 : 0.4,
                  child: FilledButton.icon(
                    onPressed: canContinue ? onContinue : null,
                    icon: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.bgCard,
                            ),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: const Text('Continue'),
                  ),
                ),
                if (major > 0 && major > myBalance.amountMinor / 100.0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Amount exceeds your balance',
                      textAlign: TextAlign.center,
                      style: AppTypography.geist(
                        fontSize: 12,
                        color: AppColors.red,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ),
        ),
      ],
    );
  }
}

class _RecipientChip extends StatelessWidget {
  const _RecipientChip({required this.recipient, required this.onChange});
  final User recipient;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: <Widget>[
          PddAvatar(user: recipient, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('SENDING TO', style: AppTypography.microLabel()),
                const SizedBox(height: 2),
                Text(
                  recipient.displayName,
                  style: AppTypography.geist(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(
              'Change',
              style: AppTypography.geist(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAmountChip extends StatelessWidget {
  const _QuickAmountChip({required this.value, required this.onTap});
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgElev,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(
            NumberFormat.decimalPattern('en_US').format(value),
            style: AppTypography.geistMono(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.label,
    required this.available,
    required this.currency,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Money available;
  final String currency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandSoft : AppColors.bgCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.line,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selected ? AppColors.brand : AppColors.gold,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTypography.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${_fmt(available)} $currency',
                style: AppTypography.geistMono(
                  fontSize: 10,
                  color: AppColors.ink3,
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
// Step 3 — success
// ────────────────────────────────────────────────────────────────────

class _Step3Success extends StatelessWidget {
  const _Step3Success({
    required this.trip,
    required this.recipientName,
    required this.amount,
    required this.balancesAsync,
    required this.onAnother,
    required this.onDone,
  });

  final Trip trip;
  final String recipientName;
  final Money amount;
  final AsyncValue<TripBalances> balancesAsync;
  final VoidCallback onAnother;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final Money newBalance = balancesAsync.maybeWhen(
      data: (TripBalances b) => b.totalBalance,
      orElse: () => Money.zero(trip.currency),
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 40),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.check,
              size: 42,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Transfer sent',
            style: AppTypography.geist(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.02 * 22,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              '$recipientName will be notified to accept the transfer.',
              textAlign: TextAlign.center,
              style: AppTypography.geist(
                fontSize: 14,
                color: AppColors.ink3,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          RichText(
            text: TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: _fmt(amount),
                  style: AppTypography.geistMono(
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink1,
                    letterSpacing: -0.02 * 36,
                  ),
                ),
                TextSpan(
                  text: '  ${amount.currencyCode}',
                  style: AppTypography.geist(
                    fontSize: 14,
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Awaiting acceptance',
            style: AppTypography.geist(
              fontSize: 12,
              color: AppColors.ink3,
            ),
          ),
          const SizedBox(height: 32),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'New balance',
                      style: AppTypography.geist(
                        fontSize: 13,
                        color: AppColors.ink3,
                      ),
                    ),
                  ),
                  Text(
                    '${_fmt(newBalance)} ${trip.currency}',
                    style: AppTypography.geistMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onAnother,
                    child: const Text('Another'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onDone,
                    child: const Text('Done'),
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

// ────────────────────────────────────────────────────────────────────
// Shared helpers
// ────────────────────────────────────────────────────────────────────

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

String _fmt(Money m) =>
    NumberFormat.decimalPattern('en_US').format(m.amountMinor / 100.0);
