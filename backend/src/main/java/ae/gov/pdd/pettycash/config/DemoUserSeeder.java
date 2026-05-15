package ae.gov.pdd.pettycash.config;

import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/**
 * Inserts the six demo personas (matching {@code mobile/assets/demo/users.json})
 * on first boot when {@code pdd.demo.seed=true}. All seeded passwords are
 * {@code demo1234}. Idempotent: skips users that already exist.
 *
 * <p>Not enabled in production. Listed in CLAUDE.md §16 open question — replace
 * with UAE Pass / PDD AD provisioning when that decision is made.
 */
@Component
@ConditionalOnProperty(name = "pdd.demo.seed", havingValue = "true")
public class DemoUserSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DemoUserSeeder.class);
    private static final String DEMO_PASSWORD = "demo1234";

    private final UserRepository users;
    private final PasswordEncoder passwordEncoder;

    public DemoUserSeeder(UserRepository users, PasswordEncoder passwordEncoder) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        String hash = passwordEncoder.encode(DEMO_PASSWORD);
        int seeded = 0;
        for (Persona p : PERSONAS) {
            if (users.existsByUsername(p.username)) continue;
            users.save(new User(
                p.id,
                p.username,
                p.displayName,
                p.displayNameAr,
                p.email,
                hash,
                p.role
            ));
            seeded++;
        }
        log.info("DemoUserSeeder seeded {} user(s); password is '{}'.", seeded, DEMO_PASSWORD);
    }

    private record Persona(
        UUID id,
        String username,
        String displayName,
        String displayNameAr,
        String email,
        UserRole role
    ) {}

    // Mirrors mobile/assets/demo/users.json so the same logins work locally.
    private static final List<Persona> PERSONAS = List.of(
        new Persona(
            UUID.fromString("00000000-0000-0000-0000-0000000a4d00"),
            "ahmed", "Ahmed Al Maktoum", "أحمد آل مكتوم",
            "ahmed@protocol.gov.ae", UserRole.MEMBER
        ),
        new Persona(
            UUID.fromString("00000000-0000-0000-0000-0000000fa71a"),
            "fatima", "Fatima Al Hashimi", "فاطمة الهاشمي",
            "fatima@protocol.gov.ae", UserRole.LEADER
        ),
        new Persona(
            UUID.fromString("00000000-0000-0000-0000-00000000ed01"),
            "mohammed", "Mohammed Ali", "محمد علي",
            "mohammed@protocol.gov.ae", UserRole.MEMBER
        ),
        new Persona(
            UUID.fromString("00000000-0000-0000-0000-00000001a71a"),
            "layla", "Layla Al Mansouri", "ليلى المنصوري",
            "layla@protocol.gov.ae", UserRole.MEMBER
        ),
        new Persona(
            UUID.fromString("00000000-0000-0000-0000-0000000ad10d"),
            "khalid", "Khalid Al Suwaidi", "خالد السويدي",
            "khalid@protocol.gov.ae", UserRole.ADMIN
        ),
        new Persona(
            UUID.fromString("00000000-0000-0000-0000-00000000d061"),
            "noura", "Noura Al Falasi", "نورة الفلاسي",
            "noura@protocol.gov.ae", UserRole.SUPER_ADMIN
        )
    );
}
