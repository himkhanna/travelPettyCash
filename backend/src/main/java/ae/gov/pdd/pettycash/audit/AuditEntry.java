package ae.gov.pdd.pettycash.audit;

import ae.gov.pdd.pettycash.common.MoneyDto;

import java.time.Instant;
import java.util.UUID;

/**
 * One row in the unified activity feed. Each instance describes a single
 * mutation: a trip was created, an allocation moved a sum, an expense was
 * logged, etc.
 *
 * Field shape is intentionally flat so the mobile/CMS renderer doesn't need
 * type-switching to display common columns (actor, target, amount, when).
 */
public record AuditEntry(
    String id,
    Instant at,

    /** Type taxonomy — see [AuditAction] for the closed set we emit. */
    AuditAction action,

    /** The user who performed the action, or null for system events. */
    UUID actorId,
    String actorName,
    String actorRole,

    /** Optional secondary user — e.g. the recipient of a transfer. */
    UUID targetUserId,
    String targetUserName,

    /** Trip context, when the action is scoped to a trip. */
    UUID tripId,
    String tripName,

    /** Monetary delta, when meaningful. */
    MoneyDto amount,

    /** Free-text description for the row's body. */
    String summary
) {}
