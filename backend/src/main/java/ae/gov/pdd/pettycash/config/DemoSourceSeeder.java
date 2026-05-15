package ae.gov.pdd.pettycash.config;

import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.fund.SourceRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/**
 * Seeds the two named funding sources from
 * {@code mobile/assets/demo/sources.json}: Zabeel Office and Protocol
 * Department. Idempotent. Source UUIDs are fixed across reboots so referencing
 * code can pin to known IDs in tests.
 */
@Component
@Order(20)
@ConditionalOnProperty(name = "pdd.demo.seed", havingValue = "true")
public class DemoSourceSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DemoSourceSeeder.class);

    public static final UUID ZABEEL_ID = UUID.fromString(
        "00000000-0000-0000-0001-000000002abe"
    );
    public static final UUID PROTOCOL_ID = UUID.fromString(
        "00000000-0000-0000-0001-0000000040c0"
    );

    private final SourceRepository sources;

    public DemoSourceSeeder(SourceRepository sources) {
        this.sources = sources;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        int seeded = 0;
        for (Seed s : SEEDS) {
            if (sources.existsByName(s.name())) continue;
            sources.save(new Source(s.id(), s.name(), s.nameAr()));
            seeded++;
        }
        log.info("DemoSourceSeeder seeded {} source(s).", seeded);
    }

    private record Seed(UUID id, String name, String nameAr) {}

    private static final List<Seed> SEEDS = List.of(
        new Seed(ZABEEL_ID,   "Zabeel Office",       "قصر زعبيل"),
        new Seed(PROTOCOL_ID, "Protocol Department", "دائرة التشريفات")
    );
}
