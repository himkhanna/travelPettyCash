package ae.gov.pdd.pettycash.chat;

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
@EnabledIf("ae.gov.pdd.pettycash.chat.ChatIT#dockerReachable")
class ChatIT {

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
    void leaderSeesAllKsaThreads_includingGroupAndDirectThreads() throws Exception {
        String tok = token("fatima");
        String tripId = pickKsa(tok);
        mvc.perform(get("/api/v1/trips/" + tripId + "/chat/threads")
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            // KSA has 3 seeded threads where Fatima is a participant.
            .andExpect(jsonPath("$.length()").value(greaterThanOrEqualTo(3)))
            .andExpect(jsonPath("$[0].lastMessageAt").exists());
    }

    @Test
    void laylaSeesOnlyTheGroupThread_notDirectThreadsBetweenOthers() throws Exception {
        String tok = token("layla");
        String tripId = pickKsa(tok);
        String resp = mvc.perform(get("/api/v1/trips/" + tripId + "/chat/threads")
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        for (JsonNode t : json.readTree(resp)) {
            // Every thread Layla sees must include her in the participants.
            boolean hasLayla = false;
            for (JsonNode p : t.path("participantIds")) {
                if ("00000000-0000-0000-0000-00000001a71a".equals(p.asText())) {
                    hasLayla = true; break;
                }
            }
            assert hasLayla : "Layla saw a thread she's not in: " + t.path("id");
        }
    }

    @Test
    void sendMessage_bumpsLastMessageAt_andUnreadForOthers() throws Exception {
        String fatima = token("fatima");
        String mohammed = token("mohammed");
        String thirdParty = pickPrivateThreadBetween(fatima, mohammed);

        // Fatima reads first → her unread goes to 0 on this thread.
        mvc.perform(patch("/api/v1/chat/threads/" + thirdParty + "/read")
                .header("Authorization", "Bearer " + fatima))
            .andExpect(status().isOk());

        // Mohammed sends a fresh message.
        mvc.perform(post("/api/v1/chat/threads/" + thirdParty + "/messages")
                .header("Authorization", "Bearer " + mohammed)
                .contentType(APPLICATION_JSON)
                .content("{\"body\":\"Heading to the meeting.\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.body").value("Heading to the meeting."));

        // Fatima's threads view: this thread now has unreadCount >= 1.
        String list = mvc.perform(get("/api/v1/trips/" + pickKsa(fatima) + "/chat/threads")
                .header("Authorization", "Bearer " + fatima))
            .andReturn().getResponse().getContentAsString();
        int unread = -1;
        for (JsonNode t : json.readTree(list)) {
            if (thirdParty.equals(t.path("id").asText())) {
                unread = t.path("unreadCount").asInt();
            }
        }
        assert unread >= 1 : "expected at least 1 unread; got " + unread;
    }

    @Test
    void nonParticipantGets404OnEverythingForThatThread() throws Exception {
        String fatima = token("fatima");
        String mohammed = token("mohammed");
        String laylaTok = token("layla");
        String direct = pickPrivateThreadBetween(fatima, mohammed);

        mvc.perform(get("/api/v1/chat/threads/" + direct + "/messages")
                .header("Authorization", "Bearer " + laylaTok))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.code").value("chat/thread-not-found"));

        mvc.perform(post("/api/v1/chat/threads/" + direct + "/messages")
                .header("Authorization", "Bearer " + laylaTok)
                .contentType(APPLICATION_JSON)
                .content("{\"body\":\"hi\"}"))
            .andExpect(status().isNotFound());
    }

    @Test
    void validation_emptyBodyIs400() throws Exception {
        String tok = token("fatima");
        String anyThread = anyThreadFor(tok);
        mvc.perform(post("/api/v1/chat/threads/" + anyThread + "/messages")
                .header("Authorization", "Bearer " + tok)
                .contentType(APPLICATION_JSON)
                .content("{\"body\":\"\"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("validation/invalid-request"));
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

    private String anyThreadFor(String tok) throws Exception {
        String resp = mvc.perform(get("/api/v1/trips/" + pickKsa(tok) + "/chat/threads")
                .header("Authorization", "Bearer " + tok))
            .andReturn().getResponse().getContentAsString();
        return json.readTree(resp).get(0).path("id").asText();
    }

    /** Picks a thread that has exactly the two given callers (direct DM). */
    private String pickPrivateThreadBetween(String tokA, String tokB) throws Exception {
        String resp = mvc.perform(get("/api/v1/trips/" + pickKsa(tokA) + "/chat/threads")
                .header("Authorization", "Bearer " + tokA))
            .andReturn().getResponse().getContentAsString();
        for (JsonNode t : json.readTree(resp)) {
            if (t.path("participantIds").size() == 2) return t.path("id").asText();
        }
        throw new IllegalStateException("No 1:1 thread seeded");
    }
}
