package ae.gov.pdd.pettycash.common;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class MoneyTest {

    @Test
    void plusAddsSameCurrencyAmounts() {
        Money a = Money.of(500, "SAR");
        Money b = Money.of(750, "SAR");
        assertThat(a.plus(b)).isEqualTo(Money.of(1250, "SAR"));
    }

    @Test
    void minusSubtracts() {
        assertThat(Money.of(1000, "AED").minus(Money.of(300, "AED")))
            .isEqualTo(Money.of(700, "AED"));
    }

    @Test
    void negateFlipsSign() {
        Money m = Money.of(100, "USD");
        assertThat(m.negate()).isEqualTo(Money.of(-100, "USD"));
        assertThat(m.negate().isNegative()).isTrue();
    }

    @Test
    void equalityIsValueBased() {
        assertThat(Money.of(42, "SAR")).isEqualTo(Money.of(42, "SAR"));
        assertThat(Money.of(42, "sar")).isEqualTo(Money.of(42, "SAR")); // normalised case
    }

    @Test
    void currencyMismatchOnAdditionThrows() {
        assertThatThrownBy(() -> Money.of(100, "SAR").plus(Money.of(100, "AED")))
            .isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("Currency mismatch");
    }

    @Test
    void currencyMismatchOnCompareThrows() {
        assertThatThrownBy(() -> Money.of(100, "SAR").compareTo(Money.of(100, "AED")))
            .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void rejectsBadCurrencyCode() {
        assertThatThrownBy(() -> Money.of(100, "SARS"))
            .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void zeroFactory() {
        assertThat(Money.zero("SAR").isZero()).isTrue();
        assertThat(Money.zero("SAR").amount()).isEqualTo(0L);
    }

    @Test
    void toStringIncludesCurrencyFirst() {
        // CLAUDE.md §8 — display has currency first.
        assertThat(Money.of(640000, "SAR").toString()).startsWith("SAR ");
    }
}
