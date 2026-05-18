package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.common.MoneyDto;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

public final class ExpenseDtos {

    public record ExpenseView(
        UUID id, UUID tripId, UUID userId, UUID sourceId, String categoryCode,
        MoneyDto amount, int quantity, String details,
        OffsetDateTime occurredAt, OffsetDateTime createdAt, OffsetDateTime updatedAt,
        String receiptObjectKey
    ) {
        public static ExpenseView from(Expense e) {
            return new ExpenseView(e.getId(), e.getTripId(), e.getUserId(), e.getSourceId(),
                e.getCategoryCode(), MoneyDto.from(e.getAmount()), e.getQuantity(), e.getDetails(),
                e.getOccurredAt(), e.getCreatedAt(), e.getUpdatedAt(), e.getReceiptObjectKey());
        }
    }

    public record CreateExpenseRequest(
        UUID id,
        UUID sourceId,
        String categoryCode,
        MoneyDto amount,
        Integer quantity,
        String details,
        OffsetDateTime occurredAt,
        String receiptObjectKey
    ) {}

    public record ExpensePatch(
        UUID sourceId,
        String categoryCode,
        MoneyDto amount,
        String details,
        OffsetDateTime occurredAt
    ) {}

    public record SourceReassign(UUID sourceId) {}

    public record CategoryView(String code, String nameEn, String nameAr, String iconKey, boolean isActive) {
        public static CategoryView from(ExpenseCategory c) {
            return new CategoryView(c.getCode(), c.getNameEn(), c.getNameAr(), c.getIconKey(), c.isActive());
        }
    }

    public record CreateCategoryRequest(String code, String nameEn, String nameAr, String iconKey) {}

    public record ExpensePage(List<ExpenseView> items, String nextCursor) {}

    private ExpenseDtos() {}
}
