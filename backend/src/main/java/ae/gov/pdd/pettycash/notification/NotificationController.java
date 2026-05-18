package ae.gov.pdd.pettycash.notification;

import ae.gov.pdd.pettycash.auth.CurrentUser;
import ae.gov.pdd.pettycash.common.ApiException;
import org.springframework.web.bind.annotation.*;

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
        static NotificationView from(Notification n) {
            return new NotificationView(n.getId(), n.getUserId(), n.getType(), n.getPayload(),
                n.isActionable(), n.getState(), n.getCreatedAt());
        }
    }

    private final NotificationRepository repo;
    private final CurrentUser current;

    public NotificationController(NotificationRepository repo, CurrentUser current) {
        this.repo = repo;
        this.current = current;
    }

    @GetMapping
    public List<NotificationView> list(@RequestParam(required = false) String cursor,
                                       @RequestParam(required = false, defaultValue = "30") int limit) {
        return repo.findByUserIdOrderByCreatedAtDesc(current.id()).stream()
            .map(NotificationView::from).toList();
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
