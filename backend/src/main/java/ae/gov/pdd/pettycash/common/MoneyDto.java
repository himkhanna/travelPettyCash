package ae.gov.pdd.pettycash.common;

/// Wire format for money per CLAUDE.md §9 — `{ amount: <minor>, currency: <ISO> }`.
public record MoneyDto(long amount, String currency) {
    public static MoneyDto of(Money m) { return new MoneyDto(m.amountMinor(), m.currency()); }
    public Money toMoney() { return new Money(amount, currency); }
}
