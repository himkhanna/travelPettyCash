package ae.gov.pdd.pettycash.common;

/** Wire shape per CLAUDE.md §9: {@code { "amount": 640000, "currency": "SAR" }}. */
public record MoneyDto(long amount, String currency) {
    public static MoneyDto from(Money m) {
        return new MoneyDto(m.amountMinor(), m.currency());
    }

    public Money toDomain() {
        return new Money(amount, currency);
    }
}
