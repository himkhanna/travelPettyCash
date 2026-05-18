package ae.gov.pdd.pettycash.expense;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ExpenseRepository extends JpaRepository<Expense, UUID> {
    List<Expense> findByTripId(UUID tripId);
    List<Expense> findByTripIdAndUserId(UUID tripId, UUID userId);
}
