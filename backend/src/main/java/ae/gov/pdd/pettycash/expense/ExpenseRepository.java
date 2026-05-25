package ae.gov.pdd.pettycash.expense;

import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface ExpenseRepository
    extends JpaRepository<Expense, UUID>, JpaSpecificationExecutor<Expense> {

    List<Expense> findByTripIdAndDeletedAtIsNullOrderByOccurredAtDesc(UUID tripId);

    /**
     * All non-deleted expenses without an attached receipt. Backs the
     * dashboard's "Receipt triage" surface — admin reviews each, uploads on
     * behalf of the member or pings them. Limited via the controller because
     * Spring Data doesn't bind limit into derived queries.
     */
    List<Expense> findByReceiptObjectKeyIsNullAndDeletedAtIsNullOrderByOccurredAtDesc();

    /**
     * Per-day spend totals in a single currency, between [from, to]
     * inclusive. Joins through trips to filter by currency since expenses
     * store amount in minor units without their own currency column (the
     * trip owns the currency per CLAUDE.md §5). Native query for the
     * date_trunc + GROUP BY shape — JPQL can't express that cleanly across
     * dialects.
     *
     * Returns rows of {@code [java.sql.Date day, BigInteger amountMinor]}.
     */
    @Query(value = """
        SELECT date_trunc('day', e.occurred_at)::date AS day,
               COALESCE(SUM(e.amount_minor), 0)       AS total_minor
          FROM expenses e
          JOIN trips    t ON t.id = e.trip_id
         WHERE e.deleted_at IS NULL
           AND e.occurred_at >= :fromTs
           AND e.occurred_at <= :toTs
           AND t.currency    =  :currency
         GROUP BY day
         ORDER BY day
        """, nativeQuery = true)
    List<Object[]> sumByDayInCurrency(
        @Param("fromTs") Instant fromTs,
        @Param("toTs") Instant toTs,
        @Param("currency") String currency
    );

    /**
     * Filterable trip-expense listing. Each nullable arg is "no filter on
     * this dimension". {@code from} and {@code to} are inclusive bounds on
     * {@code occurredAt}.
     *
     * <p>Composed with {@link Specification} so each null filter is skipped
     * entirely rather than emitted as a typed-null parameter — Postgres
     * refuses to infer the type of a bind variable that appears only inside
     * an {@code IS NULL} check, which is why a single static {@code @Query}
     * doesn't work for this shape.
     */
    default List<Expense> search(
        UUID tripId,
        UUID userId,
        Collection<String> categoryCodes,
        Collection<UUID> sourceIds,
        Collection<UUID> userIds,
        Instant from,
        Instant to
    ) {
        Specification<Expense> spec = (root, q, cb) -> cb.equal(root.get("tripId"), tripId);
        spec = spec.and((root, q, cb) -> cb.isNull(root.get("deletedAt")));
        if (userId != null) {
            spec = spec.and((root, q, cb) -> cb.equal(root.get("userId"), userId));
        }
        if (categoryCodes != null && !categoryCodes.isEmpty()) {
            spec = spec.and((root, q, cb) -> root.get("categoryCode").in(categoryCodes));
        }
        if (sourceIds != null && !sourceIds.isEmpty()) {
            spec = spec.and((root, q, cb) -> root.get("sourceId").in(sourceIds));
        }
        if (userIds != null && !userIds.isEmpty()) {
            spec = spec.and((root, q, cb) -> root.get("userId").in(userIds));
        }
        if (from != null) {
            spec = spec.and((root, q, cb) ->
                cb.greaterThanOrEqualTo(root.get("occurredAt"), from));
        }
        if (to != null) {
            spec = spec.and((root, q, cb) ->
                cb.lessThanOrEqualTo(root.get("occurredAt"), to));
        }
        return findAll(spec, Sort.by(Sort.Order.desc("occurredAt"), Sort.Order.desc("id")));
    }
}
