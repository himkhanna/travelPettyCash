package ae.gov.pdd.pettycash;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * Shared Postgres container for integration-flavoured tests.
 * Spring Boot's @ServiceConnection wires datasource URL/user/pass automatically.
 */
@TestConfiguration(proxyBeanMethods = false)
public class PostgresTestContainerConfig {

    @Bean
    @ServiceConnection
    PostgreSQLContainer<?> postgres() {
        return new PostgreSQLContainer<>(DockerImageName.parse("postgres:15"))
            .withDatabaseName("pettycash_test")
            .withUsername("pettycash")
            .withPassword("pettycash");
    }
}
