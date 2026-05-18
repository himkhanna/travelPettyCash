package ae.gov.pdd.pettycash.chat;

import ae.gov.pdd.pettycash.auth.CurrentUser;
import ae.gov.pdd.pettycash.common.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.context.request.async.DeferredResult;

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
        public static MessageView from(ChatMessage m) {
            return new MessageView(m.getId(), m.getThreadId(), m.getSenderId(), m.getBody(),
                m.getSentAt(), m.getDeliveredAt(), m.getReadAt());
        }
    }

    public record SendMessageRequest(@NotBlank String body) {}

    /** Long-poll envelope. {@code serverNow} is the server's authoritative timestamp
     *  for the next poll's {@code since} param. */
    public record PollResponse(List<MessageView> items, OffsetDateTime serverNow) {}

    private static final long DEFAULT_TIMEOUT_SECONDS = 25L;
    private static final long MAX_TIMEOUT_SECONDS = 30L;

    private final ChatThreadRepository threads;
    private final ChatMessageRepository messages;
    private final CurrentUser current;
    private final ChatPublisher publisher;

    public ChatController(ChatThreadRepository threads, ChatMessageRepository messages,
                          CurrentUser current, ChatPublisher publisher) {
        this.threads = threads;
        this.messages = messages;
        this.current = current;
        this.publisher = publisher;
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

        // Fan out to any subscribers waiting on this thread. Publish on commit if TX
        // is active so a rolled-back send doesn't surface to long-pollers.
        MessageView view = MessageView.from(saved);
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    publisher.publish(threadId, view);
                }
            });
        } else {
            publisher.publish(threadId, view);
        }
        return ResponseEntity.status(HttpStatus.CREATED).body(view);
    }

    /**
     * Long-poll for new messages in a thread. See CLAUDE.md §3 — polling-first.
     *
     * <p>Returns immediately if any messages exist with {@code sentAt > since}
     * (default: now − 30s). Otherwise hangs for up to {@code timeoutSeconds}
     * (default 25, max 30) and resolves when a peer posts, or with an empty
     * list on timeout. Thread membership is enforced — non-participants get 403.
     */
    @GetMapping("/threads/{threadId}/poll")
    @PreAuthorize("isAuthenticated()")
    public DeferredResult<PollResponse> poll(@PathVariable UUID threadId,
                                             @RequestParam(required = false) OffsetDateTime since,
                                             @RequestParam(required = false) Integer timeoutSeconds) {
        ChatThread t = threads.findById(threadId).orElseThrow(
            () -> ApiException.notFound("THREAD_NOT_FOUND", "Thread " + threadId));
        if (!t.getParticipantIds().contains(current.id())) {
            throw ApiException.forbidden("FORBIDDEN", "Not a participant");
        }
        OffsetDateTime now = OffsetDateTime.now();
        OffsetDateTime sinceTs = since != null ? since : now.minusSeconds(30);
        long timeout = timeoutSeconds == null
            ? DEFAULT_TIMEOUT_SECONDS
            : Math.max(1L, Math.min(timeoutSeconds.longValue(), MAX_TIMEOUT_SECONDS));

        DeferredResult<PollResponse> dr = new DeferredResult<>(timeout * 1000L);

        List<MessageView> backlog = messages
            .findByThreadIdAndSentAtAfterOrderBySentAtAsc(threadId, sinceTs)
            .stream().map(MessageView::from).toList();
        if (!backlog.isEmpty()) {
            dr.setResult(new PollResponse(backlog, OffsetDateTime.now()));
            return dr;
        }

        // See NotificationController.poll() for the rationale — the outer DR owns the
        // request timer; the inner DR is a no-timer relay resolved by the publisher.
        dr.onTimeout(() -> dr.setResult(new PollResponse(List.of(), OffsetDateTime.now())));
        DeferredResult<List<MessageView>> inner = new DeferredResult<>();
        inner.setResultHandler(result -> {
            if (dr.isSetOrExpired()) return;
            if (result instanceof List<?> list) {
                @SuppressWarnings("unchecked")
                List<MessageView> items = (List<MessageView>) list;
                dr.setResult(new PollResponse(items, OffsetDateTime.now()));
            }
        });
        inner.onError(t2 -> {
            if (!dr.isSetOrExpired()) dr.setErrorResult(t2);
        });

        publisher.subscribe(threadId, inner);
        return dr;
    }
}
