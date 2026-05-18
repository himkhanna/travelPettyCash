package ae.gov.pdd.pettycash.expense.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

/**
 * Admin / Leader / Member can post a comment on any expense within a trip
 * they participate in. Mentioned users get a notification with type
 * {@code EXPENSE_QUERY} and the comment in the payload — the targeted
 * notification is the whole point of this endpoint (vs trip-wide chat).
 *
 * @param body            the comment text
 * @param mentionedUserIds explicit list of users to @mention. Mobile builds
 *                         this from the chip picker; the body may also
 *                         contain {@code @name} tokens for display, but the
 *                         notification fan-out uses this canonical list to
 *                         avoid name-parsing ambiguity.
 */
public record CreateExpenseCommentRequest(
    @NotBlank @Size(max = 2000) String body,
    List<UUID> mentionedUserIds
) {}
