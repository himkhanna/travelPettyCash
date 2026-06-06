package ae.gov.pdd.pettycash.insight;

/**
 * A single computed observation about a trip's spending. Deterministically
 * derived (no model, no GPU) but presented to feel like an assistant noticed
 * it — see {@link InsightCalculator}.
 *
 * @param type     stable machine code (e.g. {@code OVER_BUDGET},
 *                 {@code CATEGORY_CONCENTRATION}); drives the UI icon
 * @param severity {@code CRITICAL} | {@code WARNING} | {@code INFO} — drives
 *                 the UI colour
 * @param title    short headline ("Over budget")
 * @param message  the full pre-rendered sentence with the computed numbers
 */
public record Insight(
    String type,
    String severity,
    String title,
    String message
) {
    public static final String CRITICAL = "CRITICAL";
    public static final String WARNING = "WARNING";
    public static final String INFO = "INFO";
}
