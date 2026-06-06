package ae.gov.pdd.pettycash.ocr;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tests {@link ReceiptOcrService#extract(String)} directly — the pure text
 * parsing path, no native Tesseract needed. Confirms the categorizer is
 * wired into the result alongside the existing vendor / amount / date
 * extraction.
 */
class ReceiptOcrServiceExtractTest {

    private final ReceiptOcrService service =
        new ReceiptOcrService("", "eng", "", new ReceiptCategorizer());

    @Test
    void extractsVendorAmountDateAndCategoryFromAReceipt() {
        String receipt = String.join("\n",
            "Rotana Hotel Abu Dhabi",
            "Room service",
            "Date: 14/05/2026",
            "Subtotal 1,200.00",
            "VAT 60.00",
            "TOTAL 1,260.00 AED");

        OcrResult r = service.extract(receipt);

        assertThat(r.engineAvailable()).isTrue();
        assertThat(r.suggestedVendor()).isEqualTo("Rotana Hotel Abu Dhabi");
        assertThat(r.suggestedAmountMinor()).isEqualTo(126000L); // largest amount
        assertThat(r.suggestedOccurredAt()).isNotNull();
        assertThat(r.suggestedOccurredAt().toString()).isEqualTo("2026-05-14");
        assertThat(r.suggestedCategoryCode()).isEqualTo("HOTEL");
    }

    @Test
    void leavesCategoryNullWhenUnrecognised() {
        OcrResult r = service.extract("Generic Trading LLC\nInvoice 88\n50.00");
        assertThat(r.suggestedCategoryCode()).isNull();
        assertThat(r.suggestedAmountMinor()).isEqualTo(5000L);
    }

    @Test
    void emptyTextReturnsEmptyResult() {
        OcrResult r = service.extract("   ");
        assertThat(r.engineAvailable()).isTrue();
        assertThat(r.suggestedCategoryCode()).isNull();
        assertThat(r.message()).isEqualTo("No text detected.");
    }
}
