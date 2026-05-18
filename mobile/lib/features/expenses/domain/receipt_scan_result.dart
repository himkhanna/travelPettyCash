import '../../../core/money/money.dart';

/// Structured response from `POST /api/v1/receipts/scan`.
///
/// The endpoint is deterministic-first OCR (Tesseract on-prem, per
/// CLAUDE.md §3). Every field except [confidence] and [warning] is
/// optional — fields the OCR cannot extract come back null and the form
/// stays blank for the user to fill manually.
///
/// The shape is shared with the backend agent's contract for the same
/// endpoint, so do not rename fields without updating both sides.
class ReceiptScanResult {
  const ReceiptScanResult({
    required this.confidence,
    required this.warning,
    this.vendor,
    this.amount,
    this.quantity,
    this.categoryHint,
    this.occurredAt,
  });

  /// Merchant name as read from the receipt header (e.g. "Carrefour Riyadh").
  final String? vendor;

  /// Total charged. Currency comes from the trip context, not the receipt —
  /// trips are single-currency (CLAUDE.md §6.3).
  final Money? amount;

  /// Item count when the receipt is a multi-line bill. Defaults to 1 if
  /// the OCR can't infer it.
  final int? quantity;

  /// Suggested ExpenseCategory.code (FOOD / HOTEL / TRANSPORT / ...).
  /// The user can override; the hint is just to pre-select the chip.
  final String? categoryHint;

  /// Transaction date extracted from the receipt.
  final DateTime? occurredAt;

  /// 0.0 – 1.0. Below ~0.7 the UI should be visually cautious. Used today
  /// only to drive the yellow disclaimer banner — every result shows it.
  final double confidence;

  /// Localized warning string the UI surfaces verbatim in the disclaimer
  /// banner. Kept server-driven so we can A/B the wording without a mobile
  /// release.
  final String warning;

  /// Parses the wire payload as documented in the OpenAPI spec:
  /// `{ vendor, amount: { amount, currency }, quantity, categoryHint,
  ///    occurredAt, confidence, warning }`
  factory ReceiptScanResult.fromJson(Map<String, Object?> json) {
    final Map<String, Object?>? amountJson =
        json['amount'] as Map<String, Object?>?;
    return ReceiptScanResult(
      vendor: json['vendor'] as String?,
      amount: amountJson == null
          ? null
          : Money(
              amountJson['amount']! as int,
              amountJson['currency']! as String,
            ),
      quantity: json['quantity'] as int?,
      categoryHint: json['categoryHint'] as String?,
      occurredAt: json['occurredAt'] == null
          ? null
          : DateTime.parse(json['occurredAt']! as String),
      confidence: (json['confidence']! as num).toDouble(),
      warning: (json['warning'] as String?) ??
          'OCR result — please verify before submitting.',
    );
  }
}
