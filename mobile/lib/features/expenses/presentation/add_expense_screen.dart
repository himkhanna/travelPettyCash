import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../auth/application/auth_providers.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expenses_providers.dart';
import '../domain/expense.dart';

/// Screen-inventory #5 / #6 — Add Expense form + success modal.
///
/// Hero demo flow: toggle Demo Controls → Offline mode → fill form → submit.
/// Expense lands in pending_expenses, success modal shows, user can add more
/// or close. Toggle Offline mode off → SyncCoordinator drains queue → expense
/// appears with no "Pending sync" chip.
class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _detailsCtrl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  static const Uuid _uuid = Uuid();

  String? _sourceId;
  String? _categoryCode;
  DateTime _occurredAt = DateTime.now();
  bool _submitting = false;
  XFile? _receiptFile;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _detailsCtrl.dispose();
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/m/trips/${widget.tripId}/dashboard'),
        ),
        title: const Text('ADD EXPENSE'),
      ),
      body: Column(
        children: <Widget>[
          const SyncStatusBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: tripAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Text('Error: $e'),
                data: (Trip trip) => Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _AmountField(
                        controller: _amountCtrl,
                        currency: trip.currency,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: 'SOURCE'),
                      sourcesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (Object e, _) => Text('Error: $e'),
                        data: (List<Source> sources) => _SourcePicker(
                          sources: sources,
                          selected: _sourceId,
                          onPick: (String id) => setState(() => _sourceId = id),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: 'CATEGORY'),
                      categoriesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (Object e, _) => Text('Error: $e'),
                        data: (List<ExpenseCategory> cats) => _CategoryPicker(
                          categories: cats,
                          selected: _categoryCode,
                          onPick: (String code) =>
                              setState(() => _categoryCode = code),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: 'DETAILS'),
                      TextFormField(
                        controller: _detailsCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Describe the expense (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: 'OCCURRED AT'),
                      _DatePickerTile(
                        value: _occurredAt,
                        onChanged: (DateTime d) =>
                            setState(() => _occurredAt = d),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: 'RECEIPT'),
                      _ReceiptPicker(
                        file: _receiptFile,
                        onPick: _pickReceipt,
                        onClear: () => setState(() => _receiptFile = null),
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
                            : const Text('ADD EXPENSE'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(Trip trip) async {
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_sourceId == null) {
      _toast('Please select a source');
      return;
    }
    if (_categoryCode == null) {
      _toast('Please select a category');
      return;
    }
    final Money amount = _parseAmount(trip.currency);
    if (amount.isZero) {
      _toast('Amount must be greater than 0');
      return;
    }

    setState(() => _submitting = true);
    try {
      final String userId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
      final Expense e = await ref
          .read(expenseRepositoryProvider)
          .create(
            clientUuid: _uuid.v4(),
            tripId: trip.id,
            userId: userId,
            sourceId: _sourceId!,
            categoryCode: _categoryCode!,
            amount: amount,
            details: _detailsCtrl.text.trim(),
            occurredAt: _occurredAt,
            // The XFile.path on web is a blob: URL — directly viewable via
            // Image.network in the detail screen. On a real backend this
            // becomes an S3 object key after the receipt upload step.
            receiptObjectKey: _receiptFile?.path,
            idempotencyKey: _uuid.v4(),
          );
      // Refresh dependent providers.
      ref.invalidate(myExpensesProvider(trip.id));
      ref.invalidate(
        tripBalancesProvider((tripId: trip.id, scope: BalanceScope.me)),
      );
      if (!mounted) return;
      await _showSuccessModal(trip, e);
    } catch (err) {
      _toast('Submission failed: $err');
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
      _toast('Receipt pick failed: $e');
    }
  }

  Money _parseAmount(String currency) {
    final String raw = _amountCtrl.text.replaceAll(',', '');
    final double v = double.tryParse(raw) ?? 0;
    return Money.fromMajor(v, currency);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showSuccessModal(Trip trip, Expense e) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppRadii.card),
          ),
          icon: Icon(
            e.pendingSync ? Icons.cloud_off : Icons.check_circle,
            color: e.pendingSync ? AppColors.warning : AppColors.success,
            size: 48,
          ),
          title: Text(
            e.pendingSync ? 'QUEUED OFFLINE' : 'EXPENSE ADDED',
            textAlign: TextAlign.center,
          ),
          content: Text(
            e.pendingSync
                ? 'The expense will sync when you go back online.'
                : '${e.amount.format()} recorded.',
            textAlign: TextAlign.center,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _resetForm();
              },
              child: const Text('ADD MORE'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.go('/m/trips/${trip.id}/dashboard');
              },
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _amountCtrl.clear();
    _detailsCtrl.clear();
    setState(() {
      _sourceId = null;
      _categoryCode = null;
      _occurredAt = DateTime.now();
    });
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.currency});
  final TextEditingController controller;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      style: Theme.of(context).textTheme.displaySmall?.copyWith(
        color: AppColors.brandBrown,
        fontWeight: FontWeight.w700,
      ),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        prefixText: '$currency  ',
        prefixStyle: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
        hintText: '0',
        border: InputBorder.none,
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.divider, width: 2),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.brandBrown, width: 2),
        ),
      ),
    );
  }
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    required this.sources,
    required this.selected,
    required this.onPick,
  });
  final List<Source> sources;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final Source s in sources)
          ChoiceChip(
            label: Text(s.name),
            selected: selected == s.id,
            onSelected: (_) => onPick(s.id),
            selectedColor: AppColors.brandBrown,
            labelStyle: TextStyle(
              color: selected == s.id ? AppColors.cream : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selected,
    required this.onPick,
  });
  final List<ExpenseCategory> categories;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final ExpenseCategory c in categories)
          ChoiceChip(
            avatar: Icon(_iconFor(c.iconKey), size: 16),
            label: Text(c.nameEn),
            selected: selected == c.code,
            onSelected: (_) => onPick(c.code),
            selectedColor: AppColors.forCategory(c.code),
            labelStyle: TextStyle(
              color: selected == c.code ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  IconData _iconFor(String key) {
    switch (key) {
      case 'cutlery':
        return Icons.restaurant;
      case 'car':
        return Icons.directions_car_outlined;
      case 'bed':
        return Icons.hotel_outlined;
      case 'phone':
        return Icons.phone_outlined;
      case 'ticket':
        return Icons.local_activity_outlined;
      case 'coin':
        return Icons.payments_outlined;
      case 'plane':
        return Icons.flight_outlined;
      case 'dots':
        return Icons.more_horiz;
      default:
        return Icons.label_outline;
    }
  }
}

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: const BorderRadius.all(AppRadii.chip),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.calendar_today_outlined, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptPicker extends StatelessWidget {
  const _ReceiptPicker({
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
        borderRadius: const BorderRadius.all(AppRadii.chip),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(AppRadii.chip),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.add_a_photo_outlined,
                color: AppColors.brandBrown,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'ADD RECEIPT',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.brandBrown,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.chip),
        border: Border.all(color: AppColors.goldOlive),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: const BorderRadius.all(AppRadii.chip),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Image.network(
                file!.path,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: AppColors.divider,
                  child: Icon(Icons.image_outlined),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  file!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Tap to replace',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Pick another file',
            onPressed: onPick,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Remove receipt',
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}
