package ae.gov.pdd.pettycash.notification;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.notification.dto.NotificationDto;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class NotificationController {

    private final NotificationService service;

    public NotificationController(NotificationService service) {
        this.service = service;
    }

    @GetMapping("/notifications")
    public List<NotificationDto> list(@AuthenticationPrincipal AuthenticatedUser caller) {
        return service.listForCaller(caller);
    }

    @GetMapping("/notifications/unread-count")
    public UnreadCount unread(@AuthenticationPrincipal AuthenticatedUser caller) {
        return new UnreadCount(service.unreadCount(caller));
    }

    @PatchMapping("/notifications/{id}/read")
    public NotificationDto markRead(
        @PathVariable UUID id,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.markRead(id, caller);
    }

    public record UnreadCount(long count) {}
}
