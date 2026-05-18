package ae.gov.pdd.pettycash.expense.dto;

import ae.gov.pdd.pettycash.expense.ExpenseComment;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record ExpenseCommentDto(
    UUID id,
    UUID expenseId,
    UUID authorId,
    String body,
    List<UUID> mentionedUserIds,
    Instant createdAt
) {
    public static ExpenseCommentDto from(ExpenseComment c) {
        return new ExpenseCommentDto(
            c.getId(),
            c.getExpenseId(),
            c.getAuthorId(),
            c.getBody(),
            List.copyOf(c.getMentionedUserIds()),
            c.getCreatedAt()
        );
    }
}
