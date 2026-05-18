package ae.gov.pdd.pettycash.expense;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

public interface ExpenseRepository extends JpaRepository<Expense, UUID> {
    List<Expense> findByTripId(UUID tripId);
    List<Expense> findByTripIdAndUserId(UUID tripId, UUID userId);

    /**
     * First page of expenses for a trip, ordered by (occurredAt DESC, id DESC).
     * Used when no cursor is supplied. Backed by {@code idx_expense_trip_occurredat_id}
     * (Flyway V005). Pageable.limit() must be set.
     */
    @Query("""
        SELECT e FROM Expense e
        WHERE e.tripId = :tripId
        ORDER BY e.occurredAt DESC, e.id DESC
        """)
    List<Expense> findFirstPageByTripId(@Param("tripId") UUID tripId, Pageable pageable);

    /**
     * Continuation page after the supplied (cutOccurredAt, cutId) cursor.
     * Tuple comparison: a row is "after" the cursor iff
     * {@code occurredAt &lt; cutOccurredAt OR (occurredAt = cutOccurredAt AND id &lt; cutId)}.
     * Same ordering as the first-page query so the cursor walk is stable.
     */
    @Query("""
        SELECT e FROM Expense e
        WHERE e.tripId = :tripId
          AND (e.occurredAt < :cutOccurredAt
               OR (e.occurredAt = :cutOccurredAt AND e.id < :cutId))
        ORDER BY e.occurredAt DESC, e.id DESC
        """)
    List<Expense> findPageByTripId(@Param("tripId") UUID tripId,
                                   @Param("cutOccurredAt") OffsetDateTime cutOccurredAt,
                                   @Param("cutId") UUID cutId,
                                   Pageable pageable);

    @Query("""
        SELECT e FROM Expense e
        WHERE e.tripId = :tripId AND e.userId = :userId
        ORDER BY e.occurredAt DESC, e.id DESC
        """)
    List<Expense> findFirstPageByTripIdAndUserId(@Param("tripId") UUID tripId,
                                                 @Param("userId") UUID userId,
                                                 Pageable pageable);

    @Query("""
        SELECT e FROM Expense e
        WHERE e.tripId = :tripId AND e.userId = :userId
          AND (e.occurredAt < :cutOccurredAt
               OR (e.occurredAt = :cutOccurredAt AND e.id < :cutId))
        ORDER BY e.occurredAt DESC, e.id DESC
        """)
    List<Expense> findPageByTripIdAndUserId(@Param("tripId") UUID tripId,
                                            @Param("userId") UUID userId,
                                            @Param("cutOccurredAt") OffsetDateTime cutOccurredAt,
                                            @Param("cutId") UUID cutId,
                                            Pageable pageable);
}
