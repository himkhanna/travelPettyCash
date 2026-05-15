package ae.gov.pdd.pettycash.config;

import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseRepository;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static ae.gov.pdd.pettycash.config.DemoPersonas.AHMED;
import static ae.gov.pdd.pettycash.config.DemoPersonas.FATIMA;
import static ae.gov.pdd.pettycash.config.DemoPersonas.LAYLA;
import static ae.gov.pdd.pettycash.config.DemoPersonas.MOHAMMED;
import static ae.gov.pdd.pettycash.config.DemoSourceSeeder.PROTOCOL_ID;
import static ae.gov.pdd.pettycash.config.DemoSourceSeeder.ZABEEL_ID;

/**
 * Seeds the 20 demo expenses from {@code mobile/assets/demo/expenses.json}.
 * Spread across the three demo trips so trip/balances rolls up to non-zero
 * numbers without needing the user to record anything. Runs after the trip
 * + source + category seeders.
 */
@Component
@Order(40)
@ConditionalOnProperty(name = "pdd.demo.seed", havingValue = "true")
public class DemoExpenseSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DemoExpenseSeeder.class);

    /** Trip ids fixed in {@link DemoTripSeeder}. */
    private static final UUID KSA_TRIP =
        UUID.fromString("00000000-0000-0000-0002-000000005a01");
    private static final UUID EGY_TRIP =
        UUID.fromString("00000000-0000-0000-0002-0000000e9201");
    private static final UUID JOR_TRIP =
        UUID.fromString("00000000-0000-0000-0002-00000000d05e");

    private final ExpenseRepository expenses;
    private final TripRepository trips;

    public DemoExpenseSeeder(ExpenseRepository expenses, TripRepository trips) {
        this.expenses = expenses;
        this.trips = trips;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        int seeded = 0;
        for (Seed s : SEEDS) {
            if (expenses.existsById(s.id())) continue;
            Optional<Trip> trip = trips.findById(s.tripId());
            if (trip.isEmpty()) continue;
            Expense e = new Expense(
                s.id(),
                s.tripId(),
                s.userId(),
                s.sourceId(),
                s.categoryCode(),
                s.amountMinor(),
                trip.get().getCurrency(),
                s.quantity(),
                s.details(),
                s.occurredAt(),
                s.receiptObjectKey()
            );
            expenses.save(e);
            seeded++;
        }
        log.info("DemoExpenseSeeder seeded {} expense(s).", seeded);
    }

    private record Seed(
        UUID id,
        UUID tripId,
        UUID userId,
        UUID sourceId,
        String categoryCode,
        long amountMinor,
        int quantity,
        String details,
        Instant occurredAt,
        String receiptObjectKey
    ) {}

    private static UUID exp(int n) {
        return UUID.fromString("00000000-0000-0000-0003-%012x".formatted(n));
    }

    private static final List<Seed> SEEDS = List.of(
        // KSA — Ahmed
        new Seed(exp(1), KSA_TRIP, AHMED.id(), ZABEEL_ID,   "HOTEL",      120000, 1,
            "Hotel night — Burj Rafal", Instant.parse("2026-04-29T18:00:00Z"), "demo/receipts/r1.jpg"),
        new Seed(exp(2), KSA_TRIP, AHMED.id(), PROTOCOL_ID, "FOOD",        18000, 1,
            "Lunch with delegation", Instant.parse("2026-04-30T09:30:00Z"), "demo/receipts/r2.jpg"),
        new Seed(exp(3), KSA_TRIP, AHMED.id(), ZABEEL_ID,   "TRANSPORT",    7500, 1,
            "Taxi to ministry", Instant.parse("2026-04-30T05:00:00Z"), null),
        new Seed(exp(4), KSA_TRIP, AHMED.id(), PROTOCOL_ID, "TIPS",         5000, 1,
            "Bellhop", Instant.parse("2026-04-30T04:00:00Z"), null),
        // KSA — Mohammed
        new Seed(exp(5), KSA_TRIP, MOHAMMED.id(), ZABEEL_ID,   "FOOD",     22500, 1,
            "Dinner — Olive Garden Riyadh", Instant.parse("2026-04-30T17:00:00Z"), "demo/receipts/r3.jpg"),
        new Seed(exp(6), KSA_TRIP, MOHAMMED.id(), PROTOCOL_ID, "TRANSPORT", 35000, 1,
            "Airport transfer", Instant.parse("2026-04-28T13:30:00Z"), null),
        new Seed(exp(7), KSA_TRIP, MOHAMMED.id(), ZABEEL_ID,   "PHONE",     9000, 1,
            "Local SIM top-up", Instant.parse("2026-04-29T07:00:00Z"), null),
        // KSA — Fatima
        new Seed(exp(8), KSA_TRIP, FATIMA.id(), PROTOCOL_ID, "HOTEL",     180000, 1,
            "Hotel — Four Seasons", Instant.parse("2026-04-29T18:00:00Z"), "demo/receipts/r4.jpg"),
        new Seed(exp(9), KSA_TRIP, FATIMA.id(), ZABEEL_ID,   "FOOD",       45000, 1,
            "Group dinner", Instant.parse("2026-04-30T16:00:00Z"), null),
        new Seed(exp(10), KSA_TRIP, FATIMA.id(), PROTOCOL_ID, "ENTERTAINMENT", 30000, 1,
            "Cultural visit tickets", Instant.parse("2026-05-01T11:00:00Z"), null),
        new Seed(exp(11), KSA_TRIP, AHMED.id(), ZABEEL_ID,   "FOOD",       14500, 1,
            "Breakfast", Instant.parse("2026-05-01T04:00:00Z"), null),
        new Seed(exp(12), KSA_TRIP, AHMED.id(), PROTOCOL_ID, "TRANSPORT",   6000, 1,
            "Taxi", Instant.parse("2026-05-01T06:00:00Z"), null),
        new Seed(exp(13), KSA_TRIP, MOHAMMED.id(), PROTOCOL_ID, "OTHERS",  12000, 1,
            "Stationery — meeting prep", Instant.parse("2026-05-01T07:00:00Z"), null),
        new Seed(exp(14), KSA_TRIP, AHMED.id(), ZABEEL_ID,   "TIPS",        3000, 1,
            "Driver", Instant.parse("2026-05-02T15:00:00Z"), null),
        new Seed(exp(15), KSA_TRIP, MOHAMMED.id(), ZABEEL_ID, "FOOD",      26000, 1,
            "Lunch", Instant.parse("2026-05-02T09:00:00Z"), null),
        // EGY
        new Seed(exp(16), EGY_TRIP, AHMED.id(),    PROTOCOL_ID, "HOTEL",   350000, 1,
            "Hotel — Marriott Cairo", Instant.parse("2026-05-03T18:00:00Z"), "demo/receipts/r5.jpg"),
        new Seed(exp(17), EGY_TRIP, AHMED.id(),    ZABEEL_ID,   "TRANSPORT", 75000, 1,
            "Driver — daily", Instant.parse("2026-05-04T04:00:00Z"), null),
        new Seed(exp(18), EGY_TRIP, MOHAMMED.id(), PROTOCOL_ID, "FOOD",     42000, 1,
            "Welcome dinner", Instant.parse("2026-05-04T16:00:00Z"), null),
        // JOR (closed trip)
        new Seed(exp(19), JOR_TRIP, AHMED.id(), ZABEEL_ID,   "HOTEL",      90000, 3,
            "Hotel — 3 nights", Instant.parse("2026-03-12T18:00:00Z"), null),
        new Seed(exp(20), JOR_TRIP, LAYLA.id(), PROTOCOL_ID, "FOOD",       28000, 1,
            "Group lunch", Instant.parse("2026-03-13T09:00:00Z"), null)
    );
}
