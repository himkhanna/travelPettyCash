package ae.gov.pdd.pettycash.chat;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface ChatThreadRepository extends JpaRepository<ChatThread, UUID> {

    /**
     * Threads in this trip the caller participates in, newest activity first.
     */
    @Query("""
        SELECT DISTINCT t
          FROM ChatThread t
          JOIN t.participantIds p
         WHERE t.tripId = :tripId
           AND p        = :userId
         ORDER BY t.lastMessageAt DESC NULLS LAST, t.createdAt DESC
        """)
    List<ChatThread> findForTripAndMember(
        @Param("tripId") UUID tripId,
        @Param("userId") UUID userId
    );

    /**
     * Every thread the caller participates in across all trips, newest first.
     * Backs the global Chat screen reached from Profile.
     */
    @Query("""
        SELECT DISTINCT t
          FROM ChatThread t
          JOIN t.participantIds p
         WHERE p = :userId
         ORDER BY t.lastMessageAt DESC NULLS LAST, t.createdAt DESC
        """)
    List<ChatThread> findForMember(@Param("userId") UUID userId);
}
