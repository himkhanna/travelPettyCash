package ae.gov.pdd.pettycash.receipt;

/**
 * Abstraction for receipt OCR. See CLAUDE.md §15 and ADR-005.
 *
 * <p>// TODO(§15 ADR-005): replace with on-prem Tesseract impl post-demo.
 */
public interface ReceiptScanner {

    /**
     * Extract structured data from a receipt image.
     *
     * @param imageBytes raw image bytes (JPEG or PNG)
     * @param currencyCode ISO 4217 code to use for the extracted amount
     *                     (defaults to SAR when {@code null})
     */
    ReceiptScanResult scan(byte[] imageBytes, String currencyCode);
}
