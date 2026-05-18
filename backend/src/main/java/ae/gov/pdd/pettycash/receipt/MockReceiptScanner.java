package ae.gov.pdd.pettycash.receipt;

import ae.gov.pdd.pettycash.common.MoneyDto;
import org.springframework.stereotype.Component;

import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

/**
 * Deterministic stub. Returns one of four canned responses keyed by
 * {@code sha256(imageBytes) mod 4} — same image always returns the same fields.
 *
 * <p>See ADR-005. To swap in real OCR, implement {@link ReceiptScanner} elsewhere
 * and remove this component (or gate it on {@code pettycash.ocr.provider=MOCK}).
 */
@Component
public class MockReceiptScanner implements ReceiptScanner {

    private static final String WARNING = "OCR result — please verify before submitting.";
    private static final OffsetDateTime FIXED_AT =
        OffsetDateTime.of(2026, 5, 18, 14, 32, 0, 0, ZoneOffset.ofHours(3));

    @Override
    public ReceiptScanResult scan(byte[] imageBytes, String currencyCode) {
        String currency = (currencyCode == null || currencyCode.isBlank()) ? "SAR" : currencyCode.toUpperCase();
        int bucket = bucketOf(imageBytes);
        return switch (bucket) {
            case 0 -> new ReceiptScanResult(
                "Carrefour Riyadh",
                new MoneyDto(1500L, currency),
                1,
                "FOOD",
                FIXED_AT,
                0.72,
                WARNING);
            case 1 -> new ReceiptScanResult(
                "Uber Trip",
                new MoneyDto(4200L, currency),
                1,
                "TRANSPORT",
                FIXED_AT,
                0.81,
                WARNING);
            case 2 -> new ReceiptScanResult(
                "Hilton Riyadh",
                new MoneyDto(85000L, currency),
                1,
                "HOTEL",
                FIXED_AT,
                0.66,
                WARNING);
            default -> new ReceiptScanResult(
                "STC Telecom",
                new MoneyDto(9900L, currency),
                1,
                "PHONE",
                FIXED_AT,
                0.58,
                WARNING);
        };
    }

    static int bucketOf(byte[] imageBytes) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(imageBytes == null ? new byte[0] : imageBytes);
            // Use the first 4 bytes interpreted unsigned, mod 4.
            int v = ByteBuffer.wrap(digest, 0, 4).getInt();
            return Math.floorMod(v, 4);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }
}
