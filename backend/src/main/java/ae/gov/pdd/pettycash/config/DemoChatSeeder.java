package ae.gov.pdd.pettycash.config;

import ae.gov.pdd.pettycash.chat.ChatMessage;
import ae.gov.pdd.pettycash.chat.ChatMessageRepository;
import ae.gov.pdd.pettycash.chat.ChatThread;
import ae.gov.pdd.pettycash.chat.ChatThreadRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.lang.reflect.Field;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static ae.gov.pdd.pettycash.config.DemoPersonas.AHMED;
import static ae.gov.pdd.pettycash.config.DemoPersonas.FATIMA;
import static ae.gov.pdd.pettycash.config.DemoPersonas.LAYLA;
import static ae.gov.pdd.pettycash.config.DemoPersonas.MOHAMMED;

/**
 * Seeds the four demo chat threads from
 * {@code mobile/assets/demo/chat_threads.json} + the five messages from
 * {@code chat_messages.json}. Runs after the trip seeder.
 */
@Component
@Order(50)
@ConditionalOnProperty(name = "pdd.demo.seed", havingValue = "true")
public class DemoChatSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DemoChatSeeder.class);

    private static final UUID KSA_TRIP =
        UUID.fromString("00000000-0000-0000-0002-000000005a01");
    private static final UUID EGY_TRIP =
        UUID.fromString("00000000-0000-0000-0002-0000000e9201");

    private final ChatThreadRepository threads;
    private final ChatMessageRepository messages;

    public DemoChatSeeder(
        ChatThreadRepository threads,
        ChatMessageRepository messages
    ) {
        this.threads = threads;
        this.messages = messages;
    }

    private static UUID thread(int n) {
        return UUID.fromString("00000000-0000-0000-0004-%012x".formatted(n));
    }

    private static UUID msg(int n) {
        return UUID.fromString("00000000-0000-0000-0005-%012x".formatted(n));
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        int seededThreads = 0;
        int seededMessages = 0;

        for (ThreadSeed t : THREAD_SEEDS) {
            if (threads.existsById(t.id())) continue;
            ChatThread row = new ChatThread(t.id(), t.tripId(), t.title(),
                t.titleAr(), t.participants());
            backdate(row, "createdAt", t.lastMessageAt());
            row.touch(t.lastMessagePreview(), t.lastMessageAt());
            threads.save(row);
            seededThreads++;
        }

        for (MessageSeed m : MESSAGE_SEEDS) {
            if (messages.existsById(m.id())) continue;
            ChatMessage row = new ChatMessage(m.id(), m.threadId(), m.senderId(), m.body());
            backdate(row, "sentAt", m.sentAt());
            backdate(row, "deliveredAt", m.sentAt());
            messages.save(row);
            seededMessages++;
        }

        log.info("DemoChatSeeder seeded {} thread(s) + {} message(s).",
            seededThreads, seededMessages);
    }

    private static void backdate(Object entity, String field, Instant value) {
        if (value == null) return;
        try {
            Field f = entity.getClass().getDeclaredField(field);
            f.setAccessible(true);
            f.set(entity, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException("Failed to backdate " + field, e);
        }
    }

    private record ThreadSeed(
        UUID id, UUID tripId,
        String title, String titleAr,
        Set<UUID> participants,
        String lastMessagePreview,
        Instant lastMessageAt
    ) {}

    private record MessageSeed(
        UUID id, UUID threadId, UUID senderId, String body, Instant sentAt
    ) {}

    private static final List<ThreadSeed> THREAD_SEEDS = List.of(
        new ThreadSeed(
            thread(1), KSA_TRIP,
            "KSA Delegation Team", "فريق وفد السعودية",
            Set.of(FATIMA.id(), AHMED.id(), MOHAMMED.id(), LAYLA.id()),
            "Confirmed pickup at 7am",
            Instant.parse("2026-05-13T03:45:00Z")
        ),
        new ThreadSeed(
            thread(2), KSA_TRIP,
            "Ahmed Al Maktoum", "أحمد آل مكتوم",
            Set.of(FATIMA.id(), AHMED.id()),
            "Can you forward the receipt?",
            Instant.parse("2026-05-12T14:00:00Z")
        ),
        new ThreadSeed(
            thread(3), KSA_TRIP,
            "Mohammed Ali", "محمد علي",
            Set.of(FATIMA.id(), MOHAMMED.id()),
            "Thanks!",
            Instant.parse("2026-05-11T06:00:00Z")
        ),
        new ThreadSeed(
            thread(4), EGY_TRIP,
            "Cairo Trip", "رحلة القاهرة",
            Set.of(FATIMA.id(), AHMED.id(), MOHAMMED.id()),
            "Meeting moved to 11",
            Instant.parse("2026-05-04T05:30:00Z")
        )
    );

    private static final List<MessageSeed> MESSAGE_SEEDS = List.of(
        new MessageSeed(msg(1), thread(1), FATIMA.id(),
            "Good morning team, breakfast at 8.",
            Instant.parse("2026-05-13T03:00:00Z")),
        new MessageSeed(msg(2), thread(1), AHMED.id(),
            "On my way.",
            Instant.parse("2026-05-13T03:10:00Z")),
        new MessageSeed(msg(3), thread(1), MOHAMMED.id(),
            "Confirmed pickup at 7am",
            Instant.parse("2026-05-13T03:45:00Z")),
        new MessageSeed(msg(4), thread(2), FATIMA.id(),
            "Can you forward the receipt?",
            Instant.parse("2026-05-12T14:00:00Z")),
        new MessageSeed(msg(5), thread(3), MOHAMMED.id(),
            "Thanks!",
            Instant.parse("2026-05-11T06:00:00Z"))
    );
}
