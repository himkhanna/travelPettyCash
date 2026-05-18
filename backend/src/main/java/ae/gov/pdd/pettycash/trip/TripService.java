package ae.gov.pdd.pettycash.trip;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseRepository;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.AllocationRepository;
import ae.gov.pdd.pettycash.fund.FundsStatus;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.fund.SourceRepository;
import ae.gov.pdd.pettycash.fund.Transfer;
import ae.gov.pdd.pettycash.fund.TransferRepository;
import ae.gov.pdd.pettycash.notification.NotificationRefType;
import ae.gov.pdd.pettycash.notification.NotificationService;
import ae.gov.pdd.pettycash.notification.NotificationType;
import ae.gov.pdd.pettycash.trip.dto.CreateTripRequest;
import ae.gov.pdd.pettycash.trip.dto.TripBalancesDto;
import ae.gov.pdd.pettycash.trip.dto.TripDto;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@Service
public class TripService {

    private final TripRepository trips;
    private final SourceRepository sources;
    private final UserRepository users;
    private final AllocationRepository allocations;
    private final TransferRepository transfers;
    private final ExpenseRepository expenses;
    private final NotificationService notifications;
    private final Clock clock;

    @Autowired
    public TripService(
        TripRepository trips,
        SourceRepository sources,
        UserRepository users,
        AllocationRepository allocations,
        TransferRepository transfers,
        ExpenseRepository expenses,
        NotificationService notifications
    ) {
        this(trips, sources, users, allocations, transfers, expenses, notifications, Clock.systemUTC());
    }

    TripService(
        TripRepository trips,
        SourceRepository sources,
        UserRepository users,
        AllocationRepository allocations,
        TransferRepository transfers,
        ExpenseRepository expenses,
        NotificationService notifications,
        Clock clock
    ) {
        this.trips = trips;
        this.sources = sources;
        this.users = users;
        this.allocations = allocations;
        this.transfers = transfers;
        this.expenses = expenses;
        this.notifications = notifications;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<TripDto> listForCaller(AuthenticatedUser caller, TripStatus status) {
        List<Trip> rows = caller.role() == UserRole.ADMIN || caller.role() == UserRole.SUPER_ADMIN
            ? trips.findAllFiltered(status)
            : trips.findForUser(caller.userId(), status);
        return rows.stream().map(TripDto::from).toList();
    }

    @Transactional(readOnly = true)
    public TripDto get(UUID tripId, AuthenticatedUser caller) {
        Trip t = loadAccessible(tripId, caller);
        return TripDto.from(t);
    }

    @Transactional
    public TripDto create(CreateTripRequest req, AuthenticatedUser caller) {
        // CLAUDE.md §7: Admin only.
        requireAdmin(caller);

        if (!users.existsById(req.leaderId())) {
            throw badRequest("trips/leader-not-found", "Leader does not exist");
        }
        for (UUID m : req.memberIds()) {
            if (!users.existsById(m)) {
                throw badRequest("trips/member-not-found", "Member " + m + " does not exist");
            }
        }
        if (!req.totalBudget().currency().equals(req.currency())) {
            throw badRequest(
                "trips/currency-mismatch",
                "totalBudget.currency must equal trip.currency"
            );
        }
        if (req.totalBudget().amount() < 0) {
            throw badRequest("trips/negative-budget", "totalBudget.amount must be >= 0");
        }

        Set<UUID> members = new HashSet<>(req.memberIds());
        Trip t = new Trip(
            UUID.randomUUID(),
            req.name(),
            req.countryCode(),
            req.countryName(),
            req.currency(),
            TripStatus.ACTIVE,
            caller.userId(),
            req.leaderId(),
            req.totalBudget().amount(),
            members
        );
        // Mission optional — the CMS picker enforces the requirement on the
        // client; here we just attach the FK if provided.
        if (req.missionId() != null) {
            t.setMissionId(req.missionId());
        }
        trips.save(t);
        return TripDto.from(t);
    }

    /**
     * Partial update — admin-only. Any null field on the request is left
     * unchanged. {@code memberIds} is the full replacement set when present
     * (passing {@code []} clears every member; not a delta).
     *
     * <p>When members are removed: their PENDING allocations + transfers
     * on this trip are auto-DECLINED (the user shouldn't be expected to
     * respond to a request that no longer concerns them, and the trip's
     * balance math shouldn't keep counting them). Accepted rows are kept
     * for audit history.
     *
     * <p>Closed trips reject the patch entirely — once history is sealed,
     * roster changes would invalidate the report.
     */
    @Transactional
    public TripDto update(
        UUID tripId,
        ae.gov.pdd.pettycash.trip.dto.PatchTripRequest req,
        AuthenticatedUser caller
    ) {
        requireAdmin(caller);
        Trip t = trips.findById(tripId).orElseThrow(() -> notFound(tripId));
        if (t.getStatus() == TripStatus.CLOSED) {
            throw badRequest("trips/closed", "Closed trips cannot be edited.");
        }

        if (req.name() != null && !req.name().isBlank()) {
            t.rename(req.name().trim());
        }

        if (req.leaderId() != null && !req.leaderId().equals(t.getLeaderId())) {
            if (!users.existsById(req.leaderId())) {
                throw badRequest("trips/leader-not-found", "Leader does not exist");
            }
            t.reassignLeader(req.leaderId());
        }

        if (req.memberIds() != null) {
            java.util.Set<java.util.UUID> requested =
                new java.util.HashSet<>(req.memberIds());
            for (UUID m : requested) {
                if (!users.existsById(m)) {
                    throw badRequest(
                        "trips/member-not-found",
                        "Member " + m + " does not exist"
                    );
                }
            }
            // Removed = on the trip but not in the new set. Cascade-decline
            // their pending activity on this trip.
            java.util.Set<UUID> removed = new java.util.HashSet<>(t.getMemberIds());
            removed.removeAll(requested);
            java.time.Instant now = clock.instant();
            for (UUID r : removed) {
                for (ae.gov.pdd.pettycash.fund.Allocation a :
                        allocations.findByTripIdAndToUserIdAndStatus(
                            t.getId(), r,
                            ae.gov.pdd.pettycash.fund.FundsStatus.PENDING)) {
                    a.respond(
                        ae.gov.pdd.pettycash.fund.FundsStatus.DECLINED, now
                    );
                }
                for (ae.gov.pdd.pettycash.fund.Transfer x :
                        transfers.findPendingInvolvingUser(t.getId(), r)) {
                    x.respond(
                        ae.gov.pdd.pettycash.fund.FundsStatus.DECLINED, now
                    );
                }
            }
            t.replaceMembers(requested);
        }

        return TripDto.from(t);
    }

    @Transactional
    public TripDto close(UUID tripId, AuthenticatedUser caller) {
        requireAdmin(caller);
        Trip t = trips.findById(tripId)
            .orElseThrow(() -> notFound(tripId));
        if (t.getStatus() == TripStatus.CLOSED) {
            throw badRequest("trips/already-closed", "Trip is already closed");
        }
        t.close(clock.instant());

        // TRIP_CLOSED on every participant (leader + members). Passive
        // notification: no accept/decline, just informs the inbox.
        Set<UUID> recipients = new LinkedHashSet<>();
        recipients.add(t.getLeaderId());
        recipients.addAll(t.getMemberIds());
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("tripId", t.getId().toString());
        payload.put("byUserId", caller.userId().toString());
        notifications.fanOut(
            NotificationType.TRIP_CLOSED,
            false,
            NotificationRefType.TRIP,
            t.getId(),
            payload,
            recipients
        );
        return TripDto.from(t);
    }

    /**
     * Hard-delete a trip and cascade its allocations + transfers. Refuses
     * if any expenses are logged against the trip — those represent real
     * financial activity that must be preserved; the admin should close
     * the trip instead, which keeps it read-only.
     */
    @Transactional
    public void delete(UUID tripId, AuthenticatedUser caller) {
        requireAdmin(caller);
        Trip t = trips.findById(tripId)
            .orElseThrow(() -> notFound(tripId));
        List<Expense> tripExpenses =
            expenses.findByTripIdAndDeletedAtIsNullOrderByOccurredAtDesc(t.getId());
        if (!tripExpenses.isEmpty()) {
            throw new ApiException(
                HttpStatus.CONFLICT,
                "trips/has-expenses",
                "Trip cannot be deleted",
                "This trip has " + tripExpenses.size() +
                    " expense(s) logged. Close the trip instead — closed "
                    + "trips become read-only but preserve the audit trail."
            );
        }
        // Cascade the lightweight associations. Notifications + chat are
        // append-only and reference trip by id only; orphaned rows are fine
        // (they continue to surface in the audit feed with a now-deleted
        // tripId, which is desirable: the deletion itself is the event).
        allocations.deleteByTripId(t.getId());
        transfers.deleteByTripId(t.getId());
        trips.deleteById(t.getId());
    }

    /**
     * Balance rollup per CLAUDE.md §6.4 — recomputed from the event log
     * (allocations + transfers + expenses), never cached.
     *
     * <ul>
     *   <li>{@code received} folds accepted allocations and (at me-scope)
     *       accepted peer transfers received.</li>
     *   <li>{@code spent} folds expenses, plus (at me-scope) accepted peer
     *       transfers sent — the wallet shrinks the same way for either.</li>
     * </ul>
     * Negative balances are allowed; the mobile UI shows a warning chip.
     */
    @Transactional(readOnly = true)
    public TripBalancesDto balances(UUID tripId, AuthenticatedUser caller, String scope) {
        Trip t = loadAccessible(tripId, caller);
        String currency = t.getCurrency();
        String resolvedScope = scope == null ? "trip" : scope;

        List<Allocation> tripAllocs = allocations.findByTripIdOrderByCreatedAtAsc(t.getId());
        List<Transfer> tripXfers = transfers.findByTripIdOrderByCreatedAtAsc(t.getId());
        List<Expense> tripExpenses =
            expenses.findByTripIdAndDeletedAtIsNullOrderByOccurredAtDesc(t.getId());

        List<TripBalancesDto.SourceBalanceDto> perSource = sources
            .findByActiveTrueOrderByName()
            .stream()
            .map((Source s) -> {
                long received = sumReceived(s.getId(), resolvedScope, caller, t, tripAllocs, tripXfers);
                long spent = sumSpent(s.getId(), resolvedScope, caller, tripXfers, tripExpenses);
                return new TripBalancesDto.SourceBalanceDto(
                    s.getId(),
                    s.getName(),
                    s.getNameAr(),
                    MoneyDto.from(new Money(received, currency)),
                    MoneyDto.from(new Money(spent, currency)),
                    MoneyDto.from(new Money(received - spent, currency))
                );
            })
            .toList();

        long totalReceived = perSource.stream().mapToLong(b -> b.received().amount()).sum();
        long totalSpent    = perSource.stream().mapToLong(b -> b.spent().amount()).sum();

        // Headline totalBudget stays the trip's stated budget so the donut
        // chart's outer ring keeps a stable scale across responses.
        Money budget = new Money(t.getTotalBudgetMinor(), currency);
        return new TripBalancesDto(
            tripId,
            resolvedScope,
            MoneyDto.from(budget),
            MoneyDto.from(new Money(totalSpent, currency)),
            MoneyDto.from(new Money(totalReceived - totalSpent, currency)),
            perSource
        );
    }

    private long sumReceived(
        UUID sourceId,
        String scope,
        AuthenticatedUser caller,
        Trip trip,
        List<Allocation> allocs,
        List<Transfer> xfers
    ) {
        long total = 0;
        for (Allocation a : allocs) {
            if (!a.getSourceId().equals(sourceId)) continue;
            if (a.getStatus() != FundsStatus.ACCEPTED) continue;
            boolean include = switch (scope) {
                case "me"     -> a.getToUserId().equals(caller.userId());
                case "leader" -> a.getToUserId().equals(trip.getLeaderId())
                                  && a.getFromUserId() == null;
                default       -> a.getFromUserId() == null; // trip
            };
            if (include) total += a.getAmountMinor();
        }
        if ("me".equals(scope)) {
            for (Transfer t : xfers) {
                if (!t.getSourceId().equals(sourceId)) continue;
                if (t.getStatus() != FundsStatus.ACCEPTED) continue;
                if (t.getToUserId().equals(caller.userId())) total += t.getAmountMinor();
            }
        }
        return total;
    }

    private long sumSpent(
        UUID sourceId,
        String scope,
        AuthenticatedUser caller,
        List<Transfer> xfers,
        List<Expense> tripExpenses
    ) {
        long total = 0;
        for (Expense e : tripExpenses) {
            if (!e.getSourceId().equals(sourceId)) continue;
            boolean include = switch (scope) {
                case "me"     -> e.getUserId().equals(caller.userId());
                case "leader" -> true; // leader scope rolls up the whole trip
                default       -> true;
            };
            if (include) total += e.getAmountMinor();
        }
        // At me-scope an outbound peer transfer also shrinks the wallet
        // (the cash physically leaves the holder). Mirrors the rule in
        // mobile/.../fake_trip_repository.dart.
        if ("me".equals(scope)) {
            for (Transfer t : xfers) {
                if (!t.getSourceId().equals(sourceId)) continue;
                if (t.getStatus() != FundsStatus.ACCEPTED) continue;
                if (t.getFromUserId().equals(caller.userId())) total += t.getAmountMinor();
            }
        }
        return total;
    }

    // ---- helpers ------------------------------------------------------

    private Trip loadAccessible(UUID tripId, AuthenticatedUser caller) {
        Trip t = trips.findById(tripId).orElseThrow(() -> notFound(tripId));
        boolean isAdmin = caller.role() == UserRole.ADMIN
            || caller.role() == UserRole.SUPER_ADMIN;
        boolean isParticipant = t.getLeaderId().equals(caller.userId())
            || t.getCreatedById().equals(caller.userId())
            || t.getMemberIds().contains(caller.userId());
        if (!isAdmin && !isParticipant) {
            // 404 not 403 — don't leak that the trip exists.
            throw notFound(tripId);
        }
        return t;
    }

    private static void requireAdmin(AuthenticatedUser caller) {
        if (caller.role() != UserRole.ADMIN && caller.role() != UserRole.SUPER_ADMIN) {
            throw new ApiException(
                HttpStatus.FORBIDDEN,
                "auth/forbidden",
                "Forbidden",
                "Only admins may perform this action."
            );
        }
    }

    private static ApiException notFound(UUID tripId) {
        return new ApiException(
            HttpStatus.NOT_FOUND,
            "trips/not-found",
            "Trip not found",
            "No trip with id " + tripId + " is accessible to this user."
        );
    }

    private static ApiException badRequest(String code, String detail) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, "Bad request", detail);
    }
}
