import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/pdd_primitives.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expenses_providers.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';

/// Add Expense per the handoff (`screens-actions.jsx → AddExpenseScreen`).
///
/// Layout: balance preview banner (turns red on exceed) → 6-col category
/// grid → vendor field → qty/per-unit/total row → source picker (split
/// buttons) → photo dashed button → note textarea → "Record expense".
class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final TextEditingController _vendorCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _unitCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  static const Uuid _uuid = Uuid();

  String? _sourceId;
  String? _categoryCode = 'FOOD';
  DateTime _occurredAt = DateTime.now();
  bool _submitting = false;
  XFile? _receiptFile;

  @override
  void initState() {
    super.initState();
    // Live total recompute as qty/unit change.
    _qtyCtrl.addListener(() => setState(() {}));
    _unitCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _vendorCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Trip> tripAsync = ref.watch(
      tripDetailProvider(widget.tripId),
    );
    final AsyncValue<List<Source>> sourcesAsync = ref.watch(sourcesProvider);
    final AsyncValue<List<ExpenseCategory>> categoriesAsync = ref.watch(
      categoriesProvider,
    );
    final AsyncValue<TripBalances> balancesAsync = ref.watch(
      tripBalancesProvider(
        (tripId: widget.tripId, scope: BalanceScope.me),
      ),
    );
    final User? me = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: tripAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, _) => Center(child: Text('Error: $e')),
          data: (Trip trip) => Column(
            children: <Widget>[
              PddTopBar(
                user: me,
                leadingBack: true,
                onBack: () =>
                    context.go('/m/trips/${widget.tripId}/dashboard'),
                title: 'New expense',
                subtitle: trip.name,
              ),
              const SyncStatusBanner(),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                      _BalancePreview(
                        trip: trip,
                        total: _total(trip.currency),
                        balancesAsync: balancesAsync,
                      ),
                      const SizedBox(height: 12),
                      _SectionLabel(label: 'Category'),
                      const SizedBox(height: 4),
                      categoriesAsync.when(
                        loading: () => const _CategoryGridPlaceholder(),
                        error: (Object e, _) => Text('Error: $e'),
                        data: (List<ExpenseCategory> cats) => _CategoryGrid(
                          categories: cats,
                          selected: _categoryCode,
                          onPick: (String code) =>
                              setState(() => _categoryCode = code),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Field(
                        label: 'Vendor',
                        child: TextField(
                          controller: _vendorCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Where did you spend?',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: _Field(
                              label: 'Qty',
                              child: TextField(
                                controller: _qtyCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Field(
                              label: 'Per unit',
                              child: TextField(
                                controller: _unitCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                                decoration: const InputDecoration(
                                  hintText: '0',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _TotalReadOnly(
                              total: _total(trip.currency),
                              currency: trip.currency,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _SectionLabel(label: 'Deduct from source'),
                      const SizedBox(height: 6),
                      sourcesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (Object e, _) => Text('Error: $e'),
                        data: (List<Source> sources) =>
                            _SourceSplit(
                          sources: sources,
                          selected: _sourceId,
                          onPick: (String id) =>
                              setState(() => _sourceId = id),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _PhotoButton(
                        file: _receiptFile,
                        onPick: _pickReceipt,
                        onClear: () => setState(() => _receiptFile = null),
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        label: 'Note',
                        child: TextField(
                          controller: _noteCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'What was this for? (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ),
                ),
              ),
              ),
              // Sticky submit — outside the scrollable so it's always
              // visible at the bottom of the phone viewport, no matter how
              // long the form gets.
              _StickyActionBar(
                child: _SubmitButton(
                  enabled: !_submitting &&
                      _vendorCtrl.text.trim().isNotEmpty &&
                      _unitCtrl.text.trim().isNotEmpty,
                  submitting: _submitting,
                  onTap: () => _submit(trip),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Money _total(String currency) {
    final double qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final double unit =
        double.tryParse(_unitCtrl.text.replaceAll(',', '').trim()) ?? 0;
    if (qty <= 0 || unit <= 0) return Money.zero(currency);
    return Money.fromMajor(qty * unit, currency);
  }

  Future<void> _submit(Trip trip) async {
    final Money amount = _total(trip.currency);
    if (amount.isZero) {
      showPddToast(context, 'Amount must be greater than 0');
      return;
    }
    if (_sourceId == null) {
      showPddToast(context, 'Please select a source');
      return;
    }
    if (_categoryCode == null) {
      showPddToast(context, 'Please select a category');
      return;
    }

    setState(() => _submitting = true);
    try {
      final String userId =
          ref.read(currentUserProvider).valueOrNull?.id ?? '';
      final int qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
      final String details = <String>[
        _vendorCtrl.text.trim(),
        if (_noteCtrl.text.trim().isNotEmpty) _noteCtrl.text.trim(),
      ].join(' — ');

      Expense e = await ref.read(expenseRepositoryProvider).create(
            clientUuid: _uuid.v4(),
            tripId: trip.id,
            userId: userId,
            sourceId: _sourceId!,
            categoryCode: _categoryCode!,
            amount: amount,
            details: details,
            occurredAt: _occurredAt,
            quantity: qty,
            receiptObjectKey: null,
            idempotencyKey: _uuid.v4(),
          );

      if (_receiptFile != null) {
        final Uint8List bytes = await _receiptFile!.readAsBytes();
        final String objectKey =
            await ref.read(expenseRepositoryProvider).uploadReceipt(
                  e.id,
                  ReceiptUpload(
                    localPath: _receiptFile!.path,
                    filename: _receiptFile!.name,
                    bytes: bytes,
                    mime: _mimeFor(_receiptFile!.name),
                    sha256: '',
                    byteSize: bytes.length,
                  ),
                );
        e = Expense(
          id: e.id,
          tripId: e.tripId,
          userId: e.userId,
          sourceId: e.sourceId,
          categoryCode: e.categoryCode,
          amount: e.amount,
          quantity: e.quantity,
          details: e.details,
          occurredAt: e.occurredAt,
          createdAt: e.createdAt,
          updatedAt: e.updatedAt,
          deletedAt: e.deletedAt,
          receiptObjectKey: objectKey,
        );
      }

      ref.invalidate(myExpensesProvider(trip.id));
      ref.invalidate(tripExpensesProvider(trip.id));
      ref.invalidate(
        tripBalancesProvider((tripId: trip.id, scope: BalanceScope.me)),
      );
      if (!mounted) return;
      showPddToast(
        context,
        'Expense recorded — ${_fmt(amount)} ${trip.currency}',
      );
      context.go('/m/trips/${trip.id}/dashboard');
    } catch (err) {
      if (mounted) showPddToast(context, 'Submission failed: $err');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickReceipt() async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked != null) {
        setState(() => _receiptFile = picked);
      }
    } catch (e) {
      if (mounted) showPddToast(context, 'Receipt pick failed: $e');
    }
  }

  String _mimeFor(String filename) {
    final String lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }
}

// ────────────────────────────────────────────────────────────────────
// Small composables
// ────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.microLabel(),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 4),
          child: Text(label.toUpperCase(), style: AppTypography.microLabel()),
        ),
        child,
      ],
    );
  }
}

class _BalancePreview extends StatelessWidget {
  const _BalancePreview({
    required this.trip,
    required this.total,
    required this.balancesAsync,
  });
  final Trip trip;
  final Money total;
  final AsyncValue<TripBalances> balancesAsync;

  @override
  Widget build(BuildContext context) {
    return balancesAsync.maybeWhen(
      data: (TripBalances b) {
        final Money balance = b.totalBalance;
        final Money after = balance - total;
        final bool exceed = after.amountMinor < 0;
        final Color bg = exceed ? AppColors.redSoft : AppColors.brandSoft;
        final Color fg = exceed ? AppColors.red : AppColors.brand;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: <Widget>[
              if (exceed) ...<Widget>[
                Icon(Icons.warning_amber_outlined,
                    color: fg, size: 16),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  exceed
                      ? 'Exceeds balance'
                      : 'Balance after expense',
                  style: AppTypography.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
              Text(
                '${_fmt(after)} ${trip.currency}',
                style: AppTypography.geistMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox(height: 0),
    );
  }
}

class _CategoryGridPlaceholder extends StatelessWidget {
  const _CategoryGridPlaceholder();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(aspectRatio: 6, child: const LinearProgressIndicator());
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.selected,
    required this.onPick,
  });
  final List<ExpenseCategory> categories;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1,
      children: <Widget>[
        for (final ExpenseCategory c in categories)
          _CategoryCell(
            code: c.code,
            label: c.nameEn,
            selected: selected == c.code,
            onTap: () => onPick(c.code),
          ),
      ],
    );
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.forCategory(code);
    final Color bg = AppColors.forCategoryBg(code);
    return Material(
      color: selected ? bg : AppColors.bgCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : AppColors.line,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                _iconForCategory(code),
                size: 18,
                color: selected ? color : AppColors.ink2,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppTypography.geist(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: selected ? color : AppColors.ink2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalReadOnly extends StatelessWidget {
  const _TotalReadOnly({required this.total, required this.currency});
  final Money total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return _Field(
      label: 'Total',
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.bgInset,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        alignment: Alignment.centerLeft,
        child: RichText(
          text: TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: _fmt(total),
                style: AppTypography.geistMono(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink1,
                ),
              ),
              TextSpan(
                text: ' $currency',
                style: AppTypography.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
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

class _SourceSplit extends StatelessWidget {
  const _SourceSplit({
    required this.sources,
    required this.selected,
    required this.onPick,
  });
  final List<Source> sources;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < sources.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _SourceTile(
              source: sources[i],
              selected: selected == sources[i].id,
              onTap: () => onPick(sources[i].id),
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.selected,
    required this.onTap,
  });
  final Source source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppColors.brand : AppColors.line;
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
            border: Border.all(color: color),
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
                source.name,
                style: AppTypography.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (source.nameAr.isNotEmpty)
                Text(
                  source.nameAr,
                  style: AppTypography.geist(
                    fontSize: 10,
                    color: AppColors.ink3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.file,
    required this.onPick,
    required this.onClear,
  });
  final XFile? file;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.lineStrong,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.photo_camera_outlined,
                color: AppColors.ink2,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Attach invoice photo',
                  style: AppTypography.geist(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink2,
                  ),
                ),
              ),
              Text(
                'Optional',
                style: AppTypography.geist(
                  fontSize: 11,
                  color: AppColors.ink3,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: AppColors.bgInset,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.check_circle,
                    color: AppColors.green, size: 24),
                const SizedBox(height: 6),
                Text(
                  file!.name,
                  style: AppTypography.geist(
                    fontSize: 12,
                    color: AppColors.ink2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: AppColors.bgCard,
            shape: const CircleBorder(),
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClear,
            ),
          ),
        ),
      ],
    );
  }
}

/// Sticky bottom action bar — sits below the scrollable form area so the
/// primary CTA is always visible at the bottom of the phone viewport. The
/// background-card fill blends with the scaffold so it reads as part of the
/// page rather than a tab bar.
class _StickyActionBar extends StatelessWidget {
  const _StickyActionBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.bgApp,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: child,
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.enabled,
    required this.submitting,
    required this.onTap,
  });
  final bool enabled;
  final bool submitting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: FilledButton.icon(
        onPressed: enabled ? onTap : null,
        icon: submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.bgCard,
                ),
              )
            : const Icon(Icons.check, size: 18),
        label: const Text('Record expense'),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────

String _fmt(Money m) =>
    NumberFormat.decimalPattern('en_US').format(m.amountMinor / 100.0);

IconData _iconForCategory(String code) {
  switch (code.toUpperCase()) {
    case 'FOOD':
      return Icons.local_cafe_outlined;
    case 'TRANSPORT':
      return Icons.directions_car_outlined;
    case 'HOTEL':
      return Icons.bed_outlined;
    case 'PHONE':
      return Icons.phone_outlined;
    case 'ENTERTAINMENT':
      return Icons.celebration_outlined;
    case 'TIPS':
      return Icons.card_giftcard_outlined;
    case 'TRAVEL':
      return Icons.flight_takeoff_outlined;
    case 'OTHERS':
    default:
      return Icons.more_horiz_outlined;
  }
}
