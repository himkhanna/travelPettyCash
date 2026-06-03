package ae.gov.pdd.pettycash.auth.sso;

import ae.gov.pdd.pettycash.config.DemoPersonas;
import ae.gov.pdd.pettycash.user.UserRole;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIf;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Full end-to-end SSO flow against the in-process {@link MockIdpController}
 * and a real Postgres (Testcontainers): start → authorize page → approve →
 * callback → exchange → /me. This exercises the otherwise-untested half of
 * {@link DubaiGovSsoService} — the real outbound token + userinfo HTTP
 * calls, claim→role mapping, the V011 external_id upsert, and JWT minting.
 *
 * <p>Uses a real web server ({@code RANDOM_PORT}) rather than MockMvc
 * because the service makes real HTTP calls back to the mock IdP endpoints
 * on the same host; MockMvc has no listening socket. {@link MockIdpReconfig}
 * repoints the OIDC URIs to {@code :8080} at boot from the default redirect
 * URI, so {@link #pointMockIdpAtRunningPort()} fixes them to the actual
 * random port before each test.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
@Testcontainers
@EnabledIf("ae.gov.pdd.pettycash.auth.sso.DubaiGovSsoIT#dockerReachable")
class DubaiGovSsoIT {

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
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", postgres::getJdbcUrl);
        r.add("spring.datasource.username", postgres::getUsername);
        r.add("spring.datasource.password", postgres::getPassword);
        // Mount the SSO endpoints + the dev mock IdP for this IT.
        r.add("pdd.auth.dubaigov.enabled", () -> "true");
        r.add("pdd.auth.dubaigov.mock-idp", () -> "true");
    }

    @LocalServerPort int port;
    @Autowired DubaiGovProperties dubaigov;
    @Autowired ObjectMapper json;

    private final HttpClient http = HttpClient.newBuilder()
        .followRedirects(HttpClient.Redirect.NEVER)
        .build();

    private String base;

    @BeforeEach
    void pointMockIdpAtRunningPort() {
        base = "http://localhost:" + port;
        dubaigov.setEnabled(true);
        dubaigov.setRedirectUri(base + "/api/v1/auth/sso/callback");
        dubaigov.setAuthorizationUri(base + "/api/v1/auth/sso/mock/authorize");
        dubaigov.setTokenUri(base + "/api/v1/auth/sso/mock/token");
        dubaigov.setUserInfoUri(base + "/api/v1/auth/sso/mock/userinfo");
        // The role-mapping defaults to empty; supply it so the mock's
        // group strings map onto roles (mirrors application-local.yml).
        dubaigov.setRoleMapping(Map.of(
            "pdd.delegation-expenses.super-admin", UserRole.SUPER_ADMIN,
            "pdd.delegation-expenses.admin", UserRole.ADMIN,
            "pdd.delegation-expenses.leader", UserRole.LEADER,
            "pdd.delegation-expenses.member", UserRole.MEMBER
        ));
    }

    @Test
    void adminSignInLinksTheExistingAccountAndMintsAUsableToken() throws Exception {
        JsonNode exchanged = runFullFlow(DemoPersonas.KHALID.id().toString());

        // Federated onto the EXISTING khalid account, not a new synthetic
        // user — same username/email, role preserved.
        assertThat(exchanged.path("user").path("role").asText()).isEqualTo("ADMIN");
        assertThat(exchanged.path("user").path("username").asText()).isEqualTo("khalid");
        assertThat(exchanged.path("user").path("email").asText())
            .isEqualTo("khalid@protocol.gov.ae");
        assertThat(exchanged.path("user").path("id").asText())
            .isEqualTo(DemoPersonas.KHALID.id().toString());

        // The minted access token actually works against a protected route.
        String access = exchanged.path("tokens").path("accessToken").asText();
        HttpResponse<String> me = http.send(
            HttpRequest.newBuilder(URI.create(base + "/api/v1/me"))
                .header("Authorization", "Bearer " + access).GET().build(),
            HttpResponse.BodyHandlers.ofString());
        assertThat(me.statusCode()).isEqualTo(200);
        assertThat(json.readTree(me.body()).path("username").asText()).isEqualTo("khalid");
    }

    @Test
    void memberSignInLinksTheExistingMemberAccount() throws Exception {
        JsonNode exchanged = runFullFlow(DemoPersonas.AHMED.id().toString());
        assertThat(exchanged.path("user").path("role").asText()).isEqualTo("MEMBER");
        assertThat(exchanged.path("user").path("username").asText()).isEqualTo("ahmed");
    }

    @Test
    void superAdminSignInLinksTheExistingSuperAdminAccount() throws Exception {
        JsonNode exchanged = runFullFlow(DemoPersonas.NOURA.id().toString());
        assertThat(exchanged.path("user").path("role").asText()).isEqualTo("SUPER_ADMIN");
        assertThat(exchanged.path("user").path("username").asText()).isEqualTo("noura");
    }

    @Test
    void signingInTwiceReusesTheSameFederatedUser() throws Exception {
        String firstId = runFullFlow(DemoPersonas.FATIMA.id().toString())
            .path("user").path("id").asText();
        String secondId = runFullFlow(DemoPersonas.FATIMA.id().toString())
            .path("user").path("id").asText();

        // First login links by email + sets external_id; the second finds
        // the same account by external_id. No duplicate, same row.
        assertThat(firstId).isEqualTo(DemoPersonas.FATIMA.id().toString());
        assertThat(secondId).isEqualTo(firstId);
    }

    @Test
    void startRejectsAndCallbackIsUnreachableWhenStateIsBogus() throws Exception {
        // A callback with a state we never issued must be rejected (the
        // pending-state map is the CSRF guard on the flow).
        HttpResponse<String> cb = get(base
            + "/api/v1/auth/sso/callback?code=whatever&state=never-issued");
        assertThat(cb.statusCode()).isEqualTo(400);
        assertThat(json.readTree(cb.body()).path("code").asText())
            .isEqualTo("auth/sso-state-unknown");
    }

    // ---- flow driver --------------------------------------------------

    /** Drives start → authorize → approve → callback → exchange for the
     *  given local account and returns the parsed exchange response. */
    private JsonNode runFullFlow(String userId) throws Exception {
        // 1) /start — 302 to the (mock) authorize URL, carrying our state.
        HttpResponse<String> start = get(base + "/api/v1/auth/sso/start?audience=mobileWeb");
        assertThat(start.statusCode()).isEqualTo(302);
        String authorizeUrl = location(start);
        assertThat(authorizeUrl).contains("/api/v1/auth/sso/mock/authorize");
        String state = queryParam(authorizeUrl, "state");
        assertThat(state).isNotBlank();

        // 2) the mock "login page" lists the local accounts to sign in as.
        HttpResponse<String> page = get(authorizeUrl);
        assertThat(page.statusCode()).isEqualTo(200);
        assertThat(page.body()).contains("Mock Dubai-Gov sign-in");

        // 3) approve as the chosen account — 302 back to our real /callback.
        String callback = base + "/api/v1/auth/sso/callback";
        HttpResponse<String> approve = get(base + "/api/v1/auth/sso/mock/approve"
            + "?userId=" + enc(userId)
            + "&redirect_uri=" + enc(callback)
            + "&state=" + enc(state));
        assertThat(approve.statusCode()).isEqualTo(302);
        String idpCode = queryParam(location(approve), "code");
        assertThat(idpCode).isNotBlank();

        // 4) /callback — the server makes the REAL token + userinfo calls
        //    to the mock, upserts the user, mints JWTs, and 302s to the SPA
        //    with a one-time exchange code.
        HttpResponse<String> cb = get(base + "/api/v1/auth/sso/callback"
            + "?code=" + enc(idpCode) + "&state=" + enc(state));
        assertThat(cb.statusCode()).isEqualTo(302);
        String spaUrl = location(cb);
        assertThat(spaUrl).startsWith("http://localhost:5173/app/auth/callback");
        String exchangeCode = queryParam(spaUrl, "code");
        assertThat(exchangeCode).isNotBlank();

        // 5) /exchange — swap the one-time code for the JWT pair + user.
        HttpResponse<String> ex = http.send(
            HttpRequest.newBuilder(URI.create(base + "/api/v1/auth/sso/exchange"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{\"code\":\"" + exchangeCode + "\"}"))
                .build(),
            HttpResponse.BodyHandlers.ofString());
        assertThat(ex.statusCode()).isEqualTo(200);
        return json.readTree(ex.body());
    }

    // ---- http + parsing helpers --------------------------------------

    private HttpResponse<String> get(String url) throws Exception {
        return http.send(
            HttpRequest.newBuilder(URI.create(url)).GET().build(),
            HttpResponse.BodyHandlers.ofString());
    }

    private static String location(HttpResponse<String> resp) {
        return resp.headers().firstValue("location").orElseThrow(
            () -> new AssertionError("expected a Location header on a redirect"));
    }

    private static String enc(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8);
    }

    private static String queryParam(String url, String key) {
        int q = url.indexOf('?');
        String query = q >= 0 ? url.substring(q + 1) : "";
        for (String pair : query.split("&")) {
            int eq = pair.indexOf('=');
            String k = eq >= 0 ? pair.substring(0, eq) : pair;
            if (k.equals(key)) {
                String v = eq >= 0 ? pair.substring(eq + 1) : "";
                return URLDecode(v);
            }
        }
        return null;
    }

    private static String URLDecode(String v) {
        return java.net.URLDecoder.decode(v, StandardCharsets.UTF_8);
    }
}
