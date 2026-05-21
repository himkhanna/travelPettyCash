package ae.gov.pdd.pettycash.common;

import java.util.Objects;

/// Money value object — long minor units + ISO 4217 currency. Per CLAUDE.md
/// §6 all monetary arithmetic must go through this type.
public record Money(long amountMinor, String currency) {
    public Money {
        Objects.requireNonNull(currency, "currency");
        if (currency.length() != 3) {
            throw new IllegalArgumentException("currency must be ISO 4217 3-letter code");
        }
    }

    public static Money zero(String currency) { return new Money(0, currency); }

    public Money plus(Money other) {
        ensureSame(other);
        return new Money(this.amountMinor + other.amountMinor, currency);
    }

    public Money minus(Money other) {
        ensureSame(other);
        return new Money(this.amountMinor - other.amountMinor, currency);
    }

    public boolean isNegative() { return amountMinor < 0; }
    public boolean isZero() { return amountMinor == 0; }

    private void ensureSame(Money other) {
        if (!this.currency.equals(other.currency)) {
            throw new IllegalArgumentException(
                    "currency mismatch: " + currency + " vs " + other.currency);
        }
    }
}
