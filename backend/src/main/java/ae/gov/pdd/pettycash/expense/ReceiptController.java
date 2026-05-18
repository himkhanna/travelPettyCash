package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.common.ApiException;
import ae.gov.pdd.pettycash.storage.StorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.Set;
import java.util.UUID;

/**
 * Receipt upload + presigned download. See CLAUDE.md §3 (storage), §7 (permissions),
 * §9 (presigned-URL pattern).
 *
 * <p>Object keys: {@code receipts/{tripId}/{expenseId}/{uuid}.{ext}}.
 */
@RestController
@RequestMapping("/api/v1/expenses")
public class ReceiptController {

    private static final Logger log = LoggerFactory.getLogger(ReceiptController.class);

    private static final long MAX_RECEIPT_BYTES = 8L * 1024 * 1024;
    private static final Duration PRESIGN_TTL = Duration.ofMinutes(5);
    private static final Set<String> ALLOWED_CONTENT_TYPES = Set.of("image/jpeg", "image/png");

    private final ExpenseService expenses;
    private final StorageService storage;

    public ReceiptController(ExpenseService expenses, StorageService storage) {
        this.expenses = expenses;
        this.storage = storage;
    }

    @PostMapping(path = "/{id}/receipt", consumes = "multipart/form-data")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<ExpenseDtos.ReceiptUploadResponse> upload(
            @PathVariable UUID id,
            @RequestParam("file") MultipartFile file) throws IOException {
        Expense expense = expenses.authorizeReceiptAccess(id);
        validate(file);
        String ext = extensionFor(file.getContentType());
        String key = "receipts/" + expense.getTripId() + "/" + expense.getId()
            + "/" + UUID.randomUUID() + "." + ext;
        try (var in = file.getInputStream()) {
            storage.putObject(key, in, file.getSize(), file.getContentType());
        }
        Expense updated = expenses.setReceiptObjectKey(id, key);
        log.info("Receipt uploaded for expense {} (key={}, size={})", id, key, file.getSize());
        return ResponseEntity.ok(new ExpenseDtos.ReceiptUploadResponse(updated.getReceiptObjectKey()));
    }

    @GetMapping("/{id}/receipt")
    @PreAuthorize("isAuthenticated()")
    public ExpenseDtos.ReceiptSignedUrlResponse get(@PathVariable UUID id) {
        Expense expense = expenses.authorizeReceiptAccess(id);
        if (expense.getReceiptObjectKey() == null) {
            throw ApiException.notFound("RECEIPT_NOT_FOUND", "No receipt attached to expense " + id);
        }
        var url = storage.presignGet(expense.getReceiptObjectKey(), PRESIGN_TTL);
        return new ExpenseDtos.ReceiptSignedUrlResponse(
            url.toString(),
            OffsetDateTime.now().plus(PRESIGN_TTL));
    }

    public static void validate(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw ApiException.badRequest("RECEIPT_EMPTY", "Receipt file is required");
        }
        if (file.getSize() > MAX_RECEIPT_BYTES) {
            throw ApiException.badRequest("RECEIPT_TOO_LARGE",
                "Receipt must be 8 MB or less; got " + file.getSize() + " bytes");
        }
        String ct = file.getContentType();
        if (ct == null || !ALLOWED_CONTENT_TYPES.contains(ct.toLowerCase())) {
            throw ApiException.badRequest("RECEIPT_UNSUPPORTED_TYPE",
                "Receipt must be image/jpeg or image/png; got " + ct);
        }
    }

    public static String extensionFor(String contentType) {
        return switch (contentType.toLowerCase()) {
            case "image/jpeg" -> "jpg";
            case "image/png"  -> "png";
            default -> throw ApiException.badRequest("RECEIPT_UNSUPPORTED_TYPE",
                "Unsupported content type: " + contentType);
        };
    }
}
