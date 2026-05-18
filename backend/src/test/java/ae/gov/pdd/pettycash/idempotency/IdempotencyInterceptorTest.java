package ae.gov.pdd.pettycash.idempotency;

import ae.gov.pdd.pettycash.PostgresTestContainerConfig;
import ae.gov.pdd.pettycash.storage.StorageService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Map;
import java.util.UUID;

import static org.mockito.Mockito.mock;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@ActiveProfiles("test")
@Import({PostgresTestContainerConfig.class, IdempotencyInterceptorTest.StubStorage.class})
@Testcontainers
class IdempotencyInterceptorTest {

    private static final String TRIP_ID = "cccccccc-0000-0000-0000-000000000001";
    private static final String LEADER_ID = "22222222-2222-2222-2222-222222222222";
    private static final String SOURCE_ID = "aaaaaaaa-0000-0000-0000-000000000001";
    private static final String CATEGORY = "FOOD";

    @Autowired WebApplicationContext ctx;
    @Autowired ObjectMapper json;

    private MockMvc mvc() {
        return MockMvcBuilders.webAppContextSetup(ctx).apply(springSecurity()).build();
    }

    private String body(UUID id) throws Exception {
        return json.writeValueAsString(Map.of(
            "id", id.toString(),
            "sourceId", SOURCE_ID,
            "categoryCode", CATEGORY,
            "amount", Map.of("amount", 1500, "currency", "SAR"),
            "quantity", 1,
            "details", "lunch",
            "occurredAt", "2026-05-18T12:00:00+03:00"
        ));
    }

    private String bodyWithVendor(UUID id, String vendor) throws Exception {
        return json.writeValueAsString(Map.of(
            "id", id.toString(),
            "sourceId", SOURCE_ID,
            "categoryCode", CATEGORY,
            "amount", Map.of("amount", 1500, "currency", "SAR"),
            "quantity", 1,
            "details", "lunch",
            "vendor", vendor,
            "occurredAt", "2026-05-18T12:00:00+03:00"
        ));
    }

    private static org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder asLeader(
            org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder rb) {
        return rb.with(jwt().jwt(j -> j
                .subject(LEADER_ID)
                .claim("username", "leader1")
                .claim("role", "LEADER"))
            .authorities(new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_LEADER")));
    }

    @Test
    void missingHeaderReturns400() throws Exception {
        UUID expenseId = UUID.randomUUID();
        mvc().perform(asLeader(post("/api/v1/trips/{tripId}/expenses", TRIP_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body(expenseId))))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REQUIRED"));
    }

    @Test
    void sameKeySameBodyReplaysResponse() throws Exception {
        String key = "idem-" + UUID.randomUUID();
        UUID expenseId = UUID.randomUUID();
        String body = body(expenseId);
        // First call — 201.
        mvc().perform(asLeader(post("/api/v1/trips/{tripId}/expenses", TRIP_ID)
                .header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.id").value(expenseId.toString()));
        // Second call — replayed 201 with the same body.
        mvc().perform(asLeader(post("/api/v1/trips/{tripId}/expenses", TRIP_ID)
                .header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.id").value(expenseId.toString()));
    }

    @Test
    void sameKeyDifferentBodyReturns409() throws Exception {
        String key = "idem-" + UUID.randomUUID();
        UUID a = UUID.randomUUID();
        UUID b = UUID.randomUUID();
        mvc().perform(asLeader(post("/api/v1/trips/{tripId}/expenses", TRIP_ID)
                .header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON)
                .content(bodyWithVendor(a, "Vendor A"))))
            .andExpect(status().isCreated());
        mvc().perform(asLeader(post("/api/v1/trips/{tripId}/expenses", TRIP_ID)
                .header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON)
                .content(bodyWithVendor(b, "Vendor B"))))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_CONFLICT"));
    }

    @TestConfiguration
    static class StubStorage {
        @Bean
        @Primary
        StorageService storageService() {
            return mock(StorageService.class);
        }
    }
}
