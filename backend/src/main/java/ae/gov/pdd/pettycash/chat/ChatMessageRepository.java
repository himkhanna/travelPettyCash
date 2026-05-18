package ae.gov.pdd.pettycash.chat;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

public interface ChatMessageRepository extends JpaRepository<ChatMessage, UUID> {
    List<ChatMessage> findByThreadIdOrderBySentAtDesc(UUID threadId);

    /** Used by chat long-poll: messages strictly newer than {@code since}. */
    List<ChatMessage> findByThreadIdAndSentAtAfterOrderBySentAtAsc(UUID threadId, OffsetDateTime since);
}
