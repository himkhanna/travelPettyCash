package ae.gov.pdd.pettycash.receipt;

import ae.gov.pdd.pettycash.common.ApiException;
import ae.gov.pdd.pettycash.config.OcrProperties;
import ae.gov.pdd.pettycash.expense.ReceiptController;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.UUID;

/**
 * Mock OCR endpoint. See CLAUDE.md §15 and ADR-005.
 *
 * <p>// TODO(§15 ADR-005): replace MockReceiptScanner with Tesseract impl post-demo.
 */
@RestController
@RequestMapping("/api/v1/receipts")
public class ReceiptScanController {

    private final ReceiptScanner scanner;
    private final TripRepository trips;
    private final OcrProperties ocr;

    public ReceiptScanController(ReceiptScanner scanner, TripRepository trips, OcrProperties ocr) {
        this.scanner = scanner;
        this.trips = trips;
        this.ocr = ocr;
    }

    @PostMapping(path = "/scan", consumes = "multipart/form-data")
    @PreAuthorize("isAuthenticated()")
    public ReceiptScanResult scan(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "tripId", required = false) UUID tripId) throws IOException {
        if (Boolean.FALSE.equals(ocr.enabled())) {
            throw ApiException.notFound("OCR_DISABLED", "OCR is disabled by configuration");
        }
        ReceiptController.validate(file);
        String currency = null;
        if (tripId != null) {
            Trip trip = trips.findById(tripId).orElseThrow(
                () -> ApiException.notFound("TRIP_NOT_FOUND", "Trip " + tripId));
            currency = trip.getCurrency();
        }
        byte[] bytes = file.getBytes();
        return scanner.scan(bytes, currency);
    }
}
