package ae.gov.pdd.pettycash.chat;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ChatThreadRepository extends JpaRepository<ChatThread, UUID> {
    List<ChatThread> findByTripId(UUID tripId);
    List<ChatThread> findByParticipantIdsContaining(UUID userId);
}
