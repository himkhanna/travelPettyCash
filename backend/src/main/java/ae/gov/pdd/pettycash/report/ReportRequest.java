package ae.gov.pdd.pettycash.report;

import java.util.UUID;

/**
 * Inbound report parameters.
 *
 * @param tripId  required.
 * @param type    {@link ReportType}.
 * @param format  {@link ReportFormat}.
 * @param userId  optional. Used to filter USER/DG reports to a single user;
 *                ignored for TRIP and FINANCE.
 */
public record ReportRequest(UUID tripId, ReportType type, ReportFormat format, UUID userId) {}
