package ae.gov.pdd.pettycash.chat;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.chat.dto.ChatMessageDto;
import ae.gov.pdd.pettycash.chat.dto.ChatThreadDto;
import ae.gov.pdd.pettycash.chat.dto.SendMessageRequest;
import ae.gov.pdd.pettycash.common.error.ApiException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
public class ChatService {

    private final ChatThreadRepository threads;
    private final ChatThreadMemberRepository members;
    private final ChatMessageRepository messages;
    private final Clock clock;

    @Autowired
    public ChatService(
        ChatThreadRepository threads,
        ChatThreadMemberRepository members,
        ChatMessageRepository messages
    ) {
        this(threads, members, messages, Clock.systemUTC());
    }

    ChatService(
        ChatThreadRepository threads,
        ChatThreadMemberRepository members,
        ChatMessageRepository messages,
        Clock clock
    ) {
        this.threads = threads;
        this.members = members;
        this.messages = messages;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<ChatThreadDto> listForTrip(UUID tripId, AuthenticatedUser caller) {
        return threads.findForTripAndMember(tripId, caller.userId()).stream()
            .map(t -> toDto(t, caller.userId()))
            .toList();
    }

    @Transactional(readOnly = true)
    public List<ChatMessageDto> listMessages(UUID threadId, AuthenticatedUser caller) {
        requireMembership(threadId, caller);
        return messages.findByThreadIdOrderBySentAtAsc(threadId).stream()
            .map(m -> ChatMessageDto.from(m, null))
            .toList();
    }

    @Transactional
    public ChatMessageDto send(
        UUID threadId,
        SendMessageRequest req,
        AuthenticatedUser caller
    ) {
        ChatThread thread = loadAccessibleThread(threadId, caller);
        Instant now = clock.instant();
        ChatMessage msg = new ChatMessage(
            UUID.randomUUID(), thread.getId(), caller.userId(), req.body()
        );
        messages.save(msg);
        thread.touch(req.body(), now);

        // Sender's own membership is up to date on their last_read_at — they
        // can't have an unread for a message they just sent.
        ChatThreadMember mem = members.findByThreadIdAndUserId(threadId, caller.userId())
            .orElseGet(() -> members.save(new ChatThreadMember(threadId, caller.userId())));
        mem.markRead(now);

        return ChatMessageDto.from(msg, now);
    }

    @Transactional
    public void markRead(UUID threadId, AuthenticatedUser caller) {
        ChatThread thread = loadAccessibleThread(threadId, caller);
        ChatThreadMember mem = members
            .findByThreadIdAndUserId(thread.getId(), caller.userId())
            .orElseGet(() -> members.save(new ChatThreadMember(thread.getId(), caller.userId())));
        mem.markRead(clock.instant());
    }

    // ---- helpers ------------------------------------------------------

    private ChatThread loadAccessibleThread(UUID threadId, AuthenticatedUser caller) {
        ChatThread t = threads.findById(threadId).orElseThrow(this::notFound);
        if (!t.getParticipantIds().contains(caller.userId())) {
            // 404 not 403 — don't leak that the thread exists.
            throw notFound();
        }
        return t;
    }

    private void requireMembership(UUID threadId, AuthenticatedUser caller) {
        loadAccessibleThread(threadId, caller);
    }

    private ChatThreadDto toDto(ChatThread t, UUID viewerId) {
        Instant lastRead = members
            .findByThreadIdAndUserId(t.getId(), viewerId)
            .map(ChatThreadMember::getLastReadAt)
            .orElse(null);
        long unread = lastRead == null
            ? messages.countByThreadIdAndSentAtAfter(t.getId(), Instant.EPOCH)
            : messages.countByThreadIdAndSentAtAfter(t.getId(), lastRead);
        return new ChatThreadDto(
            t.getId(),
            t.getTripId(),
            t.getTitle(),
            t.getTitleAr(),
            t.getParticipantIds().stream().sorted().toList(),
            (int) unread,
            t.getLastMessagePreview(),
            t.getLastMessageAt()
        );
    }

    private ApiException notFound() {
        return new ApiException(
            HttpStatus.NOT_FOUND,
            "chat/thread-not-found",
            "Thread not found",
            "No thread with that id is accessible to this user."
        );
    }
}
