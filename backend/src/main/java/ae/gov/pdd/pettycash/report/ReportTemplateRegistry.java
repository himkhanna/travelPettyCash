package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.common.ApiException;
import org.springframework.stereotype.Component;

import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/**
 * Dispatches a {@link ReportRequest} to the matching {@link ReportGenerator}.
 *
 * <p>USER supports both XLSX and PDF (handled by the same generator class via
 * {@link ReportRequest#format()}). TRIP is XLSX-only, FINANCE and DG are
 * PDF-only — see CLAUDE.md §10.
 */
@Component
public class ReportTemplateRegistry {

    private final Map<ReportType, ReportGenerator> byType = new EnumMap<>(ReportType.class);
    // USER's PDF variant comes from the same UserReportGenerator instance, so we
    // don't need a (type, format) map. The generator itself routes by format.

    public ReportTemplateRegistry(List<ReportGenerator> generators) {
        for (ReportGenerator g : generators) {
            byType.put(g.type(), g);
        }
        // Sanity check: every type must have a generator registered.
        for (ReportType t : ReportType.values()) {
            if (!byType.containsKey(t)) {
                throw new IllegalStateException("Missing ReportGenerator for type " + t);
            }
        }
    }

    public ReportGenerator pick(ReportType type, ReportFormat format) {
        ReportGenerator g = byType.get(type);
        if (g == null) {
            throw ApiException.badRequest("REPORT_TYPE_UNKNOWN", "No generator for " + type);
        }
        // Format gating: TRIP XLSX only; FINANCE/DG PDF only; USER both allowed.
        switch (type) {
            case TRIP -> requireFormat(format, ReportFormat.XLSX, type);
            case FINANCE, DG -> requireFormat(format, ReportFormat.PDF, type);
            case USER -> { /* both allowed */ }
        }
        return g;
    }

    private void requireFormat(ReportFormat actual, ReportFormat expected, ReportType type) {
        if (actual != expected) {
            throw ApiException.badRequest("REPORT_FORMAT_INVALID",
                type + " reports must be " + expected + " — see CLAUDE.md §10");
        }
    }
}
