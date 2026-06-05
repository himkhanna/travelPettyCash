package ae.gov.pdd.pettycash.expense.dto;

import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.expense.Expense;

import java.math.BigDecimal;
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
    Instant updatedAt,
    // Currency conversion (ADR-003) — present only when the expense was spent
    // in a foreign currency. `amount` above is the trip-currency base value.
    MoneyDto originalAmount,
    BigDecimal exchangeRate
) {
    public static ExpenseDto from(Expense e) {
        final MoneyDto original =
            (e.getOriginalCurrency() != null && e.getOriginalAmountMinor() != null)
                ? MoneyDto.from(new Money(e.getOriginalAmountMinor(), e.getOriginalCurrency()))
                : null;
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
            e.getUpdatedAt(),
            original,
            e.getExchangeRate()
        );
    }
}
