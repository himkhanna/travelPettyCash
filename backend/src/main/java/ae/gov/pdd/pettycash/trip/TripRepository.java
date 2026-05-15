package ae.gov.pdd.pettycash.trip;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface TripRepository extends JpaRepository<Trip, UUID> {

    /**
     * All trips the user participates in (as leader, member, or — for admins
     * who created them — as creator). Status filter is optional; passing
     * {@code null} returns trips regardless of status.
     */
    @Query("""
        SELECT DISTINCT t
          FROM Trip t
          LEFT JOIN t.memberIds m
         WHERE (:status IS NULL OR t.status = :status)
           AND (
                t.leaderId    = :userId
             OR t.createdById = :userId
             OR m             = :userId
           )
         ORDER BY t.createdAt DESC
        """)
    List<Trip> findForUser(
        @Param("userId") UUID userId,
        @Param("status") TripStatus status
    );

    /** Admin/SuperAdmin: list of all trips, optionally filtered by status. */
    @Query("""
        SELECT t FROM Trip t
         WHERE (:status IS NULL OR t.status = :status)
         ORDER BY t.createdAt DESC
        """)
    List<Trip> findAllFiltered(@Param("status") TripStatus status);
}
