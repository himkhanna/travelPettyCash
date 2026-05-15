package ae.gov.pdd.pettycash.auth;

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

import static org.hamcrest.Matchers.equalTo;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end auth flow against a real Postgres in Testcontainers:
 * login → /me → refresh → /me with new token → reuse-old-refresh → 401.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Testcontainers
@EnabledIf("ae.gov.pdd.pettycash.auth.AuthControllerIT#dockerReachable")
class AuthControllerIT {

    /**
     * Skip the IT cleanly when no Docker daemon is reachable from docker-java.
     * On CI Linux runners this is always true; on dev machines running Docker
     * Desktop with hardened-socket mode this returns false and JUnit reports
     * the class as skipped rather than failing the whole build.
     */
    @SuppressWarnings("unused") // invoked reflectively by @EnabledIf
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
    void loginIssuesTokensAndMeReturnsTheCallerProfile() throws Exception {
        JsonNode login = login("fatima", "demo1234");
        String access = login.path("tokens").path("accessToken").asText();

        mvc.perform(get("/api/v1/me").header("Authorization", "Bearer " + access))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.username").value("fatima"))
            .andExpect(jsonPath("$.role").value("LEADER"))
            .andExpect(jsonPath("$.displayNameAr").value("فاطمة الهاشمي"));
    }

    @Test
    void loginRejectsBadCredentialsWithProblemDetail() throws Exception {
        mvc.perform(post("/api/v1/auth/login")
                .contentType(APPLICATION_JSON)
                .content("""
                    {"username":"fatima","password":"wrong-password"}
                    """))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.code").value("auth/invalid-credentials"))
            .andExpect(jsonPath("$.title").value(equalTo("Invalid username or password")));
    }

    @Test
    void meReturns401WhenNoBearerHeader() throws Exception {
        mvc.perform(get("/api/v1/me"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void refreshRotatesTokenAndOldRefreshNoLongerWorks() throws Exception {
        JsonNode login = login("ahmed", "demo1234");
        String firstRefresh = login.path("tokens").path("refreshToken").asText();

        // First refresh succeeds and returns NEW tokens.
        JsonNode rotated = postJson("/api/v1/auth/refresh",
            "{\"refreshToken\":\"" + firstRefresh + "\"}");
        String secondAccess = rotated.path("tokens").path("accessToken").asText();
        String secondRefresh = rotated.path("tokens").path("refreshToken").asText();

        // New access works.
        mvc.perform(get("/api/v1/me").header("Authorization", "Bearer " + secondAccess))
            .andExpect(status().isOk());

        // Re-using the FIRST refresh now is replay → 401.
        mvc.perform(post("/api/v1/auth/refresh")
                .contentType(APPLICATION_JSON)
                .content("{\"refreshToken\":\"" + firstRefresh + "\"}"))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.code").value("auth/invalid-refresh"));

        // And the replay attempt revoked the chain — even the legit second
        // refresh that was issued in the previous step is now invalid.
        mvc.perform(post("/api/v1/auth/refresh")
                .contentType(APPLICATION_JSON)
                .content("{\"refreshToken\":\"" + secondRefresh + "\"}"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void validationErrorOnEmptyUsername() throws Exception {
        mvc.perform(post("/api/v1/auth/login")
                .contentType(APPLICATION_JSON)
                .content("""
                    {"username":"","password":"demo1234"}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("validation/invalid-request"))
            .andExpect(jsonPath("$.errors[0].field").value("username"));
    }

    // ---- helpers ------------------------------------------------------

    private JsonNode login(String user, String password) throws Exception {
        return postJson("/api/v1/auth/login",
            "{\"username\":\"" + user + "\",\"password\":\"" + password + "\"}");
    }

    private JsonNode postJson(String path, String body) throws Exception {
        String resp = mvc.perform(post(path).contentType(APPLICATION_JSON).content(body))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        return json.readTree(resp);
    }
}
