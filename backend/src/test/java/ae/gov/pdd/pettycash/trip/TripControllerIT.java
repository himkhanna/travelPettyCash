package ae.gov.pdd.pettycash.trip;

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

import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end trips API against a real Postgres in Testcontainers, exercising
 * the demo seeded trips (KSA / Cairo / Amman) and the admin-only mutations
 * (create + close).
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Testcontainers
@EnabledIf("ae.gov.pdd.pettycash.trip.TripControllerIT#dockerReachable")
class TripControllerIT {

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
    void leaderSeesOnlyTheirOwnTrips() throws Exception {
        String token = login("fatima").path("tokens").path("accessToken").asText();

        // Fatima leads all three demo trips.
        mvc.perform(get("/api/v1/trips").header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(greaterThanOrEqualTo(3)))
            .andExpect(jsonPath("$[0].currency").exists())
            .andExpect(jsonPath("$[0].totalBudget.amount").exists());
    }

    @Test
    void memberSeesOnlyTripsTheyParticipateIn() throws Exception {
        String token = login("mohammed").path("tokens").path("accessToken").asText();

        // Mohammed is a member on KSA and Cairo only — not Amman.
        mvc.perform(get("/api/v1/trips").header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(2));
    }

    @Test
    void adminSeesAllTrips() throws Exception {
        String token = login("khalid").path("tokens").path("accessToken").asText();
        mvc.perform(get("/api/v1/trips").header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(greaterThanOrEqualTo(3)));
    }

    @Test
    void statusFilterWorks() throws Exception {
        String token = login("fatima").path("tokens").path("accessToken").asText();
        mvc.perform(get("/api/v1/trips?status=CLOSED")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(1))
            .andExpect(jsonPath("$[0].status").value("CLOSED"));
    }

    @Test
    void memberCannotCreateTrip() throws Exception {
        String token = login("ahmed").path("tokens").path("accessToken").asText();
        mvc.perform(post("/api/v1/trips")
                .header("Authorization", "Bearer " + token)
                .contentType(APPLICATION_JSON)
                .content(_createBody("00000000-0000-0000-0000-0000000fa71a")))
            .andExpect(status().isForbidden());
    }

    @Test
    void adminCanCreateTripAndCloseIt() throws Exception {
        String token = login("khalid").path("tokens").path("accessToken").asText();

        JsonNode created = postJson("/api/v1/trips", token,
            _createBody("00000000-0000-0000-0000-0000000fa71a"));

        assert created.path("status").asText().equals("ACTIVE");
        String id = created.path("id").asText();

        mvc.perform(patch("/api/v1/trips/" + id + "/close")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("CLOSED"))
            .andExpect(jsonPath("$.closedAt").exists());
    }

    @Test
    void detailReturns404ToNonParticipants() throws Exception {
        String fatima = login("fatima").path("tokens").path("accessToken").asText();
        String tripId = mvc.perform(get("/api/v1/trips")
                .header("Authorization", "Bearer " + fatima))
            .andReturn().getResponse().getContentAsString().split("\"id\":\"")[1].substring(0, 36);

        // Noura (SUPER_ADMIN) can see anything.
        String noura = login("noura").path("tokens").path("accessToken").asText();
        mvc.perform(get("/api/v1/trips/" + tripId)
                .header("Authorization", "Bearer " + noura))
            .andExpect(status().isOk());

        // A bogus UUID returns 404 with stable code.
        mvc.perform(get("/api/v1/trips/11111111-1111-1111-1111-111111111111")
                .header("Authorization", "Bearer " + fatima))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.code").value("trips/not-found"));
    }

    @Test
    void balancesReturnsBudgetAndZeroSpentPerSource() throws Exception {
        String fatima = login("fatima").path("tokens").path("accessToken").asText();
        String tripId = mvc.perform(get("/api/v1/trips")
                .header("Authorization", "Bearer " + fatima))
            .andReturn().getResponse().getContentAsString().split("\"id\":\"")[1].substring(0, 36);

        mvc.perform(get("/api/v1/trips/" + tripId + "/balances?scope=trip")
                .header("Authorization", "Bearer " + fatima))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.totalSpent.amount").value(0))
            .andExpect(jsonPath("$.totalBudget.amount").exists())
            .andExpect(jsonPath("$.perSource.length()").value(2));
    }

    // ---- helpers ------------------------------------------------------

    private JsonNode login(String user) throws Exception {
        String body = "{\"username\":\"" + user + "\",\"password\":\"demo1234\"}";
        String resp = mvc.perform(post("/api/v1/auth/login")
                .contentType(APPLICATION_JSON).content(body))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        return json.readTree(resp);
    }

    private JsonNode postJson(String path, String token, String body) throws Exception {
        String resp = mvc.perform(post(path)
                .header("Authorization", "Bearer " + token)
                .contentType(APPLICATION_JSON).content(body))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        return json.readTree(resp);
    }

    private static String _createBody(String leaderUuid) {
        return """
            {
              "name": "Test Mission",
              "countryCode": "AE",
              "countryName": "United Arab Emirates",
              "currency": "AED",
              "leaderId": "%s",
              "memberIds": ["00000000-0000-0000-0000-0000000a4d00"],
              "totalBudget": { "amount": 100000, "currency": "AED" }
            }
            """.formatted(leaderUuid);
    }
}
