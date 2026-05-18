package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.expense.dto.CreateExpenseCommentRequest;
import ae.gov.pdd.pettycash.expense.dto.ExpenseCommentDto;
import ae.gov.pdd.pettycash.notification.NotificationRefType;
import ae.gov.pdd.pettycash.notification.NotificationService;
import ae.gov.pdd.pettycash.notification.NotificationType;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Expense-scoped comments with @mentions. Each mention fans out one
 * {@code EXPENSE_QUERY} notification to the mentioned user so they see the
 * question in their inbox; clicking it deep-links back to the expense in
 * the trip.
 *
 * <p>The author is never notified about their own comment, even if they
 * @-mention themselves (avoid inbox noise for slip-ups).
 *
 * <p>Mentioned users are also clipped to trip participants — mentioning
 * someone outside the trip is a no-op for notifications, the mention chip
 * still renders so the audit trail is preserved, but we don't leak
 * notifications to people who shouldn't see the expense.
 */
@Service
public class ExpenseCommentService {

    private final ExpenseCommentRepository comments;
    private final ExpenseService expenseService;
    private final TripRepository trips;
    private final NotificationService notifications;

    public ExpenseCommentService(
        ExpenseCommentRepository comments,
        ExpenseService expenseService,
        TripRepository trips,
        NotificationService notifications
    ) {
        this.comments = comments;
        this.expenseService = expenseService;
        this.trips = trips;
        this.notifications = notifications;
    }

    @Transactional(readOnly = true)
    public List<ExpenseCommentDto> list(UUID expenseId, AuthenticatedUser caller) {
        // Access-check by attempting to load the expense — throws 404 if
        // caller can't see it.
        expenseService.loadAccessibleExpense(expenseId, caller);
        return comments
            .findByExpenseIdAndDeletedAtIsNullOrderByCreatedAtAsc(expenseId)
            .stream()
            .map(ExpenseCommentDto::from)
            .toList();
    }

    @Transactional
    public ExpenseCommentDto post(
        UUID expenseId,
        CreateExpenseCommentRequest req,
        AuthenticatedUser caller
    ) {
        Expense expense = expenseService.loadAccessibleExpense(expenseId, caller);
        Trip trip = trips.findById(expense.getTripId())
            .orElseThrow(() -> new ApiException(
                HttpStatus.NOT_FOUND, "trips/not-found", "Trip not found",
                "Trip behind this expense no longer exists."
            ));

        Set<UUID> participantIds = new LinkedHashSet<>();
        participantIds.add(trip.getLeaderId());
        participantIds.add(trip.getCreatedById());
        participantIds.addAll(trip.getMemberIds());
        // The expense author is always a relevant recipient even if mention
        // was off — but we only fan out to *explicit* mentions to keep the
        // notification meaningful. Author-only updates are seen via the
        // comment list, not the inbox.

        Set<UUID> mentions = new LinkedHashSet<>();
        if (req.mentionedUserIds() != null) {
            for (UUID id : req.mentionedUserIds()) {
                if (id == null) continue;
                if (id.equals(caller.userId())) continue; // never self-notify
                if (participantIds.contains(id)) {
                    mentions.add(id);
                }
            }
        }

        ExpenseComment row = new ExpenseComment(
            UUID.randomUUID(),
            expense.getId(),
            caller.userId(),
            req.body().trim(),
            mentions
        );
        comments.save(row);

        if (!mentions.isEmpty()) {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("expenseId", expense.getId().toString());
            payload.put("tripId", trip.getId().toString());
            payload.put("tripName", trip.getName());
            payload.put("commentId", row.getId().toString());
            payload.put("authorId", caller.userId().toString());
            payload.put("snippet", snippet(row.getBody()));
            payload.put("amountMinor", expense.getAmountMinor());
            payload.put("currency", expense.getCurrency());
            payload.put("categoryCode", expense.getCategoryCode());

            notifications.fanOut(
                NotificationType.EXPENSE_QUERY,
                false, // not actionable — informational, click-through only
                NotificationRefType.EXPENSE,
                expense.getId(),
                payload,
                mentions
            );
        }

        return ExpenseCommentDto.from(row);
    }

    private static String snippet(String body) {
        if (body == null) return "";
        String trimmed = body.trim();
        if (trimmed.length() <= 140) return trimmed;
        return trimmed.substring(0, 137) + "…";
    }
}
