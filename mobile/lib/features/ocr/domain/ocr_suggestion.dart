/// Suggestions returned from the backend's OCR endpoint. All fields except
/// [engineAvailable] are nullable — the UI prefills only the ones that
/// were actually detected.
class OcrSuggestion {
  const OcrSuggestion({
    required this.engineAvailable,
    this.rawText,
    this.vendor,
    this.amountMinor,
    this.occurredAt,
    this.message,
  });

  final bool engineAvailable;
  final String? rawText;
  final String? vendor;
  final int? amountMinor;
  final DateTime? occurredAt;
  final String? message;

  bool get hasAnyPrefill =>
      vendor != null || amountMinor != null || occurredAt != null;

  factory OcrSuggestion.fromJson(Map<String, dynamic> j) {
    return OcrSuggestion(
      engineAvailable: j['engineAvailable'] as bool? ?? false,
      rawText: j['rawText'] as String?,
      vendor: j['suggestedVendor'] as String?,
      amountMinor: (j['suggestedAmountMinor'] as num?)?.toInt(),
      occurredAt: j['suggestedOccurredAt'] == null
          ? null
          : DateTime.parse(j['suggestedOccurredAt'] as String),
      message: j['message'] as String?,
    );
  }
}
