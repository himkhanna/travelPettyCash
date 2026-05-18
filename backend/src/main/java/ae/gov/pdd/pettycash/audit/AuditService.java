package ae.gov.pdd.pettycash.audit;

import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseRepository;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.AllocationRepository;
import ae.gov.pdd.pettycash.fund.FundsStatus;
import ae.gov.pdd.pettycash.fund.Transfer;
import ae.gov.pdd.pettycash.fund.TransferRepository;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.trip.TripStatus;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Synthesizes the unified audit feed from existing transactional tables.
 *
 * Approach: enumerate every Trip, Allocation, Transfer, and Expense; map
 * each to one or more [AuditEntry] records (a Trip yields a "created"
 * entry plus optionally a "closed" entry; an Allocation yields "created"
 * plus optionally "responded"; etc.). Then sort by timestamp desc and trim
 * to the requested limit.
 *
 * This is O(n) on total rows per request. Fine for demo-scale data; at
 * production volume we'd replace this with a dedicated audit_log table
 * written transactionally inside each service (CLAUDE.md §5).
 */
@Service
class AuditService {

    private final TripRepository trips;
    private final AllocationRepository allocations;
    private final TransferRepository transfers;
    private final ExpenseRepository expenses;
    private final UserRepository users;

    AuditService(
        TripRepository trips,
        AllocationRepository allocations,
        TransferRepository transfers,
        ExpenseRepository expenses,
        UserRepository users
    ) {
        this.trips = trips;
        this.allocations = allocations;
        this.transfers = transfers;
        this.expenses = expenses;
        this.users = users;
    }

    List<AuditEntry> list(
        UUID tripId,
        UUID actorId,
        Instant from,
        Instant to,
        int limit
    ) {
        // Lookup caches keyed by id so we don't repeat-fetch the same user
        // or trip while emitting entries.
        Map<UUID, User> userById = new HashMap<>();
        for (User u : users.findAll()) userById.put(u.getId(), u);
        Map<UUID, Trip> tripById = new HashMap<>();
        for (Trip t : trips.findAll()) tripById.put(t.getId(), t);

        List<AuditEntry> all = new ArrayList<>();

        // Trip lifecycle
        for (Trip t : tripById.values()) {
            if (tripId != null && !t.getId().equals(tripId)) continue;
            all.add(_tripCreated(t, userById));
            if (t.getStatus() == TripStatus.CLOSED && t.getClosedAt() != null) {
                all.add(_tripClosed(t, userById));
            }
        }

        // Allocations — created + (if responded) accepted/declined
        for (Allocation a : allocations.findAll()) {
            if (tripId != null && !a.getTripId().equals(tripId)) continue;
            all.add(_allocationCreated(a, tripById, userById));
            if (a.getRespondedAt() != null
                && a.getStatus() != FundsStatus.PENDING) {
                all.add(_allocationResponded(a, tripById, userById));
            }
        }

        // Transfers — created + (if responded) accepted/declined
        for (Transfer x : transfers.findAll()) {
            if (tripId != null && !x.getTripId().equals(tripId)) continue;
            all.add(_transferCreated(x, tripById, userById));
            if (x.getRespondedAt() != null
                && x.getStatus() != FundsStatus.PENDING) {
                all.add(_transferResponded(x, tripById, userById));
            }
        }

        // Expenses
        for (Expense e : expenses.findAll()) {
            if (tripId != null && !e.getTripId().equals(tripId)) continue;
            all.add(_expenseLogged(e, tripById, userById));
        }

        // Filter + sort + trim
        return all.stream()
            .filter(e -> actorId == null
                || (e.actorId() != null && e.actorId().equals(actorId)))
            .filter(e -> from == null || !e.at().isBefore(from))
            .filter(e -> to == null || !e.at().isAfter(to))
            .sorted((a, b) -> b.at().compareTo(a.at()))
            .limit(limit)
            .toList();
    }

    // ---- emitters ---------------------------------------------------

    private AuditEntry _tripCreated(Trip t, Map<UUID, User> userById) {
        User actor = userById.get(t.getCreatedById());
        return new AuditEntry(
            "trip-create-" + t.getId(),
            t.getCreatedAt(),
            AuditAction.TRIP_CREATED,
            actor != null ? actor.getId() : null,
            actor != null ? actor.getDisplayName() : "—",
            actor != null ? actor.getRole().name() : "—",
            null, null,
            t.getId(), t.getName(),
            null,
            "Created trip \"" + t.getName() + "\""
        );
    }

    private AuditEntry _tripClosed(Trip t, Map<UUID, User> userById) {
        // We don't track who closed the trip on the row yet. Attribute to
        // the trip's createdBy as a stand-in until we add `closedById`.
        User actor = userById.get(t.getCreatedById());
        return new AuditEntry(
            "trip-close-" + t.getId(),
            t.getClosedAt(),
            AuditAction.TRIP_CLOSED,
            actor != null ? actor.getId() : null,
            actor != null ? actor.getDisplayName() : "—",
            actor != null ? actor.getRole().name() : "—",
            null, null,
            t.getId(), t.getName(),
            null,
            "Closed trip \"" + t.getName() + "\""
        );
    }

    private AuditEntry _allocationCreated(
        Allocation a, Map<UUID, Trip> tripById, Map<UUID, User> userById
    ) {
        boolean fromAdmin = a.getFromUserId() == null;
        User actor = fromAdmin ? null : userById.get(a.getFromUserId());
        User target = userById.get(a.getToUserId());
        Trip trip = tripById.get(a.getTripId());
        return new AuditEntry(
            "alloc-create-" + a.getId(),
            a.getCreatedAt(),
            fromAdmin
                ? AuditAction.ALLOCATION_FROM_ADMIN
                : AuditAction.ALLOCATION_FROM_LEADER,
            actor != null ? actor.getId() : null,
            actor != null ? actor.getDisplayName() : "Admin",
            actor != null ? actor.getRole().name() : "ADMIN",
            target != null ? target.getId() : null,
            target != null ? target.getDisplayName() : "—",
            a.getTripId(), trip != null ? trip.getName() : "—",
            MoneyDto.from(new Money(a.getAmountMinor(), a.getCurrency())),
            (fromAdmin ? "Admin" : (actor != null ? actor.getDisplayName() : "Leader"))
                + " allocated "
                + _fmt(a.getAmountMinor(), a.getCurrency())
                + " to " + (target != null ? target.getDisplayName() : "a member")
        );
    }

    private AuditEntry _allocationResponded(
        Allocation a, Map<UUID, Trip> tripById, Map<UUID, User> userById
    ) {
        User target = userById.get(a.getToUserId());
        Trip trip = tripById.get(a.getTripId());
        boolean accepted = a.getStatus() == FundsStatus.ACCEPTED;
        return new AuditEntry(
            "alloc-respond-" + a.getId(),
            a.getRespondedAt(),
            accepted
                ? AuditAction.ALLOCATION_ACCEPTED
                : AuditAction.ALLOCATION_DECLINED,
            target != null ? target.getId() : null,
            target != null ? target.getDisplayName() : "—",
            target != null ? target.getRole().name() : "—",
            null, null,
            a.getTripId(), trip != null ? trip.getName() : "—",
            MoneyDto.from(new Money(a.getAmountMinor(), a.getCurrency())),
            (target != null ? target.getDisplayName() : "Recipient")
                + (accepted ? " accepted " : " declined ")
                + _fmt(a.getAmountMinor(), a.getCurrency())
        );
    }

    private AuditEntry _transferCreated(
        Transfer x, Map<UUID, Trip> tripById, Map<UUID, User> userById
    ) {
        User actor = userById.get(x.getFromUserId());
        User target = userById.get(x.getToUserId());
        Trip trip = tripById.get(x.getTripId());
        return new AuditEntry(
            "xfer-create-" + x.getId(),
            x.getCreatedAt(),
            AuditAction.TRANSFER_SENT,
            actor != null ? actor.getId() : null,
            actor != null ? actor.getDisplayName() : "—",
            actor != null ? actor.getRole().name() : "—",
            target != null ? target.getId() : null,
            target != null ? target.getDisplayName() : "—",
            x.getTripId(), trip != null ? trip.getName() : "—",
            MoneyDto.from(new Money(x.getAmountMinor(), x.getCurrency())),
            (actor != null ? actor.getDisplayName() : "Sender")
                + " sent "
                + _fmt(x.getAmountMinor(), x.getCurrency())
                + " to " + (target != null ? target.getDisplayName() : "a peer")
        );
    }

    private AuditEntry _transferResponded(
        Transfer x, Map<UUID, Trip> tripById, Map<UUID, User> userById
    ) {
        User target = userById.get(x.getToUserId());
        Trip trip = tripById.get(x.getTripId());
        boolean accepted = x.getStatus() == FundsStatus.ACCEPTED;
        return new AuditEntry(
            "xfer-respond-" + x.getId(),
            x.getRespondedAt(),
            accepted
                ? AuditAction.TRANSFER_ACCEPTED
                : AuditAction.TRANSFER_DECLINED,
            target != null ? target.getId() : null,
            target != null ? target.getDisplayName() : "—",
            target != null ? target.getRole().name() : "—",
            null, null,
            x.getTripId(), trip != null ? trip.getName() : "—",
            MoneyDto.from(new Money(x.getAmountMinor(), x.getCurrency())),
            (target != null ? target.getDisplayName() : "Recipient")
                + (accepted ? " accepted " : " declined ")
                + " transfer of "
                + _fmt(x.getAmountMinor(), x.getCurrency())
        );
    }

    /** "SAR 1,234.56" — matches the client `Money.format()` output shape. */
    private static String _fmt(long amountMinor, String currency) {
        return String.format(
            java.util.Locale.ENGLISH,
            "%s %,.2f",
            currency,
            amountMinor / 100.0
        );
    }

    private AuditEntry _expenseLogged(
        Expense e, Map<UUID, Trip> tripById, Map<UUID, User> userById
    ) {
        User actor = userById.get(e.getUserId());
        Trip trip = tripById.get(e.getTripId());
        return new AuditEntry(
            "expense-" + e.getId(),
            e.getCreatedAt(),
            AuditAction.EXPENSE_LOGGED,
            actor != null ? actor.getId() : null,
            actor != null ? actor.getDisplayName() : "—",
            actor != null ? actor.getRole().name() : "—",
            null, null,
            e.getTripId(), trip != null ? trip.getName() : "—",
            MoneyDto.from(new Money(e.getAmountMinor(), e.getCurrency())),
            (actor != null ? actor.getDisplayName() : "Someone")
                + " logged "
                + _fmt(e.getAmountMinor(), e.getCurrency())
                + (e.getDetails() == null || e.getDetails().isBlank()
                    ? ""
                    : " — " + e.getDetails())
        );
    }
}
