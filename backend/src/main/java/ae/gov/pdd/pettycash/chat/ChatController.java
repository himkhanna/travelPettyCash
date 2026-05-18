package ae.gov.pdd.pettycash.chat;

import ae.gov.pdd.pettycash.auth.CurrentUser;
import ae.gov.pdd.pettycash.common.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Chat REST API — see CLAUDE.md §15: no real-time presence / typing indicators; polling only.
 */
@RestController
@RequestMapping("/api/v1/chat")
public class ChatController {

    public record ThreadView(
        UUID id, UUID tripId, String title, String titleAr, Set<UUID> participantIds,
        int unreadCount, String lastMessagePreview, OffsetDateTime lastMessageAt
    ) {
        static ThreadView from(ChatThread t) {
            return new ThreadView(t.getId(), t.getTripId(), t.getTitle(), t.getTitleAr(),
                t.getParticipantIds(), 0, t.getLastMessagePreview(), t.getLastMessageAt());
        }
    }

    public record MessageView(UUID id, UUID threadId, UUID senderId, String body,
                              OffsetDateTime sentAt, OffsetDateTime deliveredAt, OffsetDateTime readAt) {
        static MessageView from(ChatMessage m) {
            return new MessageView(m.getId(), m.getThreadId(), m.getSenderId(), m.getBody(),
                m.getSentAt(), m.getDeliveredAt(), m.getReadAt());
        }
    }

    public record SendMessageRequest(@NotBlank String body) {}

    private final ChatThreadRepository threads;
    private final ChatMessageRepository messages;
    private final CurrentUser current;

    public ChatController(ChatThreadRepository threads, ChatMessageRepository messages, CurrentUser current) {
        this.threads = threads;
        this.messages = messages;
        this.current = current;
    }

    @GetMapping("/threads")
    public List<ThreadView> listThreads(@RequestParam(required = false) UUID tripId) {
        var all = tripId == null
            ? threads.findByParticipantIdsContaining(current.id())
            : threads.findByTripId(tripId);
        return all.stream().map(ThreadView::from).toList();
    }

    @GetMapping("/threads/{threadId}/messages")
    public List<MessageView> listMessages(@PathVariable UUID threadId) {
        ChatThread t = threads.findById(threadId).orElseThrow(
            () -> ApiException.notFound("THREAD_NOT_FOUND", "Thread " + threadId));
        if (!t.getParticipantIds().contains(current.id())) {
            throw ApiException.forbidden("FORBIDDEN", "Not a participant");
        }
        return messages.findByThreadIdOrderBySentAtDesc(threadId).stream()
            .map(MessageView::from).toList();
    }

    @PostMapping("/threads/{threadId}/messages")
    public ResponseEntity<MessageView> send(@PathVariable UUID threadId,
                                            @Valid @RequestBody SendMessageRequest req) {
        ChatThread t = threads.findById(threadId).orElseThrow(
            () -> ApiException.notFound("THREAD_NOT_FOUND", "Thread " + threadId));
        if (!t.getParticipantIds().contains(current.id())) {
            throw ApiException.forbidden("FORBIDDEN", "Not a participant");
        }
        ChatMessage m = new ChatMessage();
        m.setId(UUID.randomUUID());
        m.setThreadId(threadId);
        m.setSenderId(current.id());
        m.setBody(req.body());
        m.setSentAt(OffsetDateTime.now());
        ChatMessage saved = messages.save(m);
        t.setLastMessagePreview(req.body().length() > 200 ? req.body().substring(0, 200) : req.body());
        t.setLastMessageAt(saved.getSentAt());
        threads.save(t);
        return ResponseEntity.status(HttpStatus.CREATED).body(MessageView.from(saved));
    }
}
