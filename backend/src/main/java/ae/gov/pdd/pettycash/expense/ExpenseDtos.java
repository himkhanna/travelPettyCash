package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.common.MoneyDto;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.time.OffsetDateTime;

public final class ExpenseDtos {
    private ExpenseDtos() {}

    public record ExpenseView(
            String id,
            String tripId,
            String userId,
            String sourceId,
            String categoryCode,
            MoneyDto amount,
            int quantity,
            String details,
            OffsetDateTime occurredAt,
            String receiptObjectKey
    ) {
        public static ExpenseView of(ExpenseEntity e) {
            return new ExpenseView(
                    e.getId(), e.getTripId(), e.getUserId(), e.getSourceId(),
                    e.getCategoryCode(),
                    new MoneyDto(e.getAmountMinor(), e.getCurrency()),
                    e.getQuantity(), e.getDetails(), e.getOccurredAt(),
                    e.getReceiptObjectKey()
            );
        }
    }

    public record CreateExpenseRequest(
            String id, // optional, allow client-generated UUIDs from offline queue
            @NotBlank String userId,
            @NotBlank String sourceId,
            @NotBlank String categoryCode,
            @NotNull MoneyDto amount,
            @Positive int quantity,
            String details,
            @NotNull OffsetDateTime occurredAt,
            String receiptObjectKey
    ) {}

    public record PatchExpenseRequest(
            String sourceId,
            String categoryCode,
            MoneyDto amount,
            Integer quantity,
            String details,
            OffsetDateTime occurredAt
    ) {}
}
