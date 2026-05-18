package ae.gov.pdd.pettycash.trip;

import ae.gov.pdd.pettycash.PostgresTestContainerConfig;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.List;
import java.util.Map;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Note: this test uses full @SpringBootTest + Testcontainers Postgres (not @WebMvcTest)
 * because the controllers depend on JPA repositories and a real Flyway-migrated schema.
 * @WebMvcTest is reserved for pure web-layer tests with mocked services.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(PostgresTestContainerConfig.class)
@Testcontainers
class TripControllerTest {

    @Autowired WebApplicationContext ctx;
    @Autowired ObjectMapper json;

    private MockMvc mvc() {
        return MockMvcBuilders.webAppContextSetup(ctx)
            .apply(SecurityMockMvcConfigurers.springSecurity())
            .build();
    }

    @Test
    @WithMockUser
    void listTripsReturnsOk() throws Exception {
        // Provide JWT with sub + role + username claims (mirrors CurrentUser expectations).
        mvc().perform(get("/api/v1/trips?status=ACTIVE")
                .with(jwt().jwt(j -> j
                    .subject("33333333-3333-3333-3333-333333333333")
                    .claim("username", "admin1")
                    .claim("role", "ADMIN"))
                    .authorities(new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_ADMIN"))))
            .andExpect(status().isOk());
    }

    @Test
    void createTripRequiresAdmin() throws Exception {
        String body = json.writeValueAsString(Map.of(
            "name", "Test Trip",
            "countryCode", "SA",
            "currency", "SAR",
            "leaderId", "22222222-2222-2222-2222-222222222222",
            "memberIds", List.of("11111111-1111-1111-1111-111111111111"),
            "totalBudget", Map.of("amount", 100000, "currency", "SAR")
        ));
        // MEMBER role — should be forbidden.
        mvc().perform(post("/api/v1/trips")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body)
                .with(jwt().jwt(j -> j
                    .subject("11111111-1111-1111-1111-111111111111")
                    .claim("username", "member1")
                    .claim("role", "MEMBER"))
                    .authorities(new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_MEMBER"))))
            .andExpect(status().isForbidden());
    }
}
