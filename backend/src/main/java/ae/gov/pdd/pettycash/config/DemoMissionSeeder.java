package ae.gov.pdd.pettycash.config;

import ae.gov.pdd.pettycash.mission.Mission;
import ae.gov.pdd.pettycash.mission.MissionRepository;
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

/**
 * Seeds demo missions. Each mission groups multiple {@code Trip}s under a
 * single diplomatic / operational objective. Runs before the trip seeders
 * so trips can reference these via {@code Trip.missionId}.
 */
@Component
@Order(25)
@ConditionalOnProperty(name = "pdd.demo.seed", havingValue = "true")
public class DemoMissionSeeder implements ApplicationRunner {

    private static final Logger log =
        LoggerFactory.getLogger(DemoMissionSeeder.class);

    public static final UUID MISSION_GULF_TOUR =
        UUID.fromString("00000000-0000-0000-0003-000000000001");
    public static final UUID MISSION_LEVANT_VISITS =
        UUID.fromString("00000000-0000-0000-0003-000000000002");
    public static final UUID MISSION_EUROPE_ENGAGEMENT =
        UUID.fromString("00000000-0000-0000-0003-000000000003");

    private final MissionRepository missions;

    public DemoMissionSeeder(MissionRepository missions) {
        this.missions = missions;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        int seeded = 0;
        for (MissionSeed s : SEEDS) {
            if (missions.existsById(s.id())) continue;
            Mission m = new Mission(
                s.id(), s.name(), s.nameAr(), s.code(), s.description(),
                null, DemoPersonas.KHALID.id()
            );
            backdate(m, "createdAt", s.createdAt());
            missions.save(m);
            seeded++;
        }
        log.info("DemoMissionSeeder seeded {} mission(s).", seeded);
    }

    private static void backdate(Mission m, String fieldName, Instant value) {
        try {
            Field f = Mission.class.getDeclaredField(fieldName);
            f.setAccessible(true);
            f.set(m, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException("Failed to backdate " + fieldName, e);
        }
    }

    private record MissionSeed(
        UUID id,
        String name,
        String nameAr,
        String code,
        String description,
        Instant createdAt
    ) {}

    private static final List<MissionSeed> SEEDS = List.of(
        new MissionSeed(
            MISSION_GULF_TOUR,
            "Gulf State Tour 2026",
            "جولة دول الخليج 2026",
            "GULF-TOUR-26",
            "Bilateral state visits across the GCC, Q1–Q2 2026.",
            Instant.parse("2026-01-15T08:00:00Z")
        ),
        new MissionSeed(
            MISSION_LEVANT_VISITS,
            "Levant Engagement",
            "العلاقات مع بلاد الشام",
            "LEVANT-26",
            "Coordination visits to Jordan and neighbouring Levant states.",
            Instant.parse("2026-02-10T08:00:00Z")
        ),
        new MissionSeed(
            MISSION_EUROPE_ENGAGEMENT,
            "Europe Engagement 2026",
            "العلاقات الأوروبية 2026",
            "EUROPE-26",
            "Trade + cultural visits to UK and EU partners.",
            Instant.parse("2026-04-01T08:00:00Z")
        )
    );
}
