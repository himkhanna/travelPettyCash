package ae.gov.pdd.pettycash.audit;

/**
 * Closed set of action types emitted into the audit feed. Renderer maps
 * each to an icon + accent color on the CMS side; the wire value is the
 * enum name (Spring serializes it as a plain string).
 */
public enum AuditAction {
    TRIP_CREATED,
    TRIP_CLOSED,
    ALLOCATION_FROM_ADMIN,
    ALLOCATION_FROM_LEADER,
    ALLOCATION_ACCEPTED,
    ALLOCATION_DECLINED,
    TRANSFER_SENT,
    TRANSFER_ACCEPTED,
    TRANSFER_DECLINED,
    EXPENSE_LOGGED,
    USER_SIGNED_IN,
    USER_CREATED,
    USER_UPDATED,
}
