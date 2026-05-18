package ae.gov.pdd.pettycash.expense;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ExpenseCommentRepository extends JpaRepository<ExpenseComment, UUID> {

    List<ExpenseComment> findByExpenseIdAndDeletedAtIsNullOrderByCreatedAtAsc(UUID expenseId);
}
