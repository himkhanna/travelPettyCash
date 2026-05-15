package ae.gov.pdd.pettycash.fund;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AllocationRepository extends JpaRepository<Allocation, UUID> {
    List<Allocation> findByTripIdOrderByCreatedAtAsc(UUID tripId);
    List<Allocation> findByTripIdAndToUserIdOrderByCreatedAtAsc(UUID tripId, UUID toUserId);
}
