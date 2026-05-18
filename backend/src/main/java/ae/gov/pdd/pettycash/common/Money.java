package ae.gov.pdd.pettycash.common;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;

import java.util.Objects;

/**
 * Monetary value object. Stored as BIGINT minor units + ISO 4217 currency code.
 * See CLAUDE.md §6 — all arithmetic on monetary amounts must go through this type.
 *
 * <p>Embedded into JPA entities; never use raw long/double for amounts in business code.
 */
@Embeddable
public class Money implements Comparable<Money> {

    @Column(name = "amount", nullable = false)
    private long amount;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    protected Money() {
        // JPA
    }

    public Money(long amount, String currency) {
        this.amount = amount;
        this.currency = Objects.requireNonNull(currency, "currency").toUpperCase();
        if (this.currency.length() != 3) {
            throw new IllegalArgumentException("Currency must be ISO 4217 3-letter code: " + currency);
        }
    }

    public static Money of(long amount, String currency) {
        return new Money(amount, currency);
    }

    public static Money zero(String currency) {
        return new Money(0L, currency);
    }

    public long amount() {
        return amount;
    }

    public String currency() {
        return currency;
    }

    public Money plus(Money other) {
        requireSameCurrency(other);
        return new Money(Math.addExact(this.amount, other.amount), this.currency);
    }

    public Money minus(Money other) {
        requireSameCurrency(other);
        return new Money(Math.subtractExact(this.amount, other.amount), this.currency);
    }

    public Money negate() {
        return new Money(Math.negateExact(this.amount), this.currency);
    }

    public boolean isNegative() {
        return amount < 0L;
    }

    public boolean isZero() {
        return amount == 0L;
    }

    @Override
    public int compareTo(Money other) {
        requireSameCurrency(other);
        return Long.compare(this.amount, other.amount);
    }

    private void requireSameCurrency(Money other) {
        Objects.requireNonNull(other, "other");
        if (!this.currency.equals(other.currency)) {
            throw new IllegalArgumentException(
                "Currency mismatch: " + this.currency + " vs " + other.currency);
        }
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Money money)) return false;
        return amount == money.amount && Objects.equals(currency, money.currency);
    }

    @Override
    public int hashCode() {
        return Objects.hash(amount, currency);
    }

    @Override
    public String toString() {
        return currency + " " + amount;
    }
}
