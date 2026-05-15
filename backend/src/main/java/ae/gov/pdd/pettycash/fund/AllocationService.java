package ae.gov.pdd.pettycash.fund;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.fund.dto.AllocationDto;
import ae.gov.pdd.pettycash.fund.dto.CreateAllocationsRequest;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.trip.TripStatus;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.List;
import java.util.UUID;

@Service
public class AllocationService {

    private final AllocationRepository allocations;
    private final TripRepository trips;
    private final SourceRepository sources;
    private final UserRepository users;
    private final Clock clock;

    @Autowired
    public AllocationService(
        AllocationRepository allocations,
        TripRepository trips,
        SourceRepository sources,
        UserRepository users
    ) {
        this(allocations, trips, sources, users, Clock.systemUTC());
    }

    AllocationService(
        AllocationRepository allocations,
        TripRepository trips,
        SourceRepository sources,
        UserRepository users,
        Clock clock
    ) {
        this.allocations = allocations;
        this.trips = trips;
        this.sources = sources;
        this.users = users;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<AllocationDto> list(UUID tripId, UUID memberId, AuthenticatedUser caller) {
        Trip trip = loadAccessibleTrip(tripId, caller);
        List<Allocation> rows = memberId == null
            ? allocations.findByTripIdOrderByCreatedAtAsc(trip.getId())
            : allocations.findByTripIdAndToUserIdOrderByCreatedAtAsc(trip.getId(), memberId);
        return rows.stream().map(AllocationDto::from).toList();
    }

    /**
     * Bulk create. Admin (or SuperAdmin) → trip pool, fromUserId = null.
     * Leader of the trip → members, fromUserId = leader. Every other caller
     * is forbidden. Currency on every row must match the trip currency.
     */
    @Transactional
    public List<AllocationDto> create(
        UUID tripId,
        CreateAllocationsRequest req,
        AuthenticatedUser caller
    ) {
        Trip trip = trips.findById(tripId)
            .orElseThrow(() -> notFound(tripId));
        if (trip.getStatus() == TripStatus.CLOSED) {
            throw badRequest("trips/closed", "Trip is closed; cannot allocate further.");
        }

        boolean isAdmin = caller.role() == UserRole.ADMIN
            || caller.role() == UserRole.SUPER_ADMIN;
        boolean isLeader = trip.getLeaderId().equals(caller.userId());
        if (!isAdmin && !isLeader) {
            throw forbidden();
        }
        UUID fromUserId = isAdmin ? null : caller.userId();

        return req.rows().stream().map(r -> {
            if (!r.amount().currency().equals(trip.getCurrency())) {
                throw badRequest(
                    "allocations/currency-mismatch",
                    "Allocation currency must equal trip currency (" + trip.getCurrency() + ")"
                );
            }
            if (r.amount().amount() <= 0) {
                throw badRequest("allocations/non-positive-amount", "amount must be > 0");
            }
            if (!sources.existsById(r.sourceId())) {
                throw badRequest("allocations/unknown-source", "Source not found: " + r.sourceId());
            }
            if (!users.existsById(r.toUserId())) {
                throw badRequest("allocations/unknown-recipient", "Recipient not found: " + r.toUserId());
            }
            // Leader can only allocate to trip members (and not to themself).
            if (!isAdmin) {
                if (r.toUserId().equals(caller.userId())) {
                    throw badRequest(
                        "allocations/self-recipient",
                        "Leader cannot allocate to themself."
                    );
                }
                if (!trip.getMemberIds().contains(r.toUserId())) {
                    throw badRequest(
                        "allocations/non-member-recipient",
                        "Leader can only allocate to members of this trip."
                    );
                }
            }
            Allocation row = new Allocation(
                UUID.randomUUID(),
                trip.getId(),
                fromUserId,
                r.toUserId(),
                r.sourceId(),
                r.amount().amount(),
                r.amount().currency(),
                FundsStatus.PENDING,
                r.note()
            );
            allocations.save(row);
            return AllocationDto.from(row);
        }).toList();
    }

    @Transactional
    public AllocationDto respond(
        UUID allocationId,
        FundsStatus response,
        AuthenticatedUser caller
    ) {
        Allocation row = allocations.findById(allocationId)
            .orElseThrow(() -> new ApiException(
                HttpStatus.NOT_FOUND,
                "allocations/not-found",
                "Allocation not found",
                "No allocation with id " + allocationId
            ));
        if (!row.getToUserId().equals(caller.userId())) {
            throw forbidden();
        }
        try {
            row.respond(response, clock.instant());
        } catch (IllegalStateException e) {
            throw badRequest("allocations/already-responded", e.getMessage());
        } catch (IllegalArgumentException e) {
            throw badRequest("allocations/invalid-response", e.getMessage());
        }
        return AllocationDto.from(row);
    }

    // ---- helpers ------------------------------------------------------

    private Trip loadAccessibleTrip(UUID tripId, AuthenticatedUser caller) {
        Trip t = trips.findById(tripId).orElseThrow(() -> notFound(tripId));
        boolean isAdmin = caller.role() == UserRole.ADMIN
            || caller.role() == UserRole.SUPER_ADMIN;
        boolean isParticipant = t.getLeaderId().equals(caller.userId())
            || t.getCreatedById().equals(caller.userId())
            || t.getMemberIds().contains(caller.userId());
        if (!isAdmin && !isParticipant) {
            throw notFound(tripId);
        }
        return t;
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

    private static ApiException forbidden() {
        return new ApiException(
            HttpStatus.FORBIDDEN,
            "auth/forbidden",
            "Forbidden",
            "You may not perform this action."
        );
    }
}
