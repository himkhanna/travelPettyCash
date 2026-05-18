import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/money/money.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/ocr_disclaimer_banner.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../auth/application/auth_providers.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expenses_providers.dart';
import '../application/pending_receipt_uploads.dart';
import '../data/receipt_scan_repository.dart';
import '../domain/expense.dart';
import '../domain/receipt_scan_result.dart';

/// Screen-inventory #5 / #6 — Add Expense form + success modal.
///
/// OCR-first layout: scan / upload buttons sit at the top, above all
/// fields. After a scan the form is pre-filled and a yellow disclaimer
/// banner sits between the scan block and the fields so the user is
/// reminded the values came from OCR (CLAUDE.md §15 — OCR is an opt-in
/// enhancement; the disclaimer is the visible guardrail).
///
/// Hero demo flow: tap SCAN RECEIPT → camera → 1.5s spinner →
/// vendor/amount/category/date populated → banner appears → user
/// adjusts source → submit. The offline-queue path still works exactly
/// the same way it did before this rework.
class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _detailsCtrl = TextEditingController();
  final TextEditingController _vendorCtrl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  static const Uuid _uuid = Uuid();

  String? _sourceId;
  String? _categoryCode;
  DateTime _occurredAt = DateTime.now();
  bool _submitting = false;
  XFile? _receiptFile;

  // OCR state.
  bool _scanning = false;
  bool _showDisclaimer = false;
  String? _disclaimerBody;
  String? _scanError;

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
          onPressed: () => context.go('/m/trips/${widget.tripId}/dashboard'),
        ),
        title: Text(l.expense_add_title),
      ),
      body: Column(
        children: <Widget>[
          const SyncStatusBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: tripAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Text('${l.common_error}: $e'),
                data: (Trip trip) => Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _OcrSection(
                        scanning: _scanning,
                        onScan: () => _runScan(trip, ImageSource.camera),
                        onUpload: () => _runScan(trip, ImageSource.gallery),
                        error: _scanError,
                        onDismissError: () =>
                            setState(() => _scanError = null),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_showDisclaimer) ...<Widget>[
                        OcrDisclaimerBanner(
                          body: _disclaimerBody ?? l.ocr_disclaimer_body,
                          onDismiss: () =>
                              setState(() => _showDisclaimer = false),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      _AmountField(
                        controller: _amountCtrl,
                        currency: trip.currency,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: l.expense_add_vendor),
                      TextFormField(
                        controller: _vendorCtrl,
                        decoration: InputDecoration(
                          hintText: l.expense_add_vendorHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: l.expense_add_source),
                      sourcesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (Object e, _) => Text('${l.common_error}: $e'),
                        data: (List<Source> sources) => _SourcePicker(
                          sources: sources,
                          selected: _sourceId,
                          onPick: (String id) => setState(() => _sourceId = id),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: l.expense_add_category),
                      categoriesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (Object e, _) => Text('${l.common_error}: $e'),
                        data: (List<ExpenseCategory> cats) => _CategoryPicker(
                          categories: cats,
                          selected: _categoryCode,
                          onPick: (String code) =>
                              setState(() => _categoryCode = code),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: l.expense_add_details),
                      TextFormField(
                        controller: _detailsCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: l.expense_add_detailsHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Label(text: l.expense_add_occurredAt),
                      _DatePickerTile(
                        value: _occurredAt,
                        onChanged: (DateTime d) =>
                            setState(() => _occurredAt = d),
                      ),
                      if (_receiptFile != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        _Label(text: l.expense_add_receipt),
                        _AttachedReceiptTile(
                          file: _receiptFile!,
                          onRemove: () =>
                              setState(() => _receiptFile = null),
                          replaceLabel: l.expense_add_replace,
                        ),
                      ],
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
                            : Text(l.expense_add_submit),
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

  Future<void> _runScan(Trip trip, ImageSource source) async {
    if (_scanning) return;
    final AppLocalizations l = AppLocalizations.of(context);
    try {
      final ImagePickFn pick = ref.read(imagePickerProvider);
      final XFile? picked = await pick(source);
      if (picked == null) return;
      setState(() {
        _receiptFile = picked;
        _scanning = true;
        _scanError = null;
      });
      final Uint8List bytes = await picked.readAsBytes();
      final ReceiptScanRepository repo = ref.read(
        receiptScanRepositoryProvider,
      );
      final ReceiptScanResult result = await repo.scan(
        tripId: trip.id,
        bytes: bytes,
        fileName: picked.name,
      );
      if (!mounted) return;
      _applyScanResult(result, trip.currency);
    } catch (e) {
      if (!mounted) return;
      // On failure leave the form empty but keep the image attached so
      // the receipt still rides along with the manual submission.
      setState(() {
        _scanError = l.ocr_failed;
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _applyScanResult(ReceiptScanResult r, String currency) {
    setState(() {
      if (r.vendor != null) _vendorCtrl.text = r.vendor!;
      if (r.amount != null) {
        // Backend echoes the trip currency; if for any reason it
        // diverges we still format the amount in the trip's units.
        final Money amount = r.amount!.currencyCode == currency
            ? r.amount!
            : Money(r.amount!.amountMinor, currency);
        _amountCtrl.text = _formatMajor(amount);
      }
      if (r.categoryHint != null) _categoryCode = r.categoryHint;
      if (r.occurredAt != null) _occurredAt = r.occurredAt!;
      _disclaimerBody = r.warning;
      _showDisclaimer = true;
    });
  }

  String _formatMajor(Money amount) {
    // Use the Money decimals to pick a plain string without thousands
    // separators (the field is editable and we want a parseable value).
    final int decimals = amount.decimals;
    if (decimals == 0) return amount.amountMinor.toString();
    final double v = amount.majorValue;
    return v.toStringAsFixed(decimals);
  }

  Future<void> _submit(Trip trip) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_sourceId == null) {
      _toast(l.expense_add_validation_source);
      return;
    }
    if (_categoryCode == null) {
      _toast(l.expense_add_validation_category);
      return;
    }
    final Money amount = _parseAmount(trip.currency);
    if (amount.isZero) {
      _toast(l.expense_add_validation_amount);
      return;
    }

    setState(() => _submitting = true);
    try {
      final String userId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
      final String vendor = _vendorCtrl.text.trim();
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
            // We do NOT set receiptObjectKey here — slice 3C does it via
            // [uploadReceiptBytes] below so the key reflects the real S3
            // object the server allocates. For the offline path the receipt
            // bytes are queued via [pendingReceiptUploadsProvider] and the
            // SyncCoordinator drains them after expense sync.
            receiptObjectKey: null,
            vendor: vendor.isEmpty ? null : vendor,
            idempotencyKey: _uuid.v4(),
          );

      if (_receiptFile != null) {
        await _attachReceipt(e, _receiptFile!);
      }

      // Refresh dependent providers.
      ref.invalidate(myExpensesProvider(trip.id));
      ref.invalidate(
        tripBalancesProvider((tripId: trip.id, scope: BalanceScope.me)),
      );
      if (!mounted) return;
      await _showSuccessModal(trip, e);
    } catch (err) {
      _toast('${l.common_error}: $err');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Attaches the picked receipt to the freshly-created expense. Three paths:
  ///   1. Offline — queue the bytes for the SyncCoordinator to drain later.
  ///   2. Online success — uploadReceiptBytes patches the expense in place.
  ///   3. Online failure — show a snackbar with a RETRY action that
  ///      re-attempts the same bytes. We deliberately do NOT fail the
  ///      whole submission: the expense itself is already saved.
  Future<void> _attachReceipt(Expense expense, XFile file) async {
    final Uint8List bytes = await file.readAsBytes();
    final FakeConfig cfg = ref.read(fakeConfigProvider);
    if (cfg.offlineMode) {
      ref.read(pendingReceiptUploadsProvider).enqueue(
            PendingReceiptUpload(
              expenseId: expense.id,
              bytes: bytes,
              filename: file.name,
            ),
          );
      return;
    }
    await _doReceiptUpload(expense.id, bytes, file.name);
  }

  Future<void> _doReceiptUpload(
    String expenseId,
    Uint8List bytes,
    String filename,
  ) async {
    final AppLocalizations l = AppLocalizations.of(context);
    try {
      await ref
          .read(expenseRepositoryProvider)
          .uploadReceiptBytes(expenseId, bytes, filename);
    } catch (_) {
      if (!mounted) return;
      // The expense is safe — only the receipt failed. Offer a retry.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.receipt_uploadFailed),
          action: SnackBarAction(
            label: l.receipt_uploadRetry,
            onPressed: () => _doReceiptUpload(expenseId, bytes, filename),
          ),
        ),
      );
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
    final AppLocalizations l = AppLocalizations.of(context);
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
            e.pendingSync
                ? l.expense_add_success_queued
                : l.expense_add_success_title,
            textAlign: TextAlign.center,
          ),
          content: Text(
            e.pendingSync
                ? l.expense_add_success_queuedBody
                : '${e.amount.format()} recorded.',
            textAlign: TextAlign.center,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _resetForm();
              },
              child: Text(l.expense_add_addMore),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.go('/m/trips/${trip.id}/dashboard');
              },
              child: Text(l.common_close),
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
    _vendorCtrl.clear();
    setState(() {
      _sourceId = null;
      _categoryCode = null;
      _occurredAt = DateTime.now();
      _receiptFile = null;
      _showDisclaimer = false;
      _disclaimerBody = null;
      _scanError = null;
    });
  }
}

/// The OCR-first top block: SCAN RECEIPT, UPLOAD FROM GALLERY, divider,
/// optional scanning spinner, optional error tile. Replaces the old
/// bottom-anchored "ADD RECEIPT" affordance.
class _OcrSection extends StatelessWidget {
  const _OcrSection({
    required this.scanning,
    required this.onScan,
    required this.onUpload,
    required this.error,
    required this.onDismissError,
  });

  final bool scanning;
  final VoidCallback onScan;
  final VoidCallback onUpload;
  final String? error;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          onPressed: scanning ? null : onScan,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.goldOlive,
            foregroundColor: AppColors.textOnBrand,
            minimumSize: const Size(double.infinity, 56),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(AppRadii.button),
            ),
          ),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(l.expense_add_scanReceipt),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: scanning ? null : onUpload,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandBrown,
            backgroundColor: AppColors.cream,
            side: const BorderSide(color: AppColors.brandBrown),
            minimumSize: const Size(double.infinity, 52),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(AppRadii.button),
            ),
          ),
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(l.expense_add_uploadGallery),
        ),
        if (scanning) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _ScanningCard(label: l.ocr_scanning),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _ScanErrorCard(message: error!, onDismiss: onDismissError),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            const Expanded(child: Divider(color: AppColors.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                l.expense_add_orFillManually,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
              ),
            ),
            const Expanded(child: Divider(color: AppColors.divider)),
          ],
        ),
      ],
    );
  }
}

class _ScanningCard extends StatelessWidget {
  const _ScanningCard({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: AppColors.goldOlive),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.goldOlive,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.brandBrownDark,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanErrorCard extends StatelessWidget {
  const _ScanErrorCard({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.outflow.withValues(alpha: 0.10),
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: AppColors.outflow),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, color: AppColors.outflow),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.outflow,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onDismiss,
            tooltip: AppLocalizations.of(context).common_close,
          ),
        ],
      ),
    );
  }
}

class _AttachedReceiptTile extends StatelessWidget {
  const _AttachedReceiptTile({
    required this.file,
    required this.onRemove,
    required this.replaceLabel,
  });

  final XFile file;
  final VoidCallback onRemove;
  final String replaceLabel;

  @override
  Widget build(BuildContext context) {
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
                file.path,
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
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  replaceLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: AppLocalizations.of(context).common_close,
            onPressed: onRemove,
          ),
        ],
      ),
    );
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
        prefixStyle: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: AppColors.textSecondary),
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
