import 'dart:typed_data';

import '../domain/receipt_scan_result.dart';

/// Repository for `POST /api/v1/receipts/scan`.
///
/// Phase 1 ships with a fake implementation that returns canned results
/// keyed on the SHA-256 of the uploaded bytes. The real implementation
/// will be a dio-backed client once the backend lands; the interface stays
/// identical so the UI doesn't change.
abstract class ReceiptScanRepository {
  Future<ReceiptScanResult> scan({
    required String tripId,
    required Uint8List bytes,
    required String fileName,
  });
}
