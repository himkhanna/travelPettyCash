package ae.gov.pdd.pettycash.notification;

import ae.gov.pdd.pettycash.auth.CurrentUser;
import ae.gov.pdd.pettycash.common.ApiException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.context.request.async.DeferredResult;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationController {

    public record NotificationView(
        UUID id, UUID userId, NotificationType type, Map<String, Object> payload,
        boolean actionable, NotificationState state, OffsetDateTime createdAt
    ) {
        public static NotificationView from(Notification n) {
            return new NotificationView(n.getId(), n.getUserId(), n.getType(), n.getPayload(),
                n.isActionable(), n.getState(), n.getCreatedAt());
        }
    }

    /**
     * Long-poll response envelope. {@code serverNow} is the server-side timestamp
     * the client should send as {@code since} on the next poll — this avoids
     * client clock skew bouncing the window.
     */
    public record PollResponse(List<NotificationView> items, OffsetDateTime serverNow) {}

    /** Long-poll bounds. See CLAUDE.md §3 (polling-first). */
    private static final long DEFAULT_TIMEOUT_SECONDS = 25L;
    private static final long MAX_TIMEOUT_SECONDS = 30L;

    private final NotificationRepository repo;
    private final NotificationPublisher publisher;
    private final CurrentUser current;

    public NotificationController(NotificationRepository repo, NotificationPublisher publisher,
                                  CurrentUser current) {
        this.repo = repo;
        this.publisher = publisher;
        this.current = current;
    }

    @GetMapping
    public List<NotificationView> list(@RequestParam(required = false) String cursor,
                                       @RequestParam(required = false, defaultValue = "30") int limit) {
        return repo.findByUserIdOrderByCreatedAtDesc(current.id()).stream()
            .map(NotificationView::from).toList();
    }

    /**
     * Long-poll for new notifications. See CLAUDE.md §3 — polling-first transport.
     *
     * <p>Returns immediately with any notifications {@code createdAt > since}
     * (default: now − 30s if {@code since} is omitted). When the result set is
     * empty, the request hangs as a {@link DeferredResult} for up to
     * {@code timeoutSeconds} (default 25, capped at 30) and resolves when a new
     * notification is published to the current user, or with an empty list on
     * timeout. Either way the client should send back {@code serverNow} as the
     * next {@code since}.
     */
    @GetMapping("/poll")
    @PreAuthorize("isAuthenticated()")
    public DeferredResult<PollResponse> poll(
            @RequestParam(required = false) OffsetDateTime since,
            @RequestParam(required = false) Integer timeoutSeconds) {
        OffsetDateTime now = OffsetDateTime.now();
        OffsetDateTime sinceTs = since != null ? since : now.minusSeconds(30);
        long timeout = timeoutSeconds == null
            ? DEFAULT_TIMEOUT_SECONDS
            : Math.max(1L, Math.min(timeoutSeconds.longValue(), MAX_TIMEOUT_SECONDS));

        UUID userId = current.id();
        DeferredResult<PollResponse> dr = new DeferredResult<>(timeout * 1000L);

        // Fast path: any backlog since the supplied window? Return immediately.
        List<NotificationView> backlog = repo
            .findByUserIdAndCreatedAtAfterOrderByCreatedAtAsc(userId, sinceTs)
            .stream().map(NotificationView::from).toList();
        if (!backlog.isEmpty()) {
            dr.setResult(new PollResponse(backlog, OffsetDateTime.now()));
            return dr;
        }

        // Empty-list fallback on outer timeout. The outer DeferredResult owns the
        // request timer; inner is a no-timer relay that publish() resolves.
        dr.onTimeout(() -> dr.setResult(new PollResponse(List.of(), OffsetDateTime.now())));
        // Inner has no timeout (the outer one bounds the wait). When the publisher
        // fires, forward the items to the outer dr if it's still pending.
        DeferredResult<List<NotificationView>> inner = new DeferredResult<>();
        inner.setResultHandler(result -> {
            if (dr.isSetOrExpired()) return;
            if (result instanceof List<?> list) {
                @SuppressWarnings("unchecked")
                List<NotificationView> items = (List<NotificationView>) list;
                dr.setResult(new PollResponse(items, OffsetDateTime.now()));
            }
        });
        inner.onError(t -> {
            if (!dr.isSetOrExpired()) dr.setErrorResult(t);
        });

        publisher.subscribe(userId, inner);
        return dr;
    }

    @PatchMapping("/{id}/read")
    public NotificationView markRead(@PathVariable UUID id) {
        Notification n = repo.findById(id).orElseThrow(
            () -> ApiException.notFound("NOTIFICATION_NOT_FOUND", "Notification " + id));
        if (!n.getUserId().equals(current.id())) {
            throw ApiException.forbidden("FORBIDDEN", "Not your notification");
        }
        if (n.getState() == NotificationState.UNREAD) n.setState(NotificationState.READ);
        return NotificationView.from(repo.save(n));
    }
}
