package ae.gov.pdd.pettycash.config;

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
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static ae.gov.pdd.pettycash.config.DemoPersonas.AHMED;
import static ae.gov.pdd.pettycash.config.DemoPersonas.FATIMA;
import static ae.gov.pdd.pettycash.config.DemoPersonas.KHALID;
import static ae.gov.pdd.pettycash.config.DemoPersonas.LAYLA;
import static ae.gov.pdd.pettycash.config.DemoPersonas.MOHAMMED;

/**
 * Seeds the three demo trips from {@code mobile/assets/demo/trips.json}
 * (KSA, Cairo, Amman). Idempotent: trips with a fixed UUID. Runs after
 * {@link DemoUserSeeder}.
 */
@Component
@Order(30)
@ConditionalOnProperty(name = "pdd.demo.seed", havingValue = "true")
public class DemoTripSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DemoTripSeeder.class);

    private final TripRepository trips;

    public DemoTripSeeder(TripRepository trips) {
        this.trips = trips;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        int seeded = 0;
        for (TripSeed s : SEEDS) {
            if (trips.existsById(s.id())) continue;
            Trip t = new Trip(
                s.id(),
                s.name(),
                s.countryCode(),
                s.countryName(),
                s.currency(),
                s.status(),
                KHALID.id(),
                s.leaderId(),
                s.totalBudgetMinor(),
                s.memberIds()
            );
            // The createdAt/closedAt fields default in the entity ctor; backdate
            // them via reflection so demo data tracks the mobile assets — once
            // the audit slice lands these will be set via the domain event.
            backdate(t, "createdAt", s.createdAt());
            if (s.closedAt() != null) backdate(t, "closedAt", s.closedAt());
            trips.save(t);
            seeded++;
        }
        log.info("DemoTripSeeder seeded {} trip(s).", seeded);
    }

    private static void backdate(Trip t, String fieldName, Instant value) {
        try {
            Field f = Trip.class.getDeclaredField(fieldName);
            f.setAccessible(true);
            f.set(t, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException("Failed to backdate " + fieldName, e);
        }
    }

    private record TripSeed(
        UUID id,
        String name,
        String countryCode,
        String countryName,
        String currency,
        TripStatus status,
        UUID leaderId,
        Set<UUID> memberIds,
        long totalBudgetMinor,
        Instant createdAt,
        Instant closedAt
    ) {}

    private static final List<TripSeed> SEEDS = List.of(
        new TripSeed(
            UUID.fromString("00000000-0000-0000-0002-000000005a01"),
            "KSA State Visit", "SA", "Saudi Arabia", "SAR",
            TripStatus.ACTIVE,
            FATIMA.id(),
            Set.of(AHMED.id(), MOHAMMED.id(), LAYLA.id()),
            9_100_000L,
            Instant.parse("2026-04-28T05:00:00Z"),
            null
        ),
        new TripSeed(
            UUID.fromString("00000000-0000-0000-0002-0000000e9201"),
            "Cairo Delegation", "EG", "Egypt", "EGP",
            TripStatus.ACTIVE,
            FATIMA.id(),
            Set.of(AHMED.id(), MOHAMMED.id()),
            4_500_000L,
            Instant.parse("2026-05-02T06:30:00Z"),
            null
        ),
        new TripSeed(
            UUID.fromString("00000000-0000-0000-0002-00000000d05e"),
            "Amman Visit", "JO", "Jordan", "JOD",
            TripStatus.CLOSED,
            FATIMA.id(),
            Set.of(AHMED.id(), LAYLA.id()),
            8_500_000L,
            Instant.parse("2026-03-10T04:00:00Z"),
            Instant.parse("2026-03-20T14:00:00Z")
        )
    );
}
