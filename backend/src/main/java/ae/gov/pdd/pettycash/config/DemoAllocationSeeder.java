package ae.gov.pdd.pettycash.config;

import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.AllocationRepository;
import ae.gov.pdd.pettycash.fund.FundsStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.lang.reflect.Field;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static ae.gov.pdd.pettycash.config.DemoPersonas.FATIMA;
import static ae.gov.pdd.pettycash.config.DemoSourceSeeder.PROTOCOL_ID;
import static ae.gov.pdd.pettycash.config.DemoSourceSeeder.ZABEEL_ID;

/**
 * Seeds admin → leader allocations on every demo trip so the trip-scope
 * balance lands positive on first boot — without these the seeded expenses
 * draw against zero "received" and trips open with deeply negative balances.
 *
 * <p>Sized to cover roughly 90% of each trip's stated {@code totalBudget},
 * split between the two funding sources (Zabeel + Protocol). Runs after the
 * trip + source seeders, before the expense seeder.
 */
@Component
@Order(35)
@ConditionalOnProperty(name = "pdd.demo.seed", havingValue = "true")
public class DemoAllocationSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DemoAllocationSeeder.class);

    private static final UUID KSA_TRIP =
        UUID.fromString("00000000-0000-0000-0002-000000005a01");
    private static final UUID EGY_TRIP =
        UUID.fromString("00000000-0000-0000-0002-0000000e9201");
    private static final UUID JOR_TRIP =
        UUID.fromString("00000000-0000-0000-0002-00000000d05e");

    private final AllocationRepository allocations;

    public DemoAllocationSeeder(AllocationRepository allocations) {
        this.allocations = allocations;
    }

    private static UUID alloc(int n) {
        return UUID.fromString("00000000-0000-0000-0006-%012x".formatted(n));
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        int seeded = 0;
        for (Seed s : SEEDS) {
            if (allocations.existsById(s.id())) continue;
            Allocation a = new Allocation(
                s.id(),
                s.tripId(),
                null,            // fromUserId=null marks an admin-pool allocation
                FATIMA.id(),     // to the trip leader
                s.sourceId(),
                s.amountMinor(),
                s.currency(),
                FundsStatus.ACCEPTED,
                "Pre-trip advance"
            );
            // Backdate created_at + responded_at so the activity log reads in
            // the right order relative to the seeded expenses.
            backdate(a, "createdAt", s.at());
            backdate(a, "respondedAt", s.at().plusSeconds(60));
            allocations.save(a);
            seeded++;
        }
        log.info("DemoAllocationSeeder seeded {} admin allocation(s).", seeded);
    }

    private static void backdate(Object entity, String field, Instant value) {
        try {
            Field f = entity.getClass().getDeclaredField(field);
            f.setAccessible(true);
            f.set(entity, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException("Failed to backdate " + field, e);
        }
    }

    private record Seed(
        UUID id, UUID tripId, UUID sourceId,
        long amountMinor, String currency, Instant at
    ) {}

    /**
     * Per-trip allocation budgets, split roughly 55/45 across the two sources.
     * Totals stay below the trip's stated {@code totalBudget} so the headline
     * "remaining" arc reads as not-yet-fully-allocated.
     */
    private static final List<Seed> SEEDS = List.of(
        // KSA — 9,100,000 SAR budget; seed 5,000,000 Zabeel + 4,000,000 Protocol.
        new Seed(alloc(1),  KSA_TRIP, ZABEEL_ID,   5_000_000L, "SAR",
            Instant.parse("2026-04-27T08:00:00Z")),
        new Seed(alloc(2),  KSA_TRIP, PROTOCOL_ID, 4_000_000L, "SAR",
            Instant.parse("2026-04-27T08:05:00Z")),
        // Cairo — 4,500,000 EGP; 2,500,000 Zabeel + 2,000,000 Protocol.
        new Seed(alloc(3),  EGY_TRIP, ZABEEL_ID,   2_500_000L, "EGP",
            Instant.parse("2026-05-02T05:00:00Z")),
        new Seed(alloc(4),  EGY_TRIP, PROTOCOL_ID, 2_000_000L, "EGP",
            Instant.parse("2026-05-02T05:05:00Z")),
        // Amman (closed) — 8,500,000 JOD; 4,500,000 Zabeel + 4,000,000 Protocol.
        new Seed(alloc(5),  JOR_TRIP, ZABEEL_ID,   4_500_000L, "JOD",
            Instant.parse("2026-03-09T07:00:00Z")),
        new Seed(alloc(6),  JOR_TRIP, PROTOCOL_ID, 4_000_000L, "JOD",
            Instant.parse("2026-03-09T07:05:00Z"))
    );
}
