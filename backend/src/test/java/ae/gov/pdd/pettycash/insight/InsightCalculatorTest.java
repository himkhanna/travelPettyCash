package ae.gov.pdd.pettycash.insight;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Unit tests for the deterministic insights engine. Pure inputs, no Spring,
 * no DB. All amounts are minor units in the trip currency.
 */
class InsightCalculatorTest {

    private final InsightCalculator calc = new InsightCalculator();

    private static final UUID U1 = UUID.randomUUID();
    private static final UUID U2 = UUID.randomUUID();

    private static final Map<String, String> CATS = Map.of(
        "FOOD", "Food",
        "TRANSPORT", "Transport",
        "HOTEL", "Hotel");
    private static final Map<UUID, String> USERS = Map.of(
        U1, "Layla", U2, "Ahmed");

    private static ExpenseFact ex(long minor, String cat, UUID user, String day) {
        return new ExpenseFact(minor, cat, user, LocalDate.parse(day));
    }

    private static Insight find(TripInsightsDto dto, String type) {
        return dto.insights().stream()
            .filter(i -> i.type().equals(type))
            .findFirst().orElse(null);
    }

    @Test
    void overBudgetIsCritical() {
        // budget 1,000.00 SAR, spent 1,260.00 -> over by 260.00
        TripInsightsDto dto = calc.calculate("KSA Visit", "SAR", 100_000,
            List.of(ex(126_000, "HOTEL", U1, "2026-06-01")), CATS, USERS);

        Insight i = find(dto, "OVER_BUDGET");
        assertThat(i).isNotNull();
        assertThat(i.severity()).isEqualTo(Insight.CRITICAL);
        assertThat(i.message()).contains("SAR 260.00").contains("126%");
    }

    @Test
    void eightyPercentBurnIsWarning() {
        // budget 1,000.00, spent 850.00 -> 85%
        TripInsightsDto dto = calc.calculate("Trip", "AED", 100_000,
            List.of(ex(85_000, "FOOD", U1, "2026-06-01")), CATS, USERS);

        Insight i = find(dto, "BUDGET_BURN");
        assertThat(i).isNotNull();
        assertThat(i.severity()).isEqualTo(Insight.WARNING);
        assertThat(i.message()).contains("85%").contains("AED 150.00");
    }

    @Test
    void underBudgetIsInfo() {
        TripInsightsDto dto = calc.calculate("Trip", "AED", 100_000,
            List.of(ex(20_000, "FOOD", U1, "2026-06-01")), CATS, USERS);

        Insight i = find(dto, "BUDGET_OK");
        assertThat(i).isNotNull();
        assertThat(i.severity()).isEqualTo(Insight.INFO);
        assertThat(i.message()).contains("20%");
    }

    @Test
    void noBudgetSkipsBudgetInsight() {
        TripInsightsDto dto = calc.calculate("Trip", "AED", 0,
            List.of(ex(20_000, "FOOD", U1, "2026-06-01")), CATS, USERS);

        assertThat(find(dto, "OVER_BUDGET")).isNull();
        assertThat(find(dto, "BUDGET_BURN")).isNull();
        assertThat(find(dto, "BUDGET_OK")).isNull();
    }

    @Test
    void flagsCategoryConcentration() {
        // Hotel 800 of 1000 total -> 80% concentration (>=60 => WARNING)
        TripInsightsDto dto = calc.calculate("Trip", "AED", 0, List.of(
            ex(80_000, "HOTEL", U1, "2026-06-01"),
            ex(20_000, "FOOD", U1, "2026-06-02")
        ), CATS, USERS);

        Insight i = find(dto, "CATEGORY_CONCENTRATION");
        assertThat(i).isNotNull();
        assertThat(i.severity()).isEqualTo(Insight.WARNING);
        assertThat(i.message()).contains("Hotel").contains("80%");
    }

    @Test
    void noConcentrationWhenEvenlySpread() {
        TripInsightsDto dto = calc.calculate("Trip", "AED", 0, List.of(
            ex(34_000, "HOTEL", U1, "2026-06-01"),
            ex(33_000, "FOOD", U1, "2026-06-02"),
            ex(33_000, "TRANSPORT", U1, "2026-06-03")
        ), CATS, USERS);

        assertThat(find(dto, "CATEGORY_CONCENTRATION")).isNull();
    }

    @Test
    void detectsPossibleDuplicate() {
        // two identical FOOD expenses, same amount + day
        TripInsightsDto dto = calc.calculate("Trip", "AED", 0, List.of(
            ex(12_000, "FOOD", U1, "2026-06-01"),
            ex(12_000, "FOOD", U1, "2026-06-01"),
            ex(50_000, "HOTEL", U2, "2026-06-02")
        ), CATS, USERS);

        Insight i = find(dto, "POSSIBLE_DUPLICATE");
        assertThat(i).isNotNull();
        assertThat(i.severity()).isEqualTo(Insight.WARNING);
        assertThat(i.message()).contains("2 expenses of AED 120.00").contains("Food");
    }

    @Test
    void identifiesTopSpenderWhenMultiplePeople() {
        TripInsightsDto dto = calc.calculate("Trip", "AED", 0, List.of(
            ex(80_000, "HOTEL", U1, "2026-06-01"),
            ex(20_000, "FOOD", U2, "2026-06-02")
        ), CATS, USERS);

        Insight i = find(dto, "TOP_SPENDER");
        assertThat(i).isNotNull();
        assertThat(i.severity()).isEqualTo(Insight.INFO);
        assertThat(i.message()).contains("Layla").contains("80%");
    }

    @Test
    void noTopSpenderForSinglePerson() {
        TripInsightsDto dto = calc.calculate("Trip", "AED", 0,
            List.of(ex(80_000, "HOTEL", U1, "2026-06-01")), CATS, USERS);

        assertThat(find(dto, "TOP_SPENDER")).isNull();
    }

    @Test
    void narrativeForEmptyTrip() {
        TripInsightsDto dto = calc.calculate("Riyadh Delegation", "SAR", 100_000,
            List.of(), CATS, USERS);

        assertThat(dto.insights()).isEmpty();
        assertThat(dto.narrative()).isEqualTo(
            "Riyadh Delegation has no recorded expenses yet.");
    }

    @Test
    void narrativeSummarisesTotalsBudgetAndTopCategory() {
        TripInsightsDto dto = calc.calculate("KSA Visit", "SAR", 100_000, List.of(
            ex(60_000, "HOTEL", U1, "2026-06-01"),
            ex(20_000, "FOOD", U2, "2026-06-02")
        ), CATS, USERS);

        String n = dto.narrative();
        assertThat(n)
            .contains("KSA Visit has recorded 2 expenses")
            .contains("SAR 800.00")
            .contains("80% of the SAR 1,000.00 budget")
            .contains("Hotel is the largest category at 75%")
            .contains("SAR 200.00 remains");
    }

    @Test
    void threeDecimalCurrencyFormatsCorrectly() {
        // KWD has 3 minor digits: 1,500 minor = 1.500
        TripInsightsDto dto = calc.calculate("Kuwait", "KWD", 0,
            List.of(
                ex(1_500, "FOOD", U1, "2026-06-01"),
                ex(500, "TRANSPORT", U2, "2026-06-02")),
            CATS, USERS);

        Insight top = find(dto, "TOP_SPENDER");
        assertThat(top).isNotNull();
        assertThat(top.message()).contains("KWD 1.500");
    }
}
