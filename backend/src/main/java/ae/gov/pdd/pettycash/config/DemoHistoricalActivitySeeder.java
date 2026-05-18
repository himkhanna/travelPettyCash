package ae.gov.pdd.pettycash.config;

import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseRepository;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.AllocationRepository;
import ae.gov.pdd.pettycash.fund.FundsStatus;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.trip.TripStatus;
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
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static ae.gov.pdd.pettycash.config.DemoMissionSeeder.MISSION_EUROPE_ENGAGEMENT;
import static ae.gov.pdd.pettycash.config.DemoMissionSeeder.MISSION_GULF_TOUR;
import static ae.gov.pdd.pettycash.config.DemoMissionSeeder.MISSION_LEVANT_VISITS;
import static ae.gov.pdd.pettycash.config.DemoPersonas.AHMED;
import static ae.gov.pdd.pettycash.config.DemoPersonas.FATIMA;
import static ae.gov.pdd.pettycash.config.DemoPersonas.KHALID;
import static ae.gov.pdd.pettycash.config.DemoPersonas.LAYLA;
import static ae.gov.pdd.pettycash.config.DemoPersonas.MOHAMMED;
import static ae.gov.pdd.pettycash.config.DemoSourceSeeder.PROTOCOL_ID;
import static ae.gov.pdd.pettycash.config.DemoSourceSeeder.ZABEEL_ID;

/**
 * Seeds three CLOSED historical trips with full allocations + expenses,
 * spread across the last ~90 days. Gives the audit feed, Reports, and DG
 * dashboard real depth so the demo doesn't feel sparse.
 *
 * Idempotent: each row has a fixed UUID; re-runs are no-ops.
 *
 * Runs at @Order(45) — after the regular trip/allocation/expense seeders
 * (Order 30/35/40) so it doesn't compete with them for the same fixtures.
 */
@Component
@Order(45)
@ConditionalOnProperty(name = "pdd.demo.seed", havingValue = "true")
public class DemoHistoricalActivitySeeder implements ApplicationRunner {

    private static final Logger log =
        LoggerFactory.getLogger(DemoHistoricalActivitySeeder.class);

    private final TripRepository trips;
    private final AllocationRepository allocations;
    private final ExpenseRepository expenses;

    public DemoHistoricalActivitySeeder(
        TripRepository trips,
        AllocationRepository allocations,
        ExpenseRepository expenses
    ) {
        this.trips = trips;
        this.allocations = allocations;
        this.expenses = expenses;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        int t = 0, a = 0, e = 0;
        for (HistoricalTrip h : HISTORICAL_TRIPS) {
            if (trips.existsById(h.id)) continue;
            Trip trip = new Trip(
                h.id, h.name, h.countryCode, h.countryName,
                h.currency, TripStatus.CLOSED, KHALID.id(), h.leaderId,
                h.budgetMinor, h.memberIds
            );
            trip.setMissionId(h.missionId);
            backdate(trip, "createdAt", h.createdAt);
            backdate(trip, "closedAt", h.closedAt);
            trips.save(trip);
            t++;

            for (HistoricalAllocation ha : h.allocations) {
                if (allocations.existsById(ha.id)) continue;
                Allocation alloc = new Allocation(
                    ha.id, h.id,
                    null, // admin-pool
                    h.leaderId,
                    ha.sourceId,
                    ha.amountMinor, h.currency,
                    FundsStatus.ACCEPTED,
                    "Pre-trip advance"
                );
                backdate(alloc, "createdAt", ha.at);
                backdate(alloc, "respondedAt", ha.at.plus(2, ChronoUnit.HOURS));
                allocations.save(alloc);
                a++;
            }

            for (HistoricalExpense he : h.expenses) {
                if (expenses.existsById(he.id)) continue;
                Expense exp = new Expense(
                    he.id, h.id, he.userId, he.sourceId,
                    he.categoryCode, he.amountMinor, h.currency,
                    he.quantity, he.details, he.occurredAt, null
                );
                backdate(exp, "createdAt", he.occurredAt);
                expenses.save(exp);
                e++;
            }
        }
        log.info(
            "DemoHistoricalActivitySeeder seeded {} trip(s), {} allocation(s), {} expense(s).",
            t, a, e
        );
    }

    private static void backdate(Object o, String field, Instant value) {
        try {
            Field f = o.getClass().getDeclaredField(field);
            f.setAccessible(true);
            f.set(o, value);
        } catch (ReflectiveOperationException ex) {
            throw new IllegalStateException("Failed to backdate " + field, ex);
        }
    }

    // ---- fixture data ------------------------------------------------

    private record HistoricalTrip(
        UUID id,
        UUID missionId,
        String name,
        String countryCode,
        String countryName,
        String currency,
        UUID leaderId,
        Set<UUID> memberIds,
        long budgetMinor,
        Instant createdAt,
        Instant closedAt,
        List<HistoricalAllocation> allocations,
        List<HistoricalExpense> expenses
    ) {}

    private record HistoricalAllocation(
        UUID id, UUID sourceId, long amountMinor, Instant at
    ) {}

    private record HistoricalExpense(
        UUID id, UUID userId, UUID sourceId, String categoryCode,
        long amountMinor, int quantity, String details, Instant occurredAt
    ) {}

    // Anchor everything to a fixed Instant so the seed is deterministic
    // regardless of when the seeder runs.
    private static final Instant NOW = Instant.parse("2026-05-17T08:00:00Z");

    private static Instant daysAgo(int d) {
        return NOW.minus(d, ChronoUnit.DAYS);
    }

    private static UUID id(String last) {
        return UUID.fromString("00000000-0000-0000-0004-" + last);
    }

    private static final List<HistoricalTrip> HISTORICAL_TRIPS = List.of(
        // ─────────── Riyadh G20 — Gulf Tour Mission ───────────
        new HistoricalTrip(
            id("000000000001"),
            MISSION_GULF_TOUR,
            "Riyadh G20 Side-Meeting",
            "SA", "Saudi Arabia", "SAR",
            FATIMA.id(),
            Set.of(AHMED.id(), MOHAMMED.id()),
            8_000_000L, // SAR 80,000 budget
            daysAgo(85), daysAgo(78),
            List.of(
                new HistoricalAllocation(
                    id("a00000000001"), ZABEEL_ID, 5_000_000L, daysAgo(85)),
                new HistoricalAllocation(
                    id("a00000000002"), PROTOCOL_ID, 3_000_000L, daysAgo(85))
            ),
            List.of(
                new HistoricalExpense(
                    id("e00000000001"), FATIMA.id(), ZABEEL_ID, "HOTEL",
                    1_840_000L, 4, "Burj Rafal — 4 nights",
                    daysAgo(83)),
                new HistoricalExpense(
                    id("e00000000002"), AHMED.id(), ZABEEL_ID, "TRANSPORT",
                    225_000L, 1, "Airport transfer",
                    daysAgo(83)),
                new HistoricalExpense(
                    id("e00000000003"), MOHAMMED.id(), PROTOCOL_ID, "FOOD",
                    480_000L, 1, "Delegation dinner — Najd",
                    daysAgo(82)),
                new HistoricalExpense(
                    id("e00000000004"), FATIMA.id(), PROTOCOL_ID, "TIPS",
                    150_000L, 1, "Honoraria for liaison staff",
                    daysAgo(81)),
                new HistoricalExpense(
                    id("e00000000005"), AHMED.id(), ZABEEL_ID, "TRANSPORT",
                    320_000L, 1, "Side-meeting venue transport",
                    daysAgo(80))
            )
        ),
        // ─────────── Amman Bilateral — Levant Mission ───────────
        new HistoricalTrip(
            id("000000000002"),
            MISSION_LEVANT_VISITS,
            "Amman Bilateral Visit",
            "JO", "Jordan", "JOD",
            FATIMA.id(),
            Set.of(AHMED.id(), LAYLA.id()),
            5_200_000L, // JOD 52,000 budget
            daysAgo(58), daysAgo(52),
            List.of(
                new HistoricalAllocation(
                    id("a00000000003"), ZABEEL_ID, 3_200_000L, daysAgo(58)),
                new HistoricalAllocation(
                    id("a00000000004"), PROTOCOL_ID, 2_000_000L, daysAgo(58))
            ),
            List.of(
                new HistoricalExpense(
                    id("e00000000006"), FATIMA.id(), ZABEEL_ID, "HOTEL",
                    980_000L, 3, "Four Seasons — 3 nights",
                    daysAgo(57)),
                new HistoricalExpense(
                    id("e00000000007"), LAYLA.id(), PROTOCOL_ID, "FOOD",
                    240_000L, 1, "Ministry lunch",
                    daysAgo(56)),
                new HistoricalExpense(
                    id("e00000000008"), AHMED.id(), ZABEEL_ID, "TRANSPORT",
                    180_000L, 1, "Embassy transport",
                    daysAgo(55)),
                new HistoricalExpense(
                    id("e00000000009"), LAYLA.id(), ZABEEL_ID, "PHONE",
                    65_000L, 1, "Local SIM for delegation",
                    daysAgo(55))
            )
        ),
        // ─────────── London Trade Talks — Europe Mission ───────────
        new HistoricalTrip(
            id("000000000003"),
            MISSION_EUROPE_ENGAGEMENT,
            "London Trade Talks",
            "GB", "United Kingdom", "GBP",
            FATIMA.id(),
            Set.of(AHMED.id(), MOHAMMED.id(), LAYLA.id()),
            4_500_000L, // GBP 45,000 budget
            daysAgo(30), daysAgo(22),
            List.of(
                new HistoricalAllocation(
                    id("a00000000005"), ZABEEL_ID, 2_500_000L, daysAgo(30)),
                new HistoricalAllocation(
                    id("a00000000006"), PROTOCOL_ID, 2_000_000L, daysAgo(30))
            ),
            List.of(
                new HistoricalExpense(
                    id("e00000000010"), FATIMA.id(), ZABEEL_ID, "HOTEL",
                    1_500_000L, 5, "Claridge's — 5 nights",
                    daysAgo(29)),
                new HistoricalExpense(
                    id("e00000000011"), AHMED.id(), ZABEEL_ID, "TRANSPORT",
                    420_000L, 1, "Heathrow transfers + Whitehall meetings",
                    daysAgo(28)),
                new HistoricalExpense(
                    id("e00000000012"), MOHAMMED.id(), PROTOCOL_ID, "FOOD",
                    380_000L, 1, "Delegation dinner — Berkeley",
                    daysAgo(27)),
                new HistoricalExpense(
                    id("e00000000013"), LAYLA.id(), PROTOCOL_ID, "ENTERTAINMENT",
                    220_000L, 1, "Royal Opera House — cultural reception",
                    daysAgo(26)),
                new HistoricalExpense(
                    id("e00000000014"), AHMED.id(), ZABEEL_ID, "TIPS",
                    90_000L, 1, "Hotel staff + drivers",
                    daysAgo(24)),
                new HistoricalExpense(
                    id("e00000000015"), FATIMA.id(), PROTOCOL_ID, "OTHERS",
                    140_000L, 1, "Translator fees",
                    daysAgo(23))
            )
        )
    );
}
