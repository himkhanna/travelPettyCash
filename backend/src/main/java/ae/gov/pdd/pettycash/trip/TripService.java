package ae.gov.pdd.pettycash.trip;

import ae.gov.pdd.pettycash.auth.CurrentUser;
import ae.gov.pdd.pettycash.common.ApiException;
import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseRepository;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.AllocationRepository;
import ae.gov.pdd.pettycash.fund.AllocationStatus;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.fund.SourceRepository;
import ae.gov.pdd.pettycash.user.Role;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.*;

/**
 * Trip orchestration. Re-checks permissions per CLAUDE.md §7
 * (controller annotations enforce too — defense in depth).
 */
@Service
public class TripService {

    private final TripRepository trips;
    private final ExpenseRepository expenses;
    private final AllocationRepository allocations;
    private final SourceRepository sources;
    private final CurrentUser current;

    public TripService(TripRepository trips, ExpenseRepository expenses,
                       AllocationRepository allocations, SourceRepository sources,
                       CurrentUser current) {
        this.trips = trips;
        this.expenses = expenses;
        this.allocations = allocations;
        this.sources = sources;
        this.current = current;
    }

    @Transactional(readOnly = true)
    public List<Trip> list(TripStatus status, UUID viewerId, Role viewerRole) {
        // Super admin & admin see all; everyone else sees only trips they participate in.
        List<Trip> all = (status == null) ? trips.findAll() : trips.findByStatus(status);
        if (viewerRole == Role.ADMIN || viewerRole == Role.SUPER_ADMIN) {
            return all;
        }
        return all.stream()
            .filter(t -> t.getMemberIds().contains(viewerId) || Objects.equals(t.getLeaderId(), viewerId))
            .toList();
    }

    @Transactional(readOnly = true)
    public Trip get(UUID id) {
        return trips.findById(id)
            .orElseThrow(() -> ApiException.notFound("TRIP_NOT_FOUND", "Trip " + id + " not found"));
    }

    @Transactional
    public Trip create(TripDtos.CreateTripRequest req) {
        // Service-layer permission re-check per CLAUDE.md §7.
        if (current.role() != Role.ADMIN) {
            throw ApiException.forbidden("FORBIDDEN", "Only ADMIN may create trips");
        }
        if (req.totalBudget() == null || !req.currency().equalsIgnoreCase(req.totalBudget().currency())) {
            throw ApiException.badRequest("CURRENCY_MISMATCH",
                "Trip currency must match totalBudget currency");
        }
        Trip t = new Trip();
        t.setId(UUID.randomUUID());
        t.setName(req.name());
        t.setCountryCode(req.countryCode());
        t.setCountryName(req.countryName());
        t.setCurrency(req.currency().toUpperCase());
        t.setStatus(TripStatus.ACTIVE);
        t.setCreatedBy(current.id());
        t.setLeaderId(req.leaderId());
        t.setTotalBudget(Money.of(req.totalBudget().amount(), req.totalBudget().currency()));
        t.setImageUrl(req.imageUrl());
        t.setMemberIds(new LinkedHashSet<>(req.memberIds() == null ? List.of() : req.memberIds()));
        t.setCreatedAt(OffsetDateTime.now());
        return trips.save(t);
    }

    @Transactional
    public Trip close(UUID id) {
        if (current.role() != Role.ADMIN) {
            throw ApiException.forbidden("FORBIDDEN", "Only ADMIN may close trips");
        }
        Trip t = get(id);
        if (t.getStatus() == TripStatus.CLOSED) {
            throw ApiException.conflict("ALREADY_CLOSED", "Trip already closed");
        }
        t.setStatus(TripStatus.CLOSED);
        t.setClosedAt(OffsetDateTime.now());
        return trips.save(t);
    }

    @Transactional(readOnly = true)
    public TripDtos.TripBalances balances(UUID tripId, String scope) {
        Trip t = get(tripId);
        String currency = t.getCurrency();

        // Filter expenses + allocations by scope.
        List<Expense> exps;
        List<Allocation> allocs;
        UUID viewer = current.id();
        if ("me".equals(scope)) {
            exps = expenses.findByTripIdAndUserId(tripId, viewer);
            allocs = allocations.findByTripIdAndToUserId(tripId, viewer);
        } else {
            // "trip" and "leader" — full view; "leader" gated by controller @PreAuthorize.
            exps = expenses.findByTripId(tripId);
            allocs = allocations.findByTripId(tripId);
        }

        // Per-source aggregation.
        Map<UUID, long[]> perSource = new LinkedHashMap<>(); // sourceId -> [received, spent]
        for (Allocation a : allocs) {
            if (a.getStatus() == AllocationStatus.ACCEPTED) {
                perSource.computeIfAbsent(a.getSourceId(), k -> new long[2])[0] += a.getAmount().amount();
            }
        }
        for (Expense e : exps) {
            perSource.computeIfAbsent(e.getSourceId(), k -> new long[2])[1] += e.getAmount().amount();
        }

        Map<UUID, Source> sourceMap = new HashMap<>();
        sources.findAllById(perSource.keySet()).forEach(s -> sourceMap.put(s.getId(), s));

        long totalReceived = 0, totalSpent = 0;
        List<TripDtos.SourceBalance> rows = new ArrayList<>();
        for (var entry : perSource.entrySet()) {
            long received = entry.getValue()[0];
            long spent = entry.getValue()[1];
            totalReceived += received;
            totalSpent += spent;
            Source s = sourceMap.get(entry.getKey());
            rows.add(new TripDtos.SourceBalance(
                entry.getKey(),
                s == null ? null : s.getName(),
                s == null ? null : s.getNameAr(),
                new MoneyDto(received, currency),
                new MoneyDto(spent, currency),
                new MoneyDto(received - spent, currency)
            ));
        }
        return new TripDtos.TripBalances(
            tripId,
            scope,
            MoneyDto.from(t.getTotalBudget()),
            new MoneyDto(totalSpent, currency),
            new MoneyDto(totalReceived - totalSpent, currency),
            rows
        );
    }
}
