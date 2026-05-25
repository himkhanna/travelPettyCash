package ae.gov.pdd.pettycash.chat;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.chat.dto.ChatMessageDto;
import ae.gov.pdd.pettycash.chat.dto.ChatThreadDto;
import ae.gov.pdd.pettycash.chat.dto.SendMessageRequest;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.notification.NotificationRefType;
import ae.gov.pdd.pettycash.notification.NotificationService;
import ae.gov.pdd.pettycash.notification.NotificationType;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@Service
public class ChatService {

    private final ChatThreadRepository threads;
    private final ChatThreadMemberRepository members;
    private final ChatMessageRepository messages;
    private final TripRepository trips;
    private final NotificationService notifications;
    private final Clock clock;

    @Autowired
    public ChatService(
        ChatThreadRepository threads,
        ChatThreadMemberRepository members,
        ChatMessageRepository messages,
        TripRepository trips,
        NotificationService notifications
    ) {
        this(threads, members, messages, trips, notifications, Clock.systemUTC());
    }

    ChatService(
        ChatThreadRepository threads,
        ChatThreadMemberRepository members,
        ChatMessageRepository messages,
        TripRepository trips,
        NotificationService notifications,
        Clock clock
    ) {
        this.threads = threads;
        this.members = members;
        this.messages = messages;
        this.trips = trips;
        this.notifications = notifications;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<ChatThreadDto> listForTrip(UUID tripId, AuthenticatedUser caller) {
        return threads.findForTripAndMember(tripId, caller.userId()).stream()
            .map(t -> toDto(t, caller.userId()))
            .toList();
    }

    @Transactional(readOnly = true)
    public List<ChatThreadDto> listForUser(AuthenticatedUser caller) {
        return threads.findForMember(caller.userId()).stream()
            .map(t -> toDto(t, caller.userId()))
            .toList();
    }

    // -----------------------------------------------------------------
    // Team thread — one canonical group chat per trip containing the
    // leader + all members. Created on demand so existing trips (seeded
    // before this feature landed) self-heal on first access.
    // -----------------------------------------------------------------

    /**
     * Find-or-create the team thread for a trip and return the DTO. Caller
     * must be a trip participant OR admin/super-admin.
     */
    @Transactional
    public ChatThreadDto ensureAndGetTeamThread(UUID tripId, AuthenticatedUser caller) {
        Trip trip = trips.findById(tripId).orElseThrow(() -> new ApiException(
            HttpStatus.NOT_FOUND, "trips/not-found", "Trip not found",
            "No trip with id " + tripId + "."
        ));
        boolean isAdmin = caller.role() == UserRole.ADMIN
            || caller.role() == UserRole.SUPER_ADMIN;
        boolean isParticipant = trip.getLeaderId().equals(caller.userId())
            || trip.getMemberIds().contains(caller.userId());
        if (!isAdmin && !isParticipant) {
            throw new ApiException(
                HttpStatus.NOT_FOUND, "trips/not-found", "Trip not found",
                "No trip with id " + tripId + " is accessible to this user."
            );
        }
        ChatThread thread = ensureTeamThread(trip);
        return toDto(thread, caller.userId());
    }

    /**
     * Called from TripService.create + TripService.update to keep the team
     * thread's participant set in sync with the trip's leader + memberIds.
     * Idempotent: creates the thread if missing, updates participants if
     * present.
     */
    @Transactional
    public ChatThread ensureTeamThread(Trip trip) {
        UUID id = teamThreadId(trip.getId());
        Set<UUID> participants = new LinkedHashSet<>();
        participants.add(trip.getLeaderId());
        participants.addAll(trip.getMemberIds());

        ChatThread existing = threads.findById(id).orElse(null);
        if (existing == null) {
            ChatThread row = new ChatThread(
                id,
                trip.getId(),
                "Team chat",
                "محادثة الفريق",
                participants
            );
            return threads.save(row);
        }
        if (!existing.getParticipantIds().equals(participants)) {
            existing.replaceParticipants(participants);
        }
        return existing;
    }

    /**
     * Deterministic ID derived from the trip id so the team thread can be
     * looked up without a flag column. Trip → exactly one team thread,
     * forever.
     */
    private static UUID teamThreadId(UUID tripId) {
        return UUID.nameUUIDFromBytes(
            ("team-thread:" + tripId).getBytes(StandardCharsets.UTF_8)
        );
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

        fanOutMessageNotifications(thread, caller, req.body());

        return ChatMessageDto.from(msg, now);
    }

    /**
     * Drop a CHAT_MESSAGE notification on every participant other than the
     * sender so the recipient sees a row in their inbox + a chip on the home
     * activity feed. We don't dedupe across multiple messages in the same
     * thread — the inbox view collapses by ref on the mobile side.
     */
    private void fanOutMessageNotifications(
        ChatThread thread, AuthenticatedUser sender, String body
    ) {
        Set<UUID> recipients = new LinkedHashSet<>(thread.getParticipantIds());
        recipients.remove(sender.userId());
        if (recipients.isEmpty()) return;

        String tripName = trips.findById(thread.getTripId())
            .map(Trip::getName)
            .orElse("");
        String snippet = body == null ? ""
            : body.length() > 140 ? body.substring(0, 137) + "…" : body;

        Map<String, Object> payload = new HashMap<>();
        payload.put("threadId", thread.getId().toString());
        payload.put("tripId", thread.getTripId().toString());
        payload.put("tripName", tripName);
        payload.put("senderId", sender.userId().toString());
        payload.put("snippet", snippet);

        notifications.fanOut(
            NotificationType.CHAT_MESSAGE,
            false,
            NotificationRefType.CHAT_THREAD,
            thread.getId(),
            payload,
            recipients
        );
    }

    @Transactional
    public void markRead(UUID threadId, AuthenticatedUser caller) {
        ChatThread thread = loadAccessibleThread(threadId, caller);
        ChatThreadMember mem = members
            .findByThreadIdAndUserId(thread.getId(), caller.userId())
            .orElseGet(() -> members.save(new ChatThreadMember(thread.getId(), caller.userId())));
        mem.markRead(clock.instant());
        // Also flip any UNREAD CHAT_MESSAGE notifications this caller has
        // for this thread to READ so the inbox/home activity counters
        // don't keep showing dots after the user has opened the thread.
        notifications.markReadByUserAndRef(
            caller.userId(), NotificationRefType.CHAT_THREAD, thread.getId()
        );
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
