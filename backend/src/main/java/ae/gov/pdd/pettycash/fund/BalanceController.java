package ae.gov.pdd.pettycash.fund;

import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.common.NotFoundException;
import ae.gov.pdd.pettycash.expense.ExpenseEntity;
import ae.gov.pdd.pettycash.expense.ExpenseRepository;
import ae.gov.pdd.pettycash.trip.TripEntity;
import ae.gov.pdd.pettycash.trip.TripRepository;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

interface AllocationRepository extends JpaRepository<AllocationEntity, String> {
    List<AllocationEntity> findByTripId(String tripId);
}

interface TransferRepository extends JpaRepository<TransferEntity, String> {
    List<TransferEntity> findByTripId(String tripId);
}

/// Per CLAUDE.md §6: balances are derived from the event log, not cached.
/// We rebuild from allocations + transfers + expenses on every call.
@RestController
@RequestMapping("/api/v1/trips/{tripId}/balances")
public class BalanceController {

    private final TripRepository trips;
    private final ExpenseRepository expenses;
    private final AllocationRepository allocations;
    private final TransferRepository transfers;

    public BalanceController(TripRepository trips, ExpenseRepository expenses,
                             AllocationRepository allocations, TransferRepository transfers) {
        this.trips = trips;
        this.expenses = expenses;
        this.allocations = allocations;
        this.transfers = transfers;
    }

    public enum Scope { ME, TRIP, LEADER }

    public record SourceBalance(
            String sourceId,
            MoneyDto received,
            MoneyDto spent,
            MoneyDto balance
    ) {}

    public record TripBalances(
            String tripId,
            Scope scope,
            MoneyDto totalBudget,
            MoneyDto totalSpent,
            MoneyDto totalBalance,
            List<SourceBalance> perSource
    ) {}

    @GetMapping
    public TripBalances balances(
            @PathVariable String tripId,
            @RequestParam(defaultValue = "TRIP") Scope scope,
            @RequestParam(required = false) String userId
    ) {
        TripEntity trip = trips.findById(tripId).orElseThrow(NotFoundException::new);
        String currency = trip.getCurrency();
        String leader = trip.getLeaderId();
        String me = userId;

        Map<String, Long> received = new HashMap<>();
        Map<String, Long> spent = new HashMap<>();

        for (AllocationEntity a : allocations.findByTripId(tripId)) {
            if (a.getStatus() != TransferStatus.ACCEPTED) continue;
            boolean include = switch (scope) {
                case ME -> me != null && a.getToUserId().equals(me);
                case LEADER -> a.getToUserId().equals(leader) && a.getFromUserId() == null;
                case TRIP -> a.getFromUserId() == null;
            };
            if (include) received.merge(a.getSourceId(), a.getAmountMinor(), Long::sum);
        }

        if (scope == Scope.ME && me != null) {
            for (TransferEntity t : transfers.findByTripId(tripId)) {
                if (t.getStatus() != TransferStatus.ACCEPTED) continue;
                if (t.getToUserId().equals(me)) {
                    received.merge(t.getSourceId(), t.getAmountMinor(), Long::sum);
                }
            }
        }

        for (ExpenseEntity e : expenses.findByTripIdAndDeletedAtIsNullOrderByOccurredAtDesc(tripId)) {
            boolean include = switch (scope) {
                case ME -> me != null && e.getUserId().equals(me);
                case TRIP, LEADER -> true;
            };
            if (include) spent.merge(e.getSourceId(), e.getAmountMinor(), Long::sum);
        }

        if (scope == Scope.ME && me != null) {
            for (TransferEntity t : transfers.findByTripId(tripId)) {
                if (t.getStatus() != TransferStatus.ACCEPTED) continue;
                if (t.getFromUserId().equals(me)) {
                    spent.merge(t.getSourceId(), t.getAmountMinor(), Long::sum);
                }
            }
        }

        long totalSpent = 0;
        long totalReceived = 0;
        List<SourceBalance> rows = new ArrayList<>();
        var allKeys = new java.util.LinkedHashSet<String>();
        allKeys.addAll(received.keySet());
        allKeys.addAll(spent.keySet());
        for (String src : allKeys) {
            long r = received.getOrDefault(src, 0L);
            long s = spent.getOrDefault(src, 0L);
            totalReceived += r;
            totalSpent += s;
            rows.add(new SourceBalance(
                    src,
                    new MoneyDto(r, currency),
                    new MoneyDto(s, currency),
                    new MoneyDto(r - s, currency)
            ));
        }

        return new TripBalances(
                tripId, scope,
                new MoneyDto(trip.getTotalBudgetMinor(), currency),
                new MoneyDto(totalSpent, currency),
                new MoneyDto(totalReceived - totalSpent, currency),
                rows
        );
    }
}
