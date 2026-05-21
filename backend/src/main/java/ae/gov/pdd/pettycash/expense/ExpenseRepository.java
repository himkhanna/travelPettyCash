package ae.gov.pdd.pettycash.expense;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ExpenseRepository extends JpaRepository<ExpenseEntity, String> {
    List<ExpenseEntity> findByTripIdAndDeletedAtIsNullOrderByOccurredAtDesc(String tripId);
}
