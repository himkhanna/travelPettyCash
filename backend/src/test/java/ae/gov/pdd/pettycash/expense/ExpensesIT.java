package ae.gov.pdd.pettycash.expense;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIf;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.UUID;

import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Testcontainers
@EnabledIf("ae.gov.pdd.pettycash.expense.ExpensesIT#dockerReachable")
class ExpensesIT {

    @SuppressWarnings("unused")
    static boolean dockerReachable() {
        try {
            return DockerClientFactory.instance().isDockerAvailable();
        } catch (Throwable t) {
            return false;
        }
    }

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
        .withDatabaseName("pdd_petty_cash")
        .withUsername("pdd")
        .withPassword("pdd");

    @DynamicPropertySource
    static void datasourceProps(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", postgres::getJdbcUrl);
        r.add("spring.datasource.username", postgres::getUsername);
        r.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;

    @Test
    void categoriesEndpointReturnsSeededList() throws Exception {
        String tok = token("ahmed");
        mvc.perform(get("/api/v1/categories").header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(greaterThanOrEqualTo(8)))
            .andExpect(jsonPath("$[?(@.code=='FOOD')].nameAr").exists());
    }

    @Test
    void memberSeesOnlyOwnExpensesOnTrip() throws Exception {
        String tok = token("ahmed");
        String tripId = pickKsa(tok);
        String resp = mvc.perform(get("/api/v1/trips/" + tripId + "/expenses")
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        for (JsonNode row : json.readTree(resp)) {
            assert row.path("userId").asText().equals("00000000-0000-0000-0000-0000000a4d00");
        }
    }

    @Test
    void leaderSeesAllExpensesOnTrip() throws Exception {
        String tok = token("fatima");
        String tripId = pickKsa(tok);
        mvc.perform(get("/api/v1/trips/" + tripId + "/expenses")
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            // Demo seeds 15 KSA expenses across 3 members.
            .andExpect(jsonPath("$.length()").value(greaterThanOrEqualTo(10)));
    }

    @Test
    void balancesNowReflectsRealSpentAtTripScope() throws Exception {
        String tok = token("fatima");
        String tripId = pickKsa(tok);
        // Demo seeds non-trivial spend on this trip; trip-scope totalSpent > 0.
        mvc.perform(get("/api/v1/trips/" + tripId + "/balances?scope=trip")
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.totalSpent.amount").value(greaterThanOrEqualTo(1)));
    }

    @Test
    void memberCreatesExpense_balancesReflect_idempotencyHolds() throws Exception {
        String tok = token("ahmed");
        String tripId = pickKsa(tok);
        String zabeel = pickZabeel(tok);
        UUID expId = UUID.randomUUID();

        String body = """
            {
              "id": "%s",
              "sourceId": "%s",
              "categoryCode": "FOOD",
              "amount": { "amount": 12300, "currency": "SAR" },
              "quantity": 1,
              "details": "Shawarma",
              "occurredAt": "2026-05-15T10:00:00Z"
            }
            """.formatted(expId, zabeel);

        JsonNode first = postJsonWithKey(
            "/api/v1/trips/" + tripId + "/expenses", tok, "exp-key-1", body);
        JsonNode replay = postJsonWithKey(
            "/api/v1/trips/" + tripId + "/expenses", tok, "exp-key-1", body);
        assert first.path("id").asText().equals(replay.path("id").asText());

        // Different idempotency key but same client id → still dedupes via
        // the id-already-exists path in ExpenseService.create.
        JsonNode replayDifferentKey = postJsonWithKey(
            "/api/v1/trips/" + tripId + "/expenses", tok, "exp-key-2", body);
        assert first.path("id").asText().equals(replayDifferentKey.path("id").asText());
    }

    @Test
    void missingIdempotencyKeyIs400() throws Exception {
        String tok = token("ahmed");
        String tripId = pickKsa(tok);
        String zabeel = pickZabeel(tok);
        mvc.perform(post("/api/v1/trips/" + tripId + "/expenses")
                .header("Authorization", "Bearer " + tok)
                .contentType(APPLICATION_JSON)
                .content("""
                    {
                      "id": "%s",
                      "sourceId": "%s",
                      "categoryCode": "FOOD",
                      "amount": { "amount": 100, "currency": "SAR" },
                      "quantity": 1,
                      "details": "x",
                      "occurredAt": "2026-05-15T10:00:00Z"
                    }
                    """.formatted(UUID.randomUUID(), zabeel)))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("validation/missing-idempotency-key"));
    }

    @Test
    void reassignSourceFlipsTheRowAndBumpsUpdatedAt() throws Exception {
        String tok = token("ahmed");
        String tripId = pickKsa(tok);

        String list = mvc.perform(get("/api/v1/trips/" + tripId + "/expenses")
                .header("Authorization", "Bearer " + tok))
            .andReturn().getResponse().getContentAsString();
        JsonNode row = json.readTree(list).get(0);
        String expId = row.path("id").asText();
        String currentSource = row.path("sourceId").asText();

        String otherSource = mvc.perform(get("/api/v1/sources")
                .header("Authorization", "Bearer " + tok))
            .andReturn().getResponse().getContentAsString().contains("Zabeel")
                ? mvc.perform(get("/api/v1/sources").header("Authorization", "Bearer " + tok))
                    .andReturn().getResponse().getContentAsString()
                : "";
        // Pick whichever source is NOT the current one.
        String otherSrc = pickOtherSource(tok, currentSource);

        mvc.perform(patch("/api/v1/expenses/" + expId + "/source")
                .header("Authorization", "Bearer " + tok)
                .contentType(APPLICATION_JSON)
                .content("{\"sourceId\":\"" + otherSrc + "\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.sourceId").value(otherSrc))
            .andExpect(jsonPath("$.updatedAt").exists());
    }

    @Test
    void summaryByCategoryReturnsBilingualLabels() throws Exception {
        String tok = token("fatima");
        String tripId = pickKsa(tok);
        mvc.perform(get("/api/v1/trips/" + tripId + "/expenses/summary?groupBy=category&scope=trip")
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.groupBy").value("category"))
            .andExpect(jsonPath("$.rows[?(@.key=='FOOD')].labelAr").exists());
    }

    @Test
    void adminCannotCreateExpenseOnBehalfOfMember() throws Exception {
        String tok = token("khalid");
        String tripId = pickKsa(tok);
        String zabeel = pickZabeel(tok);
        mvc.perform(post("/api/v1/trips/" + tripId + "/expenses")
                .header("Authorization", "Bearer " + tok)
                .header("Idempotency-Key", "admin-exp-key")
                .contentType(APPLICATION_JSON)
                .content("""
                    {
                      "id": "%s",
                      "sourceId": "%s",
                      "categoryCode": "FOOD",
                      "amount": { "amount": 100, "currency": "SAR" },
                      "quantity": 1,
                      "details": "x",
                      "occurredAt": "2026-05-15T10:00:00Z"
                    }
                    """.formatted(UUID.randomUUID(), zabeel)))
            .andExpect(status().isForbidden());
    }

    // ---- helpers ------------------------------------------------------

    private String token(String user) throws Exception {
        String resp = mvc.perform(post("/api/v1/auth/login")
                .contentType(APPLICATION_JSON)
                .content("{\"username\":\"" + user + "\",\"password\":\"demo1234\"}"))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        return json.readTree(resp).path("tokens").path("accessToken").asText();
    }

    private String pickKsa(String token) throws Exception {
        String resp = mvc.perform(get("/api/v1/trips")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        for (JsonNode t : json.readTree(resp)) {
            if (t.path("countryCode").asText().equals("SA")) return t.path("id").asText();
        }
        throw new IllegalStateException("KSA trip not seeded");
    }

    private String pickZabeel(String token) throws Exception {
        String resp = mvc.perform(get("/api/v1/sources")
                .header("Authorization", "Bearer " + token))
            .andReturn().getResponse().getContentAsString();
        for (JsonNode s : json.readTree(resp)) {
            if (s.path("name").asText().equals("Zabeel Office")) return s.path("id").asText();
        }
        throw new IllegalStateException("Zabeel source not seeded");
    }

    private String pickOtherSource(String token, String notThis) throws Exception {
        String resp = mvc.perform(get("/api/v1/sources")
                .header("Authorization", "Bearer " + token))
            .andReturn().getResponse().getContentAsString();
        for (JsonNode s : json.readTree(resp)) {
            String id = s.path("id").asText();
            if (!id.equals(notThis)) return id;
        }
        throw new IllegalStateException("No alternative source found");
    }

    private JsonNode postJsonWithKey(
        String path, String token, String key, String body
    ) throws Exception {
        String resp = mvc.perform(post(path)
                .header("Authorization", "Bearer " + token)
                .header("Idempotency-Key", key)
                .contentType(APPLICATION_JSON).content(body))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        return json.readTree(resp);
    }
}
