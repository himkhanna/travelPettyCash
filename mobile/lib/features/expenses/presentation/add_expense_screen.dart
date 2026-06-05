import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../core/connectivity/offline_status_provider.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/pdd_primitives.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../ocr/data/ocr_repository.dart';
import '../../ocr/domain/ocr_suggestion.dart';
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

/// One row on the Add Expense form when the invoice contains multiple
/// line items. Each row owns its own three controllers so users can
/// type freely while live-total recomputes. Disposed in
/// [_AddExpenseScreenState.dispose] alongside the rest of the form.
class _LineItem {
  _LineItem({String? desc, String qty = '1', String unit = ''})
      : descCtrl = TextEditingController(text: desc ?? ''),
        qtyCtrl = TextEditingController(text: qty),
        unitCtrl = TextEditingController(text: unit);
  final TextEditingController descCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController unitCtrl;

  void dispose() {
    descCtrl.dispose();
    qtyCtrl.dispose();
    unitCtrl.dispose();
  }

  /// Compute this row's contribution to the total in major units.
  double totalMajor() {
    final double q = double.tryParse(qtyCtrl.text.trim()) ?? 0;
    final double u =
        double.tryParse(unitCtrl.text.replaceAll(',', '').trim()) ?? 0;
    return (q <= 0 || u <= 0) ? 0 : q * u;
  }
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final TextEditingController _vendorCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final List<_LineItem> _lines = <_LineItem>[_LineItem()];
  static const Uuid _uuid = Uuid();

  /// ADR-003: curated foreign-currency list for the manual-rate toggle.
  static const List<String> _fxCurrencies = <String>[
    'EUR', 'USD', 'GBP', 'AED', 'SAR', 'QAR',
    'EGP', 'KWD', 'BHD', 'OMR', 'JOD', 'TRY',
  ];

  String? _sourceId;
  String? _categoryCode = 'FOOD';
  DateTime _occurredAt = DateTime.now();
  bool _submitting = false;
  XFile? _receiptFile;
  bool _ocrBusy = false;

  // ADR-003: foreign-currency original. When off, the entered amount is the
  // trip (base) currency — the existing path is untouched.
  bool _foreignCurrency = false;
  String? _foreignCode;
  final TextEditingController _rateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _attachListeners(_lines.first);
  }

  void _attachListeners(_LineItem li) {
    li.qtyCtrl.addListener(() => setState(() {}));
    li.unitCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _vendorCtrl.dispose();
    _noteCtrl.dispose();
    _rateCtrl.dispose();
    for (final _LineItem li in _lines) {
      li.dispose();
    }
    super.dispose();
  }

  /// Parsed manual rate (foreign → trip), or null when blank/invalid.
  double? get _parsedRate {
    final double? r =
        double.tryParse(_rateCtrl.text.replaceAll(',', '').trim());
    return (r != null && r > 0) ? r : null;
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
                        // Balance math is always in the trip (base) currency
                        // (ADR-003) — convert the foreign total at the manual
                        // rate before previewing the post-expense balance.
                        total: _baseAmount(trip.currency),
                        balancesAsync: balancesAsync,
                      ),
                      const SizedBox(height: 12),
                      // Invoice upload first — staff snap the receipt before
                      // typing anything, then the OCR auto-fill (when
                      // available) populates the fields below. Order matches
                      // the actual workflow on the ground.
                      _SectionLabel(label: 'Invoice'),
                      const SizedBox(height: 4),
                      _PhotoButton(
                        file: _receiptFile,
                        onPick: _pickReceipt,
                        onClear: () => setState(() => _receiptFile = null),
                      ),
                      if (_receiptFile != null) ...<Widget>[
                        const SizedBox(height: 8),
                        _OcrAutofillButton(
                          busy: _ocrBusy,
                          onTap: _runOcr,
                        ),
                        const SizedBox(height: 8),
                        _OcrDisclaimer(),
                      ],
                      const SizedBox(height: 14),
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
                      _SectionLabel(label: 'Line items'),
                      const SizedBox(height: 4),
                      for (int i = 0; i < _lines.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(height: 8),
                        _LineItemRow(
                          index: i,
                          line: _lines[i],
                          currency: trip.currency,
                          canRemove: _lines.length > 1,
                          onRemove: () => setState(() {
                            _lines.removeAt(i).dispose();
                          }),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              final _LineItem li = _LineItem();
                              _attachListeners(li);
                              _lines.add(li);
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add line item'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.brand,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _GrandTotal(
                        total: _foreignCurrency && _foreignCode != null
                            ? _total(_foreignCode!)
                            : _total(trip.currency),
                        currency: _foreignCurrency && _foreignCode != null
                            ? _foreignCode!
                            : trip.currency,
                      ),
                      const SizedBox(height: 14),
                      _SectionLabel(label: 'Currency'),
                      const SizedBox(height: 4),
                      _ForeignToggle(
                        value: _foreignCurrency,
                        onChanged: (bool v) => setState(() {
                          _foreignCurrency = v;
                          if (!v) {
                            _foreignCode = null;
                            _rateCtrl.clear();
                          }
                        }),
                      ),
                      if (_foreignCurrency) ...<Widget>[
                        const SizedBox(height: 10),
                        _Field(
                          label: 'Foreign currency',
                          child: DropdownButtonFormField<String>(
                            initialValue: _foreignCode,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              hintText: 'Select currency',
                            ),
                            items: <DropdownMenuItem<String>>[
                              for (final String code in _fxCurrencies)
                                if (code != trip.currency)
                                  DropdownMenuItem<String>(
                                    value: code,
                                    child: Text(code),
                                  ),
                            ],
                            onChanged: (String? v) =>
                                setState(() => _foreignCode = v),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _Field(
                          label: _foreignCode == null
                              ? 'Exchange rate'
                              : '1 $_foreignCode = ? ${trip.currency}',
                          child: TextField(
                            controller: _rateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: '0.000000',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_foreignCode != null && _parsedRate != null) ...<Widget>[
                          const SizedBox(height: 8),
                          _ConvertedPreview(
                            base: Money.fromMajor(
                              _total(_foreignCode!).majorValue * _parsedRate!,
                              trip.currency,
                            ),
                          ),
                        ],
                      ],
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
                  // Receipt is optional (BRD §2.3) — do not gate submit on it.
                  enabled: !_submitting &&
                      _vendorCtrl.text.trim().isNotEmpty &&
                      _lines.any((_LineItem li) => li.totalMajor() > 0),
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
    final double total = _lines.fold<double>(
      0, (double acc, _LineItem li) => acc + li.totalMajor(),
    );
    if (total <= 0) return Money.zero(currency);
    return Money.fromMajor(total, currency);
  }

  /// The canonical trip-currency (base) amount. When a foreign currency +
  /// valid rate are set, converts the line-item sum at the manual rate
  /// (ADR-003); otherwise it's just the line-item sum in the trip currency.
  Money _baseAmount(String tripCurrency) {
    if (_foreignCurrency && _foreignCode != null && _parsedRate != null) {
      return Money.fromMajor(
        _total(_foreignCode!).majorValue * _parsedRate!,
        tripCurrency,
      );
    }
    return _total(tripCurrency);
  }

  Future<void> _submit(Trip trip) async {
    if (_total(trip.currency).isZero) {
      showPddToast(context, 'Add at least one line item with qty + unit cost');
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

    // ADR-003: foreign currency requires both a currency and a positive rate.
    if (_foreignCurrency) {
      if (_foreignCode == null) {
        showPddToast(context, 'Please select the foreign currency');
        return;
      }
      if (_parsedRate == null) {
        showPddToast(context, 'Please enter a valid exchange rate');
        return;
      }
    }

    // The canonical amount is always the trip (base) currency. When foreign,
    // it's the converted line-item sum; otherwise the sum itself.
    final Money amount = _baseAmount(trip.currency);
    // Foreign original (all-three-or-none) — null on the common base path.
    final Money? foreignTotal =
        _foreignCurrency ? _total(_foreignCode!) : null;
    final double? rate = _foreignCurrency ? _parsedRate : null;

    setState(() => _submitting = true);
    try {
      final String userId =
          ref.read(currentUserProvider).valueOrNull?.id ?? '';
      // Total quantity is the sum across rows so the canonical record still
      // captures the volume even though the model has no line-item table.
      final int qty = _lines.fold<int>(
        0,
        (int acc, _LineItem li) =>
            acc + (int.tryParse(li.qtyCtrl.text.trim()) ?? 0),
      );
      // Encode each line into `details` so the audit trail keeps the
      // breakdown even though we're not splitting into N rows on the
      // server. Format mirrors a receipt's printed layout.
      final List<String> lineParts = <String>[];
      for (final _LineItem li in _lines) {
        if (li.totalMajor() <= 0) continue;
        final String desc = li.descCtrl.text.trim();
        final String q = li.qtyCtrl.text.trim();
        final String u = li.unitCtrl.text.trim();
        lineParts.add(
          desc.isEmpty
              ? '$q × $u'
              : '$desc ($q × $u)',
        );
      }
      final String details = <String>[
        _vendorCtrl.text.trim(),
        if (lineParts.isNotEmpty) lineParts.join(' + '),
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
            originalCurrency: _foreignCurrency ? _foreignCode : null,
            originalAmountMinor: foreignTotal?.amountMinor,
            exchangeRate: rate,
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
          originalAmount: e.originalAmount,
          exchangeRate: e.exchangeRate,
        );
      }

      ref.invalidate(myExpensesProvider(trip.id));
      ref.invalidate(tripExpensesProvider(trip.id));
      ref.invalidate(
        tripBalancesProvider((tripId: trip.id, scope: BalanceScope.me)),
      );
      if (!mounted) return;
      // When the device is offline the fake/Drift repo writes the row
      // to the local queue with `pendingSync=true`. Call that out
      // explicitly so the user understands the draft state, and route
      // back to the offline screen (the trip dashboard is gated).
      final bool offline = ref.read(isOfflineProvider);
      showPddToast(
        context,
        offline
            ? 'Saved as draft — will sync when you are back online.'
            : 'Expense recorded — ${_fmt(amount)} ${trip.currency}',
      );
      if (offline) {
        context.go('/m/offline');
      } else {
        context.go('/m/trips/${trip.id}/dashboard');
      }
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

  /// Send the picked photo to the server's Tesseract endpoint and prefill
  /// whatever it could extract. Leaves fields the user already filled
  /// alone — only writes into blanks — so re-running OCR on a corrected
  /// form doesn't blow away the user's edits.
  Future<void> _runOcr() async {
    final XFile? file = _receiptFile;
    if (file == null) return;
    setState(() => _ocrBusy = true);
    try {
      final Uint8List bytes = await file.readAsBytes();
      final OcrSuggestion s =
          await ref.read(ocrRepositoryProvider).ocrReceipt(
                bytes: bytes,
                filename: file.name,
                mime: _mimeFor(file.name),
              );
      if (!s.engineAvailable) {
        if (mounted) {
          showPddToast(
            context,
            s.message ?? 'OCR not configured on the server.',
          );
        }
        return;
      }
      int prefills = 0;
      setState(() {
        if (s.vendor != null && _vendorCtrl.text.trim().isEmpty) {
          _vendorCtrl.text = s.vendor!;
          prefills++;
        }
        // OCR fills the FIRST line item only — multi-line invoices need
        // the user to add the remaining rows manually since the extractor
        // returns one total, not a line breakdown.
        final _LineItem first = _lines.first;
        if (s.amountMinor != null && first.unitCtrl.text.trim().isEmpty) {
          first.unitCtrl.text =
              (s.amountMinor! / 100.0).toStringAsFixed(2);
          if (first.qtyCtrl.text.trim().isEmpty) {
            first.qtyCtrl.text = '1';
          }
          prefills++;
        }
        if (s.occurredAt != null) {
          _occurredAt = s.occurredAt!;
          prefills++;
        }
      });
      if (mounted) {
        showPddToast(
          context,
          prefills == 0
              ? (s.message ?? 'No fields detected in the receipt.')
              : 'Prefilled $prefills field${prefills == 1 ? '' : 's'} from receipt.',
        );
      }
    } catch (e) {
      if (mounted) showPddToast(context, 'OCR failed: $e');
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
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

/// One row on the Add Expense line-items list. Description-qty-unit
/// inputs plus a delete affordance when more than one row exists.
class _LineItemRow extends StatelessWidget {
  const _LineItemRow({
    required this.index,
    required this.line,
    required this.currency,
    required this.canRemove,
    required this.onRemove,
  });
  final int index;
  final _LineItem line;
  final String currency;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final double total = line.totalMajor();
    final NumberFormat fmt = NumberFormat.decimalPattern('en_US');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandTint,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${index + 1}',
                  style: AppTypography.geist(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: line.descCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Line item description (optional)',
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (canRemove)
                IconButton(
                  tooltip: 'Remove line',
                  icon: const Icon(
                    Icons.close, size: 16, color: AppColors.ink3,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30, minHeight: 30,
                  ),
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: _Field(
                  label: 'Qty',
                  child: TextField(
                    controller: line.qtyCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Field(
                  label: 'Per unit',
                  child: TextField(
                    controller: line.unitCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
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
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Field(
                  label: 'Line total',
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.bgInset,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      total == 0
                          ? '—'
                          : '${fmt.format(total)} $currency',
                      style: AppTypography.geistMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grand total below the line items list — sum across every line.
class _GrandTotal extends StatelessWidget {
  const _GrandTotal({required this.total, required this.currency});
  final Money total;
  final String currency;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: total.isZero ? AppColors.bgCard : AppColors.brandSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: total.isZero
              ? AppColors.line
              : AppColors.brand.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(
            'GRAND TOTAL',
            style: AppTypography.geist(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.ink2,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          Text(
            total.isZero ? '—' : _fmt(total),
            style: AppTypography.geistMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: total.isZero ? AppColors.ink3 : AppColors.brand,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            currency,
            style: AppTypography.geist(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: total.isZero ? AppColors.ink3 : AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}

/// ADR-003 toggle row — "Spent in a foreign currency?". Styled as a card
/// to match the rest of the form rather than a bare SwitchListTile.
class _ForeignToggle extends StatelessWidget {
  const _ForeignToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Spent in a foreign currency?',
              style: AppTypography.geist(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink1,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.brand,
          ),
        ],
      ),
    );
  }
}

/// ADR-003 live preview — shows the converted trip-currency base amount
/// (`≈ <trip ccy> <base>`) below the rate field.
class _ConvertedPreview extends StatelessWidget {
  const _ConvertedPreview({required this.base});
  final Money base;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.swap_horiz, size: 16, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Deducted from balance',
              style: AppTypography.geist(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.brand,
              ),
            ),
          ),
          Text(
            '≈ ${base.format()}',
            style: AppTypography.geistMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
          ),
        ],
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
            // Neutral border — the invoice is optional (BRD §2.3).
            border: Border.all(
              color: AppColors.ink3.withValues(alpha: 0.35),
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
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink1,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bgApp,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'OPTIONAL',
                  style: AppTypography.geist(
                    fontSize: 10,
                    color: AppColors.ink3,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
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

/// Persistent warning shown whenever a receipt is attached — reminds the
/// user that any auto-populated fields are best-effort and must be checked
/// against the original receipt before the expense is recorded. Sits
/// directly below the Auto-fill button so the message lands at the moment
/// the user is about to act on the prefilled data.
class _OcrDisclaimer extends StatelessWidget {
  const _OcrDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline,
            size: 16,
            color: AppColors.goldDeep,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Please verify auto-populated details against the original '
              'invoice before submitting.',
              style: AppTypography.geist(
                fontSize: 11.5,
                color: AppColors.goldDeep,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OcrAutofillButton extends StatelessWidget {
  const _OcrAutofillButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: BorderSide(color: AppColors.brand.withValues(alpha: 0.6)),
          foregroundColor: AppColors.brand,
        ),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brand,
                ),
              )
            : const Icon(Icons.auto_fix_high, size: 18),
        label: Text(busy ? 'Reading receipt…' : 'Auto-fill from receipt'),
      ),
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
