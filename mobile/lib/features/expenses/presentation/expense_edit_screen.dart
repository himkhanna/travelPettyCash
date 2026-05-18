import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/money/money.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expenses_providers.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';

/// Screen-inventory #10 — Expense detail (edit).
///
/// Per the team decision documented in screen-inventory.md, amount, category,
/// occurredAt, source, and details are all editable until the trip is CLOSED.
/// When the trip is closed we render a locked banner and disable the form.
class ExpenseEditScreen extends ConsumerStatefulWidget {
  const ExpenseEditScreen({
    super.key,
    required this.tripId,
    required this.expenseId,
  });

  final String tripId;
  final String expenseId;

  @override
  ConsumerState<ExpenseEditScreen> createState() => _ExpenseEditScreenState();
}

class _ExpenseEditScreenState extends ConsumerState<ExpenseEditScreen> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _detailsCtrl = TextEditingController();
  final TextEditingController _vendorCtrl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  Expense? _original;
  String? _sourceId;
  String? _categoryCode;
  DateTime? _occurredAt;
  bool _saving = false;
  Future<Expense>? _expenseFuture;

  @override
  void initState() {
    super.initState();
    _expenseFuture =
        ref.read(expenseRepositoryProvider).byId(widget.expenseId);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _detailsCtrl.dispose();
    _vendorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
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
          onPressed: () => context.go(
            '/m/trips/${widget.tripId}/expenses/${widget.expenseId}',
          ),
        ),
        title: Text(l.expense_edit_title),
      ),
      body: FutureBuilder<Expense>(
        future: _expenseFuture,
        builder: (BuildContext context, AsyncSnapshot<Expense> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final Expense e = snap.data!;
          _seedOnce(e);

          return tripAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object err, _) => Center(child: Text('Error: $err')),
            data: (Trip trip) {
              final bool locked = trip.status == TripStatus.closed;
              return SingleChildScrollView(
                padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (locked) _LockedBanner(message: l.expense_edit_locked),
                      const SizedBox(height: AppSpacing.md),
                      _Label(text: l.expense_edit_amount),
                      _AmountField(
                        controller: _amountCtrl,
                        currency: trip.currency,
                        enabled: !locked,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: l.expense_detail_source),
                      sourcesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (Object err, _) => Text('Error: $err'),
                        data: (List<Source> sources) => _SourceChips(
                          sources: sources,
                          selected: _sourceId,
                          enabled: !locked,
                          onPick: (String id) =>
                              setState(() => _sourceId = id),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: l.expense_detail_category),
                      categoriesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (Object err, _) => Text('Error: $err'),
                        data: (List<ExpenseCategory> cats) => _CategoryChips(
                          categories: cats,
                          selected: _categoryCode,
                          enabled: !locked,
                          onPick: (String code) =>
                              setState(() => _categoryCode = code),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: l.expense_add_vendor),
                      TextFormField(
                        controller: _vendorCtrl,
                        enabled: !locked,
                        decoration: InputDecoration(
                          hintText: l.expense_add_vendorHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: l.expense_detail_details),
                      TextFormField(
                        controller: _detailsCtrl,
                        maxLines: 3,
                        enabled: !locked,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: l.expense_add_occurredAt),
                      _OccurredAtTile(
                        value: _occurredAt ?? e.occurredAt,
                        enabled: !locked,
                        onChanged: (DateTime d) =>
                            setState(() => _occurredAt = d),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton(
                        onPressed: locked || _saving
                            ? null
                            : () => _save(trip),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.cream,
                                ),
                              )
                            : Text(l.expense_edit_save),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _seedOnce(Expense e) {
    if (_original != null) return;
    _original = e;
    _amountCtrl.text = e.amount.majorValue.toString();
    _detailsCtrl.text = e.details;
    _vendorCtrl.text = e.vendor ?? '';
    _sourceId = e.sourceId;
    _categoryCode = e.categoryCode;
    _occurredAt = e.occurredAt;
  }

  Future<void> _save(Trip trip) async {
    if (_original == null) return;
    final FormState? form = _formKey.currentState;
    if (form != null && !form.validate()) return;
    final String raw = _amountCtrl.text.replaceAll(',', '');
    final double major = double.tryParse(raw) ?? 0;
    if (major <= 0) {
      _toast(AppLocalizations.of(context).expense_add_validation_amount);
      return;
    }
    final Money amount = Money.fromMajor(major, trip.currency);
    setState(() => _saving = true);
    try {
      await ref.read(expenseRepositoryProvider).update(
            widget.expenseId,
            ExpensePatch(
              sourceId: _sourceId,
              categoryCode: _categoryCode,
              amount: amount,
              details: _detailsCtrl.text.trim(),
              vendor: _vendorCtrl.text.trim().isEmpty
                  ? null
                  : _vendorCtrl.text.trim(),
              occurredAt: _occurredAt,
            ),
          );
      ref.invalidate(myExpensesProvider(widget.tripId));
      ref.invalidate(tripBalancesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).expense_edit_saved),
        ),
      );
      context.go(
        '/m/trips/${widget.tripId}/expenses/${widget.expenseId}',
      );
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
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

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.outflow.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.all(AppRadii.card),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.lock_outline, color: AppColors.outflow),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.outflow,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.currency,
    required this.enabled,
  });
  final TextEditingController controller;
  final String currency;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColors.brandBrown,
            fontWeight: FontWeight.w700,
          ),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        prefixText: '$currency  ',
        border: const UnderlineInputBorder(),
      ),
    );
  }
}

class _SourceChips extends StatelessWidget {
  const _SourceChips({
    required this.sources,
    required this.selected,
    required this.enabled,
    required this.onPick,
  });
  final List<Source> sources;
  final String? selected;
  final bool enabled;
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
            onSelected: enabled ? (_) => onPick(s.id) : null,
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

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.enabled,
    required this.onPick,
  });
  final List<ExpenseCategory> categories;
  final String? selected;
  final bool enabled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final ExpenseCategory c in categories)
          ChoiceChip(
            label: Text(c.nameEn),
            selected: selected == c.code,
            onSelected: enabled ? (_) => onPick(c.code) : null,
            selectedColor: AppColors.forCategory(c.code),
            labelStyle: TextStyle(
              color: selected == c.code
                  ? Colors.white
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _OccurredAtTile extends StatelessWidget {
  const _OccurredAtTile({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final DateTime value;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled
          ? () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) onChanged(picked);
            }
          : null,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
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
