package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.common.idempotency.IdempotencyService;
import ae.gov.pdd.pettycash.expense.dto.CreateExpenseCommentRequest;
import ae.gov.pdd.pettycash.expense.dto.CreateExpenseRequest;
import ae.gov.pdd.pettycash.expense.dto.ExpenseCommentDto;
import ae.gov.pdd.pettycash.expense.dto.ExpenseDto;
import ae.gov.pdd.pettycash.expense.dto.ExpenseSummaryDto;
import ae.gov.pdd.pettycash.expense.dto.PatchExpenseRequest;
import ae.gov.pdd.pettycash.expense.dto.ReassignSourceRequest;
import ae.gov.pdd.pettycash.expense.dto.ReceiptUrlDto;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class ExpenseController {

    private final ExpenseService service;
    private final ExpenseCommentService comments;
    private final IdempotencyService idempotency;

    public ExpenseController(
        ExpenseService service,
        ExpenseCommentService comments,
        IdempotencyService idempotency
    ) {
        this.service = service;
        this.comments = comments;
        this.idempotency = idempotency;
    }

    @GetMapping("/trips/{tripId}/expenses")
    public List<ExpenseDto> list(
        @PathVariable UUID tripId,
        @RequestParam(name = "userId", required = false) UUID userId,
        @RequestParam(name = "categoryCode", required = false) List<String> categoryCodes,
        @RequestParam(name = "sourceId", required = false) List<UUID> sourceIds,
        @RequestParam(name = "memberId", required = false) List<UUID> memberIds,
        @RequestParam(name = "from", required = false) Instant from,
        @RequestParam(name = "to",   required = false) Instant to,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.list(tripId, caller, new ExpenseService.Filter(
            userId, categoryCodes, sourceIds, memberIds, from, to
        ));
    }

    @GetMapping("/expenses/{id}")
    public ExpenseDto detail(
        @PathVariable UUID id,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.get(id, caller);
    }

    /**
     * Admin-only "receipt triage" feed — non-deleted expenses with no
     * attached receipt. Backs the dashboard's Triage CTA so the admin can
     * fix or ping in one place rather than scanning every trip.
     */
    @GetMapping("/expenses/missing-receipt")
    public List<ExpenseDto> missingReceipts(
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.missingReceipts(caller);
    }

    @PostMapping("/trips/{tripId}/expenses")
    public ExpenseDto create(
        @PathVariable UUID tripId,
        @Valid @RequestBody CreateExpenseRequest body,
        @RequestHeader(name = "Idempotency-Key", required = false) String idempotencyKey,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        String key = IdempotencyService.require(idempotencyKey);
        return idempotency.runOrReplay(
            key, caller.userId(), "POST /trips/expenses", ExpenseDto.class,
            () -> service.create(tripId, body, caller)
        );
    }

    @PatchMapping("/expenses/{id}")
    public ExpenseDto patch(
        @PathVariable UUID id,
        @Valid @RequestBody PatchExpenseRequest body,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.patch(id, body, caller);
    }

    @PatchMapping("/expenses/{id}/source")
    public ExpenseDto reassignSource(
        @PathVariable UUID id,
        @Valid @RequestBody ReassignSourceRequest body,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.reassignSource(id, body.sourceId(), caller);
    }

    @GetMapping("/trips/{tripId}/expenses/summary")
    public ExpenseSummaryDto summary(
        @PathVariable UUID tripId,
        @RequestParam(name = "scope", required = false, defaultValue = "trip") String scope,
        @RequestParam(name = "groupBy", required = false, defaultValue = "category") String groupBy,
        @RequestParam(name = "userId", required = false) UUID userId,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.summary(tripId, caller, scope, groupBy, userId);
    }

    /** Maximum receipt size: 5 MB. Larger ones are rejected at the boundary. */
    private static final long MAX_RECEIPT_BYTES = 5L * 1024 * 1024;

    private static final Set<String> ALLOWED_RECEIPT_TYPES = Set.of(
        "image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic",
        "application/pdf"
    );

    @PostMapping(path = "/expenses/{id}/receipt", consumes = "multipart/form-data")
    public ExpenseDto uploadReceipt(
        @PathVariable UUID id,
        @RequestPart("file") MultipartFile file,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        if (file.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                "validation/empty-receipt", "Empty receipt file",
                "The uploaded file is empty.");
        }
        if (file.getSize() > MAX_RECEIPT_BYTES) {
            throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE,
                "validation/receipt-too-large", "Receipt too large",
                "Receipts must be at most 5 MB (got " + file.getSize() + " bytes).");
        }
        String contentType = file.getContentType();
        if (contentType == null || !ALLOWED_RECEIPT_TYPES.contains(contentType.toLowerCase())) {
            throw new ApiException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                "validation/unsupported-receipt-type",
                "Unsupported receipt type",
                "Allowed: " + String.join(", ", ALLOWED_RECEIPT_TYPES));
        }
        try {
            return service.uploadReceipt(
                id, caller, contentType, file.getSize(), file.getInputStream()
            );
        } catch (IOException e) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR,
                "server/upload-failed", "Upload failed",
                "Could not read the uploaded bytes.");
        }
    }

    @GetMapping("/expenses/{id}/receipt")
    public ReceiptUrlDto receiptUrl(
        @PathVariable UUID id,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.receiptUrl(id, caller);
    }

    // ---- comments + @mentions ----------------------------------------

    @GetMapping("/expenses/{id}/comments")
    public List<ExpenseCommentDto> listComments(
        @PathVariable UUID id,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return comments.list(id, caller);
    }

    @PostMapping("/expenses/{id}/comments")
    public ExpenseCommentDto postComment(
        @PathVariable UUID id,
        @Valid @RequestBody CreateExpenseCommentRequest body,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return comments.post(id, body, caller);
    }
}
