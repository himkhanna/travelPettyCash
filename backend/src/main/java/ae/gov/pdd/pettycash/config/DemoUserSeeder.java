package ae.gov.pdd.pettycash.config;

import ae.gov.pdd.pettycash.config.DemoPersonas.Persona;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Inserts the six demo personas (matching {@code mobile/assets/demo/users.json})
 * on first boot when {@code pdd.demo.seed=true}. All seeded passwords are
 * {@code demo1234}. Idempotent: skips users that already exist.
 *
 * <p>Not enabled in production. Listed in CLAUDE.md §16 open question — replace
 * with UAE Pass / PDD AD provisioning when that decision is made.
 */
@Component
@Order(10)
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
        for (Persona p : DemoPersonas.ALL) {
            if (users.existsByUsername(p.username())) continue;
            users.save(new User(
                p.id(),
                p.username(),
                p.displayName(),
                p.displayNameAr(),
                p.email(),
                hash,
                p.role()
            ));
            seeded++;
        }
        log.info("DemoUserSeeder seeded {} user(s); password is '{}'.", seeded, DEMO_PASSWORD);
    }
}
