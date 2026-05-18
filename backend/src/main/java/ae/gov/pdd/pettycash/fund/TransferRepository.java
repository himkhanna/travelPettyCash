package ae.gov.pdd.pettycash.fund;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface TransferRepository extends JpaRepository<Transfer, UUID> {
    List<Transfer> findByTripIdOrderByCreatedAtAsc(UUID tripId);

    /** Pending transfers involving a user, either as sender or recipient. */
    @org.springframework.data.jpa.repository.Query("""
        SELECT t FROM Transfer t
         WHERE t.tripId = :tripId
           AND t.status = ae.gov.pdd.pettycash.fund.FundsStatus.PENDING
           AND (t.fromUserId = :userId OR t.toUserId = :userId)
        """)
    List<Transfer> findPendingInvolvingUser(
        @org.springframework.data.repository.query.Param("tripId") UUID tripId,
        @org.springframework.data.repository.query.Param("userId") UUID userId
    );

    /** Cascade helper for trip-delete. */
    long deleteByTripId(UUID tripId);
}
