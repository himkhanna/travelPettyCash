package ae.gov.pdd.pettycash.report;

/**
 * Render a report from pre-loaded data. Generators are pure — no DB access,
 * no auth. The service layer assembles the {@link ReportContext} and the
 * generator only formats it. See CLAUDE.md §10.
 */
public interface ReportGenerator {

    ReportType type();

    ReportFormat format();

    byte[] generate(ReportRequest request, ReportContext context);
}
