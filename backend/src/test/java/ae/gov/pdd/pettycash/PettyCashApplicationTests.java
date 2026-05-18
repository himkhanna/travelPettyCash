package ae.gov.pdd.pettycash;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Smoke test: full Spring context boots with a Testcontainers Postgres backing it.
 * Uses Testcontainers (not H2) because Flyway V001 uses pgcrypto + JSONB.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(PostgresTestContainerConfig.class)
@Testcontainers
class PettyCashApplicationTests {

    @Test
    void contextLoads() {
        // Pass = the context boots, Flyway migrates, and JPA validates the schema.
    }
}
