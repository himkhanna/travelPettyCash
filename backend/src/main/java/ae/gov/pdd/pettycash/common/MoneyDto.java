package ae.gov.pdd.pettycash.common;

/**
 * Wire-format Money — minor units + ISO currency code.
 * See CLAUDE.md §9 — { "amount": 640000, "currency": "SAR" }.
 */
public record MoneyDto(long amount, String currency) {
    public static MoneyDto from(Money money) {
        if (money == null) return null;
        return new MoneyDto(money.amount(), money.currency());
    }

    public Money toDomain() {
        return Money.of(amount, currency);
    }
}
