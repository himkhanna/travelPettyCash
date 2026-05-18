package ae.gov.pdd.pettycash.report;

/**
 * Report types per CLAUDE.md §10.
 *
 * <ul>
 *   <li>USER — single user's expenses for finance, grouped by source then category.</li>
 *   <li>TRIP — every expense by every member; team-level summary.</li>
 *   <li>FINANCE — letterhead PDF: sources used, totals per source, net balance returned.
 *       Will be PAdES-signed once ADR-003 unblocks; currently watermarked "DRAFT — unsigned".</li>
 *   <li>DG — read-only summary for the Director General view.</li>
 * </ul>
 */
public enum ReportType {
    USER, TRIP, FINANCE, DG
}
