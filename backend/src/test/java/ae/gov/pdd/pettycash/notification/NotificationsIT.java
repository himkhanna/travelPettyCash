package ae.gov.pdd.pettycash.notification;

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

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Testcontainers
@EnabledIf("ae.gov.pdd.pettycash.notification.NotificationsIT#dockerReachable")
class NotificationsIT {

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

    @Test
    void adminAllocates_recipientGetsUnreadNotification_respondFlipsItActed() throws Exception {
        String adminTok = token("khalid");
        String leaderTok = token("fatima");
        String tripId = pickKsa(adminTok);
        String zabeel = pickZabeel(adminTok);
        String fatimaId = "00000000-0000-0000-0000-0000000fa71a";

        // Admin allocates → Fatima gets one unread notification.
        long before = unreadCount(leaderTok);
        JsonNode created = postJsonWithKey("/api/v1/trips/" + tripId + "/allocations",
            adminTok, "notif-alloc-1",
            """
                { "rows": [{
                    "toUserId": "%s",
                    "sourceId": "%s",
                    "amount": { "amount": 50000, "currency": "SAR" }
                }]}
                """.formatted(fatimaId, zabeel));
        String allocId = created.get(0).path("id").asText();

        assert unreadCount(leaderTok) == before + 1
            : "expected unread to grow by 1; before=" + before;

        // The notification carries the allocation id in its payload and ref.
        String notifId = findUnreadByRef(leaderTok, "ALLOCATION_RECEIVED", allocId);

        // Fatima accepts the allocation directly.
        mvc.perform(post("/api/v1/allocations/" + allocId + "/respond")
                .header("Authorization", "Bearer " + leaderTok)
                .contentType(APPLICATION_JSON)
                .content("{\"response\":\"ACCEPTED\"}"))
            .andExpect(status().isOk());

        // The notification she had for that allocation is now ACTED.
        String listBody = mvc.perform(get("/api/v1/notifications")
                .header("Authorization", "Bearer " + leaderTok))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        String state = null;
        for (JsonNode n : json.readTree(listBody)) {
            if (n.path("id").asText().equals(notifId)) state = n.path("state").asText();
        }
        assert "ACTED".equals(state) : "expected ACTED, got " + state;
    }

    @Test
    void markRead_flipsStateAndReadAt() throws Exception {
        // Drop one notification by allocating to the leader, then PATCH read.
        String adminTok = token("khalid");
        String leaderTok = token("fatima");
        String tripId = pickKsa(adminTok);
        String zabeel = pickZabeel(adminTok);
        postJsonWithKey("/api/v1/trips/" + tripId + "/allocations",
            adminTok, "notif-read-1",
            """
                { "rows": [{
                    "toUserId": "00000000-0000-0000-0000-0000000fa71a",
                    "sourceId": "%s",
                    "amount": { "amount": 100, "currency": "SAR" }
                }]}
                """.formatted(zabeel));
        String resp = mvc.perform(get("/api/v1/notifications")
                .header("Authorization", "Bearer " + leaderTok))
            .andReturn().getResponse().getContentAsString();
        String first = json.readTree(resp).get(0).path("id").asText();

        mvc.perform(patch("/api/v1/notifications/" + first + "/read")
                .header("Authorization", "Bearer " + leaderTok))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.state").value("READ"))
            .andExpect(jsonPath("$.readAt").exists());
    }

    @Test
    void otherUsersNotificationsAreInvisible() throws Exception {
        String adminTok = token("khalid");
        String leaderTok = token("fatima");
        String mohammedTok = token("mohammed");
        String tripId = pickKsa(adminTok);
        String zabeel = pickZabeel(adminTok);

        // Allocate to Fatima → Fatima has a notification, Mohammed doesn't see it.
        JsonNode created = postJsonWithKey("/api/v1/trips/" + tripId + "/allocations",
            adminTok, "notif-isolate-1",
            """
                { "rows": [{
                    "toUserId": "00000000-0000-0000-0000-0000000fa71a",
                    "sourceId": "%s",
                    "amount": { "amount": 1234, "currency": "SAR" }
                }]}
                """.formatted(zabeel));
        String allocId = created.get(0).path("id").asText();
        String notifId = findUnreadByRef(leaderTok, "ALLOCATION_RECEIVED", allocId);

        // Mohammed PATCHing Fatima's notification id → 404.
        mvc.perform(patch("/api/v1/notifications/" + notifId + "/read")
                .header("Authorization", "Bearer " + mohammedTok))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.code").value("notifications/not-found"));

        // Mohammed's inbox doesn't contain the row.
        String list = mvc.perform(get("/api/v1/notifications")
                .header("Authorization", "Bearer " + mohammedTok))
            .andReturn().getResponse().getContentAsString();
        for (JsonNode n : json.readTree(list)) {
            assert !n.path("id").asText().equals(notifId)
                : "Mohammed should not see Fatima's notification";
        }
    }

    @Test
    void transferRespond_fansAcceptedToSender() throws Exception {
        String leaderTok = token("fatima");
        String memberTok = token("ahmed");
        String tripId = pickKsa(leaderTok);
        String zabeel = pickZabeel(leaderTok);

        // Fatima → Ahmed transfer; Ahmed accepts.
        JsonNode xfer = postJsonWithKey("/api/v1/trips/" + tripId + "/transfers",
            leaderTok, "notif-xfer-1",
            """
                { "toUserId": "00000000-0000-0000-0000-0000000a4d00",
                  "sourceId": "%s",
                  "amount": { "amount": 5000, "currency": "SAR" } }
                """.formatted(zabeel));
        String xferId = xfer.path("id").asText();

        long fatimaUnreadBefore = unreadCount(leaderTok);
        mvc.perform(post("/api/v1/transfers/" + xferId + "/respond")
                .header("Authorization", "Bearer " + memberTok)
                .contentType(APPLICATION_JSON)
                .content("{\"response\":\"ACCEPTED\"}"))
            .andExpect(status().isOk());

        // Fatima now has a TRANSFER_ACCEPTED notification.
        assert unreadCount(leaderTok) >= fatimaUnreadBefore + 1;
        String list = mvc.perform(get("/api/v1/notifications")
                .header("Authorization", "Bearer " + leaderTok))
            .andReturn().getResponse().getContentAsString();
        boolean found = false;
        for (JsonNode n : json.readTree(list)) {
            if ("TRANSFER_ACCEPTED".equals(n.path("type").asText())
                && xferId.equals(n.path("refId").asText())) {
                found = true; break;
            }
        }
        assert found : "expected a TRANSFER_ACCEPTED notification for the sender";
    }

    @Test
    void unreadCountEndpoint() throws Exception {
        String tok = token("ahmed");
        mvc.perform(get("/api/v1/notifications/unread-count")
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.count").value(greaterThanOrEqualTo(0)));
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
        String resp = mvc.perform(get("/api/v1/trips")
                .header("Authorization", "Bearer " + tok))
            .andReturn().getResponse().getContentAsString();
        for (JsonNode t : json.readTree(resp)) {
            if ("SA".equals(t.path("countryCode").asText())) return t.path("id").asText();
        }
        throw new IllegalStateException("KSA trip not seeded");
    }

    private String pickZabeel(String tok) throws Exception {
        String resp = mvc.perform(get("/api/v1/sources")
                .header("Authorization", "Bearer " + tok))
            .andReturn().getResponse().getContentAsString();
        for (JsonNode s : json.readTree(resp)) {
            if ("Zabeel Office".equals(s.path("name").asText())) return s.path("id").asText();
        }
        throw new IllegalStateException("Zabeel source not seeded");
    }

    private long unreadCount(String tok) throws Exception {
        String resp = mvc.perform(get("/api/v1/notifications/unread-count")
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        return json.readTree(resp).path("count").asLong();
    }

    private String findUnreadByRef(String tok, String type, String refId) throws Exception {
        String resp = mvc.perform(get("/api/v1/notifications")
                .header("Authorization", "Bearer " + tok))
            .andReturn().getResponse().getContentAsString();
        for (JsonNode n : json.readTree(resp)) {
            if (type.equals(n.path("type").asText())
                && refId.equals(n.path("refId").asText())) {
                return n.path("id").asText();
            }
        }
        throw new IllegalStateException("Did not find " + type + " notification for ref " + refId);
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
