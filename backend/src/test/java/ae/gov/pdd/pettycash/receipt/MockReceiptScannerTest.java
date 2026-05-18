package ae.gov.pdd.pettycash.receipt;

import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class MockReceiptScannerTest {

    private final MockReceiptScanner scanner = new MockReceiptScanner();

    @Test
    void sameImageBytesAlwaysReturnsSameFields() {
        byte[] image = "fake-jpeg-bytes".getBytes();
        ReceiptScanResult a = scanner.scan(image, "SAR");
        ReceiptScanResult b = scanner.scan(image, "SAR");
        assertThat(a).isEqualTo(b);
        assertThat(a.warning()).isEqualTo("OCR result — please verify before submitting.");
        assertThat(a.amount().currency()).isEqualTo("SAR");
    }

    @Test
    void differentBucketsReturnDifferentCannedResponses() {
        // Search for 4 different bucket values across short distinct strings.
        Set<Integer> buckets = new HashSet<>();
        Set<String> vendors = new HashSet<>();
        for (int i = 0; i < 200 && buckets.size() < 4; i++) {
            byte[] bytes = ("seed-" + i).getBytes();
            buckets.add(MockReceiptScanner.bucketOf(bytes));
            vendors.add(scanner.scan(bytes, "SAR").vendor());
        }
        assertThat(buckets).hasSize(4);
        assertThat(vendors).hasSize(4);
        assertThat(vendors).containsExactlyInAnyOrder(
            "Carrefour Riyadh", "Uber Trip", "Hilton Riyadh", "STC Telecom");
    }

    @Test
    void defaultsToSarWhenCurrencyNull() {
        ReceiptScanResult r = scanner.scan(new byte[]{1, 2, 3}, null);
        assertThat(r.amount().currency()).isEqualTo("SAR");
    }

    @Test
    void usesTripCurrencyWhenProvided() {
        ReceiptScanResult r = scanner.scan(new byte[]{1, 2, 3}, "AED");
        assertThat(r.amount().currency()).isEqualTo("AED");
    }
}
