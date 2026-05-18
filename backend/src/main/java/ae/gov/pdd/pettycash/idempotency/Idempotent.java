package ae.gov.pdd.pettycash.idempotency;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Marks a controller endpoint as requiring an {@code Idempotency-Key} header.
 * Enforced by {@link IdempotencyInterceptor}.
 * See CLAUDE.md §9 — required on POST /expenses, /transfers, /allocations.
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Idempotent {
}
