package ae.gov.pdd.pettycash.expense;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface ExpenseCategoryRepository extends JpaRepository<ExpenseCategory, UUID> {
    List<ExpenseCategory> findByActiveTrueOrderByCode();
    Optional<ExpenseCategory> findByCode(String code);
    boolean existsByCode(String code);
}
