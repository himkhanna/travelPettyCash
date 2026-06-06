package ae.gov.pdd.pettycash.ocr;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Unit tests for the deterministic receipt categorizer. No Tesseract, no
 * Spring context — pure keyword classification over vendor + raw text.
 */
class ReceiptCategorizerTest {

    private final ReceiptCategorizer categorizer = new ReceiptCategorizer();

    @ParameterizedTest(name = "[{index}] \"{0}\" -> {1}")
    @CsvSource({
        // vendor line                         , expected code
        "Hilton Garden Inn Dubai               , HOTEL",
        "Rotana Hotel & Resort                 , HOTEL",
        "Careem ride receipt                    , TRANSPORT",
        "ADNOC fuel station                     , TRANSPORT",
        "Salik toll gate                        , TRANSPORT",
        "Starbucks Coffee                       , FOOD",
        "Al Safadi Restaurant                   , FOOD",
        "Etisalat recharge                      , PHONE",
        "VOX Cinemas Mall of the Emirates       , ENTERTAINMENT",
        "Emirates Airline e-ticket              , TRAVEL",
        "Service charge gratuity                , TIPS",
    })
    void classifiesCommonMerchants(String vendor, String expected) {
        assertThat(categorizer.categorize(vendor, null)).isEqualTo(expected);
    }

    @Test
    void returnsNullWhenNothingMatches() {
        assertThat(categorizer.categorize("Generic Trading LLC", "Invoice 4471"))
            .isNull();
    }

    @Test
    void returnsNullForBlankInput() {
        assertThat(categorizer.categorize(null, null)).isNull();
        assertThat(categorizer.categorize("", "   ")).isNull();
    }

    @Test
    void stripsAccentsSoCafeMatches() {
        // "Café" with an acute accent must still hit the "cafe" keyword.
        assertThat(categorizer.categorize("Café Bateel", null)).isEqualTo("FOOD");
    }

    @Test
    void matchesArabicMerchantNames() {
        assertThat(categorizer.categorize("فندق العنوان", null)).isEqualTo("HOTEL");
        assertThat(categorizer.categorize("مطعم البيت", null)).isEqualTo("FOOD");
    }

    @Test
    void tieBreakPrefersHotelOverFoodForHotelRestaurant() {
        // A hotel restaurant receipt hits both HOTEL ("hotel") and FOOD
        // ("restaurant") once each. HOTEL is declared first, so it wins the
        // tie deterministically.
        String code = categorizer.categorize(
            "Marriott Hotel - Atrium Restaurant", null);
        assertThat(code).isEqualTo("HOTEL");
    }

    @Test
    void usesBodyTextNotJustVendor() {
        // Vendor line is unhelpful, but the body mentions a taxi fare.
        String code = categorizer.categorize(
            "Receipt #9921",
            "Thank you for riding\nTaxi fare\nTotal 45.00 AED");
        assertThat(code).isEqualTo("TRANSPORT");
    }

    @Test
    void higherKeywordCountWins() {
        // Text leans clearly to FOOD (restaurant + coffee) vs a single
        // incidental TRANSPORT hit (parking).
        String code = categorizer.categorize(
            "The Coffee Club Restaurant",
            "coffee and cake\nfree parking validated");
        assertThat(code).isEqualTo("FOOD");
    }
}
