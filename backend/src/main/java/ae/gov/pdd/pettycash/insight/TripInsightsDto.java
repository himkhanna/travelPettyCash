package ae.gov.pdd.pettycash.insight;

import java.util.List;

/**
 * Response for {@code GET /api/v1/trips/{id}/insights}: a plain-language
 * narrative summary of the trip plus the list of individual flagged
 * {@link Insight}s. Both are deterministically generated from the trip's
 * expenses and budget.
 */
public record TripInsightsDto(
    String narrative,
    List<Insight> insights
) {}
