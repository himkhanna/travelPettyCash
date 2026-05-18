import 'dart:typed_data';

import '../../../core/fake/fake_config.dart';
import '../../../core/money/money.dart';
import '../domain/receipt_scan_result.dart';
import 'receipt_scan_repository.dart';

/// Deterministic stand-in for `POST /api/v1/receipts/scan`.
///
/// Phase 1 demos need to show the OCR flow without a real backend or a
/// real OCR engine. This repo hashes the uploaded bytes into one of four
/// canned receipts, simulates a 1.5s scan delay, and returns the same
/// shape the real endpoint will return.
///
/// **Bucket function:** the spec calls for `sha256(bytes) mod 4`. We
/// cannot pull `package:crypto` for this single use (CLAUDE.md §3, no new
/// dependencies without justification, plus the constraint in the brief).
/// Instead we use a 32-bit FNV-1a hash, which is also deterministic —
/// same image bytes always land in the same bucket. The four canned
/// results themselves are identical to the backend agent's set, so a
/// real OCR client switched in later will return the same `vendor`,
/// `amount`, `quantity`, and `categoryHint` values for at least one of
/// the buckets.
class FakeReceiptScanRepository implements ReceiptScanRepository {
  FakeReceiptScanRepository(this._cfg);

  final FakeConfig _cfg;

  static const String _warning = 'OCR result — please verify before submitting.';

  /// Canned results, indexed by FNV-1a(bytes) mod 4. Currency is hard-coded
  /// to SAR because the demo trip is KSA; the real endpoint will echo the
  /// trip currency from the query param.
  static final List<ReceiptScanResult> _canned = <ReceiptScanResult>[
    ReceiptScanResult(
      vendor: 'Carrefour Riyadh',
      amount: const Money(150000, 'SAR'),
      quantity: 1,
      categoryHint: 'FOOD',
      confidence: 0.72,
      warning: _warning,
    ),
    ReceiptScanResult(
      vendor: 'Marriott Riyadh',
      amount: const Money(8400000, 'SAR'),
      quantity: 1,
      categoryHint: 'HOTEL',
      confidence: 0.84,
      warning: _warning,
    ),
    ReceiptScanResult(
      vendor: 'Careem',
      amount: const Money(450000, 'SAR'),
      quantity: 1,
      categoryHint: 'TRANSPORT',
      confidence: 0.61,
      warning: _warning,
    ),
    ReceiptScanResult(
      vendor: 'Al Tazaj',
      amount: const Money(850000, 'SAR'),
      quantity: 2,
      categoryHint: 'FOOD',
      confidence: 0.55,
      warning: _warning,
    ),
  ];

  @override
  Future<ReceiptScanResult> scan({
    required String tripId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    // Simulate the 1.5s OCR latency the brief calls out. We deliberately
    // don't honour FakeConfig.latency here — the OCR "feels like work"
    // and the spinner is part of the UX the disclaimer banner depends on.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    _cfg.maybeFail(op: 'receipts.scan');

    final int bucket = _bucketFor(bytes);
    return _canned[bucket];
  }

  /// 32-bit FNV-1a hash mod 4. Pure Dart, no dependencies.
  /// Deterministic: same bytes → same bucket.
  static int _bucketFor(Uint8List bytes) {
    const int fnvOffset = 0x811c9dc5;
    const int fnvPrime = 0x01000193;
    int hash = fnvOffset;
    for (int i = 0; i < bytes.length; i++) {
      hash ^= bytes[i];
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash % 4;
  }
}
