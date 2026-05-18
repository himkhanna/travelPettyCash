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

import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * PATCH /api/v1/trips/{id} — rename, leader swap, member roster changes,
 * and the cascade-decline of pending allocations + transfers when a member
 * is removed.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Testcontainers
@EnabledIf("ae.gov.pdd.pettycash.trip.EditTripIT#dockerReachable")
class EditTripIT {

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
    static void wireProps(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", postgres::getJdbcUrl);
        r.add("spring.datasource.username", postgres::getUsername);
        r.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;

    private static final String AHMED_ID    = "00000000-0000-0000-0000-0000000a4d00";
    private static final String FATIMA_ID   = "00000000-0000-0000-0000-0000000fa71a";
    private static final String MOHAMMED_ID = "00000000-0000-0000-0000-00000000ed01";
    private static final String LAYLA_ID    = "00000000-0000-0000-0000-00000001a71a";

    @Test
    void adminCanRenameTrip() throws Exception {
        String tok = token("khalid");
        String tripId = pickKsa(tok);
        mvc.perform(patch("/api/v1/trips/" + tripId)
                .header("Authorization", "Bearer " + tok)
                .contentType(APPLICATION_JSON)
                .content("{\"name\":\"KSA Renamed\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.name").value("KSA Renamed"));
    }

    @Test
    void memberCannotEditTrip() throws Exception {
        String tok = token("ahmed");
        String tripId = pickKsa(tok);
        mvc.perform(patch("/api/v1/trips/" + tripId)
                .header("Authorization", "Bearer " + tok)
                .contentType(APPLICATION_JSON)
                .content("{\"name\":\"Not Allowed\"}"))
            .andExpect(status().isForbidden());
    }

    @Test
    void closedTripsCannotBeEdited() throws Exception {
        String tok = token("khalid");
        // Amman is closed in the seed.
        String tripId = mvc.perform(get("/api/v1/trips?status=CLOSED")
                .header("Authorization", "Bearer " + tok))
            .andReturn().getResponse().getContentAsString().split("\"id\":\"")[1].substring(0, 36);
        mvc.perform(patch("/api/v1/trips/" + tripId)
                .header("Authorization", "Bearer " + tok)
                .contentType(APPLICATION_JSON)
                .content("{\"name\":\"X\"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("trips/closed"));
    }

    @Test
    void leaderSwapPersists() throws Exception {
        String tok = token("khalid");
        // Use the Cairo trip so we don't disturb KSA-using tests in the same class.
        String tripId = pickByCountry(tok, "EG");
        // Cairo currently has Fatima as leader; swap to Layla (also a member).
        // First add Layla as a member of Cairo so she's eligible (seed has her on KSA + JOR).
        mvc.perform(patch("/api/v1/trips/" + tripId)
                .header("Authorization", "Bearer " + tok)
                .contentType(APPLICATION_JSON)
                .content("""
                    { "memberIds": ["%s","%s","%s"] }
                    """.formatted(AHMED_ID, MOHAMMED_ID, LAYLA_ID)))
            .andExpect(status().isOk());

        mvc.perform(patch("/api/v1/trips/" + tripId)
                .header("Authorization", "Bearer " + tok)
                .contentType(APPLICATION_JSON)
                .content("{\"leaderId\":\"" + LAYLA_ID + "\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.leaderId").value(LAYLA_ID));
    }

    @Test
    void removingMemberCascadeDeclinesTheirPendingAllocations() throws Exception {
        String adminTok = token("khalid");
        String tripId = pickKsa(adminTok);
        String zabeel = pickZabeel(adminTok);

        // Admin creates a pending allocation for Layla on KSA.
        JsonNode created = postJsonWithKey("/api/v1/trips/" + tripId + "/allocations",
            adminTok, "edit-cascade-1",
            """
                { "rows": [{
                    "toUserId": "%s",
                    "sourceId": "%s",
                    "amount": { "amount": 12345, "currency": "SAR" }
                }]}
                """.formatted(LAYLA_ID, zabeel));
        String allocId = created.get(0).path("id").asText();

        // Remove Layla from KSA roster (Ahmed + Mohammed only).
        mvc.perform(patch("/api/v1/trips/" + tripId)
                .header("Authorization", "Bearer " + adminTok)
                .contentType(APPLICATION_JSON)
                .content("""
                    { "memberIds": ["%s","%s"] }
                    """.formatted(AHMED_ID, MOHAMMED_ID)))
            .andExpect(status().isOk());

        // Her pending allocation should now be DECLINED.
        String allocList = mvc.perform(get("/api/v1/trips/" + tripId + "/allocations")
                .header("Authorization", "Bearer " + adminTok))
            .andReturn().getResponse().getContentAsString();
        String status = null;
        for (JsonNode a : json.readTree(allocList)) {
            if (a.path("id").asText().equals(allocId)) {
                status = a.path("status").asText();
            }
        }
        assert "DECLINED".equals(status) : "expected DECLINED, got " + status;
    }

    @Test
    void unknownMemberIs400() throws Exception {
        String tok = token("khalid");
        String tripId = pickKsa(tok);
        mvc.perform(patch("/api/v1/trips/" + tripId)
                .header("Authorization", "Bearer " + tok)
                .contentType(APPLICATION_JSON)
                .content("""
                    { "memberIds": ["11111111-1111-1111-1111-111111111111"] }
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("trips/member-not-found"));
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

    private String pickKsa(String tok) throws Exception {
        return pickByCountry(tok, "SA");
    }

    private String pickByCountry(String tok, String cc) throws Exception {
        String resp = mvc.perform(get("/api/v1/trips")
                .header("Authorization", "Bearer " + tok))
            .andReturn().getResponse().getContentAsString();
        for (JsonNode t : json.readTree(resp)) {
            if (cc.equals(t.path("countryCode").asText())) return t.path("id").asText();
        }
        throw new IllegalStateException("No trip for country " + cc);
    }

    private String pickZabeel(String tok) throws Exception {
        String resp = mvc.perform(get("/api/v1/sources")
                .header("Authorization", "Bearer " + tok))
            .andReturn().getResponse().getContentAsString();
        for (JsonNode s : json.readTree(resp)) {
            if ("Zabeel Office".equals(s.path("name").asText())) return s.path("id").asText();
        }
        throw new IllegalStateException("Zabeel not seeded");
    }

    private JsonNode postJsonWithKey(
        String path, String tok, String key, String body
    ) throws Exception {
        String resp = mvc.perform(post(path)
                .header("Authorization", "Bearer " + tok)
                .header("Idempotency-Key", key)
                .contentType(APPLICATION_JSON).content(body))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        return json.readTree(resp);
    }
}
