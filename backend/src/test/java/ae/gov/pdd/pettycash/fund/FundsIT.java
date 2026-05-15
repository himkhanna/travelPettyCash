package ae.gov.pdd.pettycash.fund;

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

import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end allocation + transfer flows: admin allocates to leader from the
 * Zabeel pool, leader accepts, /balances reflects the new received amount,
 * leader transfers to a member, etc. Plus the permission matrix +
 * idempotency replay.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Testcontainers
@EnabledIf("ae.gov.pdd.pettycash.fund.FundsIT#dockerReachable")
class FundsIT {

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

    // ---- Allocations ---------------------------------------------------

    @Test
    void adminAllocatesToLeader_leaderAccepts_balancesReflectInflow() throws Exception {
        String adminTok = token("khalid");
        String leaderTok = token("fatima");
        String tripId = pickKsaTripId(adminTok);
        String sourceId = pickZabeelSourceId(adminTok);
        String leaderId = "00000000-0000-0000-0000-0000000fa71a";

        // Admin allocates 5,000 SAR from Zabeel to Fatima.
        JsonNode created = postJsonWithKey("/api/v1/trips/" + tripId + "/allocations",
            adminTok, "key-alloc-1",
            """
                { "rows": [{
                    "toUserId": "%s",
                    "sourceId": "%s",
                    "amount": { "amount": 500000, "currency": "SAR" }
                }]}
                """.formatted(leaderId, sourceId));
        String allocId = created.get(0).path("id").asText();

        // Fatima accepts.
        mvc.perform(post("/api/v1/allocations/" + allocId + "/respond")
                .header("Authorization", "Bearer " + leaderTok)
                .contentType(APPLICATION_JSON)
                .content("{\"response\":\"ACCEPTED\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("ACCEPTED"));

        // Trip balances: trip-scope received jumps to 500000.
        mvc.perform(get("/api/v1/trips/" + tripId + "/balances?scope=trip")
                .header("Authorization", "Bearer " + leaderTok))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.totalBalance.amount").value(500000));
    }

    @Test
    void memberCannotAllocate() throws Exception {
        String ahmedTok = token("ahmed");
        String tripId = pickKsaTripId(ahmedTok);
        String sourceId = pickZabeelSourceId(ahmedTok);
        mvc.perform(post("/api/v1/trips/" + tripId + "/allocations")
                .header("Authorization", "Bearer " + ahmedTok)
                .header("Idempotency-Key", "k-m-forbid")
                .contentType(APPLICATION_JSON)
                .content("""
                    { "rows": [{
                        "toUserId": "00000000-0000-0000-0000-0000000a4d00",
                        "sourceId": "%s",
                        "amount": { "amount": 100, "currency": "SAR" }
                    }]}
                    """.formatted(sourceId)))
            .andExpect(status().isForbidden());
    }

    @Test
    void missingIdempotencyKeyOnAllocateIs400() throws Exception {
        String adminTok = token("khalid");
        String tripId = pickKsaTripId(adminTok);
        String sourceId = pickZabeelSourceId(adminTok);
        mvc.perform(post("/api/v1/trips/" + tripId + "/allocations")
                .header("Authorization", "Bearer " + adminTok)
                .contentType(APPLICATION_JSON)
                .content("""
                    { "rows": [{
                        "toUserId": "00000000-0000-0000-0000-0000000fa71a",
                        "sourceId": "%s",
                        "amount": { "amount": 100, "currency": "SAR" }
                    }]}
                    """.formatted(sourceId)))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("validation/missing-idempotency-key"));
    }

    @Test
    void idempotencyReplayReturnsSameAllocationIds() throws Exception {
        String adminTok = token("khalid");
        String tripId = pickKsaTripId(adminTok);
        String sourceId = pickZabeelSourceId(adminTok);
        String body = """
            { "rows": [{
                "toUserId": "00000000-0000-0000-0000-0000000fa71a",
                "sourceId": "%s",
                "amount": { "amount": 100, "currency": "SAR" }
            }]}
            """.formatted(sourceId);

        JsonNode first = postJsonWithKey("/api/v1/trips/" + tripId + "/allocations",
            adminTok, "replay-1", body);
        JsonNode second = postJsonWithKey("/api/v1/trips/" + tripId + "/allocations",
            adminTok, "replay-1", body);

        assert first.get(0).path("id").asText().equals(second.get(0).path("id").asText());
    }

    @Test
    void leaderCannotAllocateToNonMember() throws Exception {
        String leaderTok = token("fatima");
        String tripId = pickKsaTripId(leaderTok);
        String sourceId = pickZabeelSourceId(leaderTok);
        // Khalid (admin) is not a member of the KSA trip.
        mvc.perform(post("/api/v1/trips/" + tripId + "/allocations")
                .header("Authorization", "Bearer " + leaderTok)
                .header("Idempotency-Key", "k-nonmember")
                .contentType(APPLICATION_JSON)
                .content("""
                    { "rows": [{
                        "toUserId": "00000000-0000-0000-0000-0000000ad10d",
                        "sourceId": "%s",
                        "amount": { "amount": 100, "currency": "SAR" }
                    }]}
                    """.formatted(sourceId)))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("allocations/non-member-recipient"));
    }

    @Test
    void respondTwiceIs400() throws Exception {
        String adminTok = token("khalid");
        String leaderTok = token("fatima");
        String tripId = pickKsaTripId(adminTok);
        String sourceId = pickZabeelSourceId(adminTok);
        JsonNode created = postJsonWithKey("/api/v1/trips/" + tripId + "/allocations",
            adminTok, "key-respond-twice",
            """
                { "rows": [{
                    "toUserId": "00000000-0000-0000-0000-0000000fa71a",
                    "sourceId": "%s",
                    "amount": { "amount": 100, "currency": "SAR" }
                }]}
                """.formatted(sourceId));
        String id = created.get(0).path("id").asText();
        mvc.perform(post("/api/v1/allocations/" + id + "/respond")
                .header("Authorization", "Bearer " + leaderTok)
                .contentType(APPLICATION_JSON)
                .content("{\"response\":\"ACCEPTED\"}"))
            .andExpect(status().isOk());
        mvc.perform(post("/api/v1/allocations/" + id + "/respond")
                .header("Authorization", "Bearer " + leaderTok)
                .contentType(APPLICATION_JSON)
                .content("{\"response\":\"DECLINED\"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("allocations/already-responded"));
    }

    // ---- Transfers -----------------------------------------------------

    @Test
    void leaderTransfersToMember_recipientAccepts_meScopeReflectsBoth() throws Exception {
        String leaderTok = token("fatima");
        String memberTok = token("ahmed");
        String tripId = pickKsaTripId(leaderTok);
        String sourceId = pickZabeelSourceId(leaderTok);
        String ahmedId = "00000000-0000-0000-0000-0000000a4d00";

        JsonNode created = postJsonWithKey("/api/v1/trips/" + tripId + "/transfers",
            leaderTok, "xfer-1",
            """
                { "toUserId": "%s", "sourceId": "%s",
                  "amount": { "amount": 25000, "currency": "SAR" },
                  "note": "lunch" }
                """.formatted(ahmedId, sourceId));
        String xferId = created.path("id").asText();

        mvc.perform(post("/api/v1/transfers/" + xferId + "/respond")
                .header("Authorization", "Bearer " + memberTok)
                .contentType(APPLICATION_JSON)
                .content("{\"response\":\"ACCEPTED\"}"))
            .andExpect(status().isOk());

        // Ahmed: received 25000 at me-scope.
        mvc.perform(get("/api/v1/trips/" + tripId + "/balances?scope=me")
                .header("Authorization", "Bearer " + memberTok))
            .andExpect(jsonPath("$.totalBalance.amount").value(25000));
        // Fatima: sent 25000 at me-scope → -25000 received minus spent = ...
        // Without admin inflow, just -25000.
        mvc.perform(get("/api/v1/trips/" + tripId + "/balances?scope=me")
                .header("Authorization", "Bearer " + leaderTok))
            .andExpect(jsonPath("$.totalBalance.amount").value(-25000));
    }

    @Test
    void adminCannotInitiateTransfer() throws Exception {
        String adminTok = token("khalid");
        String tripId = pickKsaTripId(adminTok);
        String sourceId = pickZabeelSourceId(adminTok);
        mvc.perform(post("/api/v1/trips/" + tripId + "/transfers")
                .header("Authorization", "Bearer " + adminTok)
                .header("Idempotency-Key", "k-admin-xfer")
                .contentType(APPLICATION_JSON)
                .content("""
                    { "toUserId": "00000000-0000-0000-0000-0000000fa71a",
                      "sourceId": "%s",
                      "amount": { "amount": 100, "currency": "SAR" } }
                    """.formatted(sourceId)))
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

    private String pickKsaTripId(String token) throws Exception {
        String resp = mvc.perform(get("/api/v1/trips")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        for (JsonNode t : json.readTree(resp)) {
            if (t.path("countryCode").asText().equals("SA")) return t.path("id").asText();
        }
        throw new IllegalStateException("KSA trip not seeded");
    }

    private String pickZabeelSourceId(String token) throws Exception {
        String resp = mvc.perform(get("/api/v1/sources")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        for (JsonNode s : json.readTree(resp)) {
            if (s.path("name").asText().equals("Zabeel Office")) return s.path("id").asText();
        }
        throw new IllegalStateException("Zabeel source not seeded");
    }
}
