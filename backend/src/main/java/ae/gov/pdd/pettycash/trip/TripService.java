package ae.gov.pdd.pettycash.trip;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.fund.SourceRepository;
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
import java.util.List;
import java.util.Set;
import java.util.UUID;

@Service
public class TripService {

    private final TripRepository trips;
    private final SourceRepository sources;
    private final UserRepository users;
    private final Clock clock;

    @Autowired
    public TripService(
        TripRepository trips,
        SourceRepository sources,
        UserRepository users
    ) {
        this(trips, sources, users, Clock.systemUTC());
    }

    TripService(
        TripRepository trips,
        SourceRepository sources,
        UserRepository users,
        Clock clock
    ) {
        this.trips = trips;
        this.sources = sources;
        this.users = users;
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
        trips.save(t);
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
        return TripDto.from(t);
    }

    /**
     * Balance rollup. Until the funds + expense slices land we return the
     * trip's headline {@code totalBudget} with zero {@code totalSpent} and a
     * per-source row for every active funding source — also zero. The shape
     * matches what the mobile FakeTripRepository returns so the UI doesn't
     * need to branch.
     */
    @Transactional(readOnly = true)
    public TripBalancesDto balances(UUID tripId, AuthenticatedUser caller, String scope) {
        Trip t = loadAccessible(tripId, caller);
        Money zero = Money.zero(t.getCurrency());
        Money budget = new Money(t.getTotalBudgetMinor(), t.getCurrency());

        List<TripBalancesDto.SourceBalanceDto> perSource = sources
            .findByActiveTrueOrderByName()
            .stream()
            .map((Source s) -> new TripBalancesDto.SourceBalanceDto(
                s.getId(),
                s.getName(),
                s.getNameAr(),
                MoneyDto.from(zero),
                MoneyDto.from(zero),
                MoneyDto.from(zero)
            ))
            .toList();

        return new TripBalancesDto(
            tripId,
            scope == null ? "trip" : scope,
            MoneyDto.from(budget),
            MoneyDto.from(zero),
            MoneyDto.from(budget),
            perSource
        );
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
