package ae.gov.pdd.pettycash.chat;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public interface ChatMessageRepository extends JpaRepository<ChatMessage, UUID> {

    List<ChatMessage> findByThreadIdOrderBySentAtAsc(UUID threadId);

    long countByThreadIdAndSentAtAfter(UUID threadId, Instant after);
}
