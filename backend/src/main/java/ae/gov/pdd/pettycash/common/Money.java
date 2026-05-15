package ae.gov.pdd.pettycash.common;

import java.util.Objects;

/**
 * Server-side money value object. Always stores minor units (CLAUDE.md §6).
 *
 * <p>Wire shape on the API is {@code {amount: long_minor_units, currency: "ISO"}}
 * — see {@link ae.gov.pdd.pettycash.common.MoneyDto}.
 */
public record Money(long amountMinor, String currency) {

    public Money {
        Objects.requireNonNull(currency, "currency");
        if (currency.length() != 3) {
            throw new IllegalArgumentException(
                "currency must be a 3-letter ISO code, got: " + currency
            );
        }
    }

    public static Money zero(String currency) {
        return new Money(0L, currency);
    }

    public Money plus(Money other) {
        requireSameCurrency(other);
        return new Money(amountMinor + other.amountMinor, currency);
    }

    public Money minus(Money other) {
        requireSameCurrency(other);
        return new Money(amountMinor - other.amountMinor, currency);
    }

    public boolean isNegative() {
        return amountMinor < 0;
    }

    private void requireSameCurrency(Money other) {
        if (!currency.equals(other.currency)) {
            throw new IllegalArgumentException(
                "Currency mismatch: " + currency + " vs " + other.currency
            );
        }
    }
}
