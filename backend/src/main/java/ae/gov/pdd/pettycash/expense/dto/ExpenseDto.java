package ae.gov.pdd.pettycash.expense.dto;

import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.expense.Expense;

import java.time.Instant;
import java.util.UUID;

public record ExpenseDto(
    UUID id,
    UUID tripId,
    UUID userId,
    UUID sourceId,
    String categoryCode,
    MoneyDto amount,
    int quantity,
    String details,
    Instant occurredAt,
    String receiptObjectKey,
    Instant createdAt,
    Instant updatedAt
) {
    public static ExpenseDto from(Expense e) {
        return new ExpenseDto(
            e.getId(),
            e.getTripId(),
            e.getUserId(),
            e.getSourceId(),
            e.getCategoryCode(),
            MoneyDto.from(new Money(e.getAmountMinor(), e.getCurrency())),
            e.getQuantity(),
            e.getDetails(),
            e.getOccurredAt(),
            e.getReceiptObjectKey(),
            e.getCreatedAt(),
            e.getUpdatedAt()
        );
    }
}
