package ae.gov.pdd.pettycash.trip;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface TripRepository extends JpaRepository<Trip, UUID> {
    List<Trip> findByStatus(TripStatus status);
    List<Trip> findByMemberIdsContaining(UUID userId);
}
