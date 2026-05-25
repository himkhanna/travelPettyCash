package ae.gov.pdd.pettycash.chat;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.chat.dto.ChatMessageDto;
import ae.gov.pdd.pettycash.chat.dto.ChatThreadDto;
import ae.gov.pdd.pettycash.chat.dto.SendMessageRequest;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class ChatController {

    private final ChatService service;

    public ChatController(ChatService service) {
        this.service = service;
    }

    @GetMapping("/trips/{tripId}/chat/threads")
    public List<ChatThreadDto> listThreads(
        @PathVariable UUID tripId,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.listForTrip(tripId, caller);
    }

    /**
     * Returns the trip's "team chat" thread — one canonical group per trip
     * with leader + all members as participants. Created lazily so existing
     * trips work without a backfill migration.
     */
    @GetMapping("/trips/{tripId}/chat/team")
    public ChatThreadDto teamThread(
        @PathVariable UUID tripId,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.ensureAndGetTeamThread(tripId, caller);
    }

    @GetMapping("/chat/threads")
    public List<ChatThreadDto> listThreadsForUser(
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.listForUser(caller);
    }

    @GetMapping("/chat/threads/{threadId}/messages")
    public List<ChatMessageDto> listMessages(
        @PathVariable UUID threadId,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.listMessages(threadId, caller);
    }

    @PostMapping("/chat/threads/{threadId}/messages")
    public ChatMessageDto send(
        @PathVariable UUID threadId,
        @Valid @RequestBody SendMessageRequest body,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.send(threadId, body, caller);
    }

    @PatchMapping("/chat/threads/{threadId}/read")
    public void markRead(
        @PathVariable UUID threadId,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        service.markRead(threadId, caller);
    }
}
