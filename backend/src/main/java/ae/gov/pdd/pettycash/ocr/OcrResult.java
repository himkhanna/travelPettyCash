package ae.gov.pdd.pettycash.ocr;

import java.time.LocalDate;

/**
 * Suggestions returned from {@link ReceiptOcrService}. All fields except
 * {@code engineAvailable} are nullable — the UI prefills only the ones
 * that were detected, leaving the rest untouched.
 *
 * <ul>
 *   <li>{@code engineAvailable=false} means the OCR engine isn't loadable
 *       on this host (missing libtesseract or tessdata). The mobile app
 *       surfaces a "not configured" toast instead of prefilling.</li>
 *   <li>{@code message} carries a soft-failure note ("No text detected.",
 *       etc.) so the UI can show a contextual hint when extraction
 *       returns nothing.</li>
 * </ul>
 */
public record OcrResult(
    boolean engineAvailable,
    String rawText,
    String suggestedVendor,
    Long suggestedAmountMinor,
    LocalDate suggestedOccurredAt,
    String message
) {
    public static OcrResult unavailable() {
        return new OcrResult(false, null, null, null, null,
            "OCR engine not configured on this server.");
    }

    public static OcrResult empty(String message) {
        return new OcrResult(true, null, null, null, null, message);
    }
}
