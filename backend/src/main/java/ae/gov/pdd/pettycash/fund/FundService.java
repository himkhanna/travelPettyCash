package ae.gov.pdd.pettycash.fund;

import ae.gov.pdd.pettycash.audit.AuditService;
import ae.gov.pdd.pettycash.auth.CurrentUser;
import ae.gov.pdd.pettycash.common.ApiException;
import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.user.Role;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class FundService {

    private final AllocationRepository allocations;
    private final TransferRepository transfers;
    private final TripRepository trips;
    private final SourceRepository sources;
    private final AuditService audit;
    private final CurrentUser current;

    public FundService(AllocationRepository allocations, TransferRepository transfers,
                       TripRepository trips, SourceRepository sources,
                       AuditService audit, CurrentUser current) {
        this.allocations = allocations;
        this.transfers = transfers;
        this.trips = trips;
        this.sources = sources;
        this.audit = audit;
        this.current = current;
    }

    @Transactional(readOnly = true)
    public List<Allocation> listForTrip(UUID tripId) {
        return allocations.findByTripId(tripId);
    }

    @Transactional
    public List<Allocation> createAllocations(UUID tripId, FundDtos.CreateAllocationsRequest req) {
        Trip trip = trips.findById(tripId).orElseThrow(
            () -> ApiException.notFound("TRIP_NOT_FOUND", "Trip " + tripId));

        Role role = current.role();
        boolean isLeader = trip.getLeaderId().equals(current.id());
        if (!(role == Role.ADMIN || (role == Role.LEADER && isLeader))) {
            throw ApiException.forbidden("FORBIDDEN", "Only ADMIN or trip LEADER may allocate funds");
        }
        UUID fromUserId = (role == Role.ADMIN) ? null : current.id();

        List<Allocation> created = new ArrayList<>();
        for (FundDtos.AllocationDraft d : req.allocations()) {
            if (!sources.existsById(d.sourceId())) {
                throw ApiException.notFound("SOURCE_NOT_FOUND", "Source " + d.sourceId());
            }
            if (!d.amount().currency().equalsIgnoreCase(trip.getCurrency())) {
                throw ApiException.badRequest("CURRENCY_MISMATCH",
                    "Allocation currency must match trip currency");
            }
            Allocation a = new Allocation();
            a.setId(UUID.randomUUID());
            a.setTripId(tripId);
            a.setFromUserId(fromUserId);
            a.setToUserId(d.toUserId());
            a.setSourceId(d.sourceId());
            a.setAmount(Money.of(d.amount().amount(), d.amount().currency()));
            a.setStatus(AllocationStatus.PENDING);
            a.setNote(d.note());
            a.setCreatedAt(OffsetDateTime.now());
            Allocation saved = allocations.save(a);
            audit.recordEvent("Allocation", saved.getId().toString(), current.id(), "CREATE",
                null,
                Map.of(
                    "tripId", tripId.toString(),
                    "toUserId", saved.getToUserId().toString(),
                    "sourceId", saved.getSourceId().toString(),
                    "amount", saved.getAmount().amount(),
                    "currency", saved.getAmount().currency()
                ));
            created.add(saved);
        }
        return created;
    }

    @Transactional
    public Allocation respond(UUID allocationId, String action) {
        Allocation a = allocations.findById(allocationId).orElseThrow(
            () -> ApiException.notFound("ALLOCATION_NOT_FOUND", "Allocation " + allocationId));
        if (!a.getToUserId().equals(current.id())) {
            throw ApiException.forbidden("FORBIDDEN", "Only the recipient may respond");
        }
        if (a.getStatus() != AllocationStatus.PENDING) {
            throw ApiException.conflict("ALREADY_RESPONDED", "Allocation already " + a.getStatus());
        }
        AllocationStatus next = switch (action) {
            case "ACCEPT" -> AllocationStatus.ACCEPTED;
            case "DECLINE" -> AllocationStatus.DECLINED;
            default -> throw ApiException.badRequest("BAD_ACTION", "action must be ACCEPT or DECLINE");
        };
        a.setStatus(next);
        a.setRespondedAt(OffsetDateTime.now());
        return allocations.save(a);
    }

    @Transactional
    public Transfer createTransfer(UUID tripId, FundDtos.CreateTransferRequest req) {
        Trip trip = trips.findById(tripId).orElseThrow(
            () -> ApiException.notFound("TRIP_NOT_FOUND", "Trip " + tripId));
        if (!trip.getMemberIds().contains(current.id()) && !trip.getLeaderId().equals(current.id())) {
            throw ApiException.forbidden("NOT_TRIP_MEMBER", "Caller is not a trip participant");
        }
        if (!sources.existsById(req.sourceId())) {
            throw ApiException.notFound("SOURCE_NOT_FOUND", "Source " + req.sourceId());
        }
        if (req.id() == null) throw ApiException.badRequest("MISSING_ID", "Client UUID required");
        if (transfers.existsById(req.id())) return transfers.findById(req.id()).orElseThrow();

        Transfer t = new Transfer();
        t.setId(req.id());
        t.setTripId(tripId);
        t.setFromUserId(current.id());
        t.setToUserId(req.toUserId());
        t.setSourceId(req.sourceId());
        t.setAmount(Money.of(req.amount().amount(), req.amount().currency()));
        t.setStatus(AllocationStatus.PENDING);
        t.setNote(req.note());
        t.setCreatedAt(OffsetDateTime.now());
        return transfers.save(t);
    }
}
