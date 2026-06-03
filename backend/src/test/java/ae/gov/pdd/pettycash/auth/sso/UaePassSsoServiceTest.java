package ae.gov.pdd.pettycash.auth.sso;

import ae.gov.pdd.pettycash.auth.AuthService;
import ae.gov.pdd.pettycash.auth.dto.AuthTokens;
import ae.gov.pdd.pettycash.auth.dto.LoginResponse;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.UUID;

import static ae.gov.pdd.pettycash.auth.sso.UaePassSsoService.Audience;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * Unit tests for {@link UaePassSsoService}. The simple paths (authorize
 * URL, enabled gate, state/exchange errors) need no HTTP. The link /
 * reject paths drive the real token + userinfo calls against a
 * {@link MockRestServiceServer} bound to the injected RestClient.
 */
class UaePassSsoServiceTest {

    private UaePassProperties props;
    private UserRepository users;
    private AuthService auth;

    @BeforeEach
    void setUp() {
        props = new UaePassProperties();
        props.setEnabled(true);
        users = mock(UserRepository.class);
        auth = mock(AuthService.class);
    }

    private UaePassSsoService serviceWith(RestClient http) {
        Clock fixed = Clock.fixed(Instant.parse("2026-06-02T09:00:00Z"), ZoneOffset.UTC);
        return new UaePassSsoService(props, users, auth, fixed, http);
    }

    // ---- authorize URL ------------------------------------------------

    @Test
    void startUrlBuildsAuthorizeUrlWithEncodedScopeAndAcr() {
        String url = serviceWith(RestClient.builder().build()).startUrl(Audience.MOBILE_WEB);

        assertThat(url).startsWith(props.getAuthorizationUri() + "?");
        assertThat(url).contains("response_type=code");
        assertThat(url).contains("client_id=sandbox_stage");
        // Colons are valid query chars and stay literal; the UAE Pass scope
        // (a single URN) has no spaces to encode.
        assertThat(url).contains("scope=urn:uae:digitalid:profile:general");
        assertThat(url).contains("acr_values=urn:safelayer:tws:policies:authentication:level:low");
        assertThat(url).contains("state=");
        assertThat(url).doesNotContain(" ");
    }

    @Test
    void startUrl404sWhenDisabled() {
        props.setEnabled(false);
        ApiException ex = catchThrowableOfType(
            ApiException.class,
            () -> serviceWith(RestClient.builder().build()).startUrl(Audience.MOBILE_WEB));
        assertThat(ex).isNotNull();
        assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void completeCallbackRejectsUnknownState() {
        ApiException ex = catchThrowableOfType(
            ApiException.class,
            () -> serviceWith(RestClient.builder().build())
                .completeCallback("code", "never-issued"));
        assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(ex.getCode()).isEqualTo("auth/sso-state-unknown");
    }

    @Test
    void exchangeRejectsUnknownCode() {
        ApiException ex = catchThrowableOfType(
            ApiException.class,
            () -> serviceWith(RestClient.builder().build()).exchange("nope"));
        assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(ex.getCode()).isEqualTo("auth/sso-exchange-unknown");
    }

    // ---- link / reject (full token + userinfo round-trip) ------------

    @Test
    void linksUaePassIdentityToExistingAccountByEmail() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(props.getTokenUri())).andExpect(method(HttpMethod.POST))
            .andRespond(withSuccess("{\"access_token\":\"tok-123\"}", MediaType.APPLICATION_JSON));
        server.expect(requestTo(props.getUserInfoUri())).andExpect(method(HttpMethod.GET))
            .andRespond(withSuccess(
                "{\"sub\":\"UAEPASS/abc-123\",\"uuid\":\"abc-123\","
                    + "\"email\":\"khalid@protocol.gov.ae\",\"fullnameEN\":\"Khalid Al Suwaidi\"}",
                MediaType.APPLICATION_JSON));

        User khalid = new User(
            UUID.fromString("00000000-0000-0000-0000-0000000ad10d"),
            "khalid", "Khalid Al Suwaidi", "خالد السويدي",
            "khalid@protocol.gov.ae", "hash", UserRole.ADMIN);
        when(users.findByExternalId("uaepass|abc-123")).thenReturn(Optional.empty());
        when(users.findByEmailIgnoreCase("khalid@protocol.gov.ae")).thenReturn(Optional.of(khalid));
        when(auth.mintForUser(any())).thenAnswer(inv -> new AuthService.LoginResult(
            inv.getArgument(0), new AuthTokens("access", "refresh", 900, 2592000)));

        UaePassSsoService svc = serviceWith(builder.build());
        String state = stateOf(svc.startUrl(Audience.MOBILE_WEB));
        String dest = svc.completeCallback("auth-code", state);
        String oneTime = codeOf(dest);
        LoginResponse resp = svc.exchange(oneTime);

        server.verify();
        // Linked onto the existing khalid account; role preserved; federated.
        assertThat(resp.user().username()).isEqualTo("khalid");
        assertThat(resp.user().role()).isEqualTo(UserRole.ADMIN);
        assertThat(khalid.getExternalId()).isEqualTo("uaepass|abc-123");
        assertThat(dest).startsWith(props.getWebMobileCallback());
    }

    @Test
    void linksByEmiratesIdPreferredOverEmail() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(props.getTokenUri()))
            .andRespond(withSuccess("{\"access_token\":\"tok\"}", MediaType.APPLICATION_JSON));
        server.expect(requestTo(props.getUserInfoUri()))
            .andRespond(withSuccess(
                "{\"sub\":\"UAEPASS/xyz-9\",\"uuid\":\"xyz-9\",\"idn\":\"784-1990-1234567-1\","
                    + "\"email\":\"changed@example.com\",\"fullnameEN\":\"Fatima Al Hashimi\"}",
                MediaType.APPLICATION_JSON));

        User fatima = new User(
            UUID.fromString("00000000-0000-0000-0000-0000000fa71a"),
            "fatima", "Fatima Al Hashimi", "فاطمة الهاشمي",
            "fatima@protocol.gov.ae", "hash", UserRole.LEADER);
        when(users.findByExternalId(any())).thenReturn(Optional.empty());
        when(users.findByEmiratesId("784-1990-1234567-1")).thenReturn(Optional.of(fatima));
        when(auth.mintForUser(any())).thenAnswer(inv -> new AuthService.LoginResult(
            inv.getArgument(0), new AuthTokens("a", "r", 900, 2592000)));

        UaePassSsoService svc = serviceWith(builder.build());
        String state = stateOf(svc.startUrl(Audience.PORTAL));
        LoginResponse resp = svc.exchange(codeOf(svc.completeCallback("ac", state)));

        server.verify();
        assertThat(resp.user().username()).isEqualTo("fatima");
        assertThat(fatima.getExternalId()).isEqualTo("uaepass|xyz-9");
        assertThat(fatima.getEmiratesId()).isEqualTo("784-1990-1234567-1");
    }

    @Test
    void rejectsUnknownIdentityWith403() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(props.getTokenUri()))
            .andRespond(withSuccess("{\"access_token\":\"tok\"}", MediaType.APPLICATION_JSON));
        server.expect(requestTo(props.getUserInfoUri()))
            .andRespond(withSuccess(
                "{\"sub\":\"UAEPASS/nobody\",\"uuid\":\"nobody\","
                    + "\"email\":\"stranger@uaepass.ae\",\"fullnameEN\":\"A Stranger\"}",
                MediaType.APPLICATION_JSON));

        when(users.findByExternalId(any())).thenReturn(Optional.empty());
        when(users.findByEmailIgnoreCase(any())).thenReturn(Optional.empty());

        UaePassSsoService svc = serviceWith(builder.build());
        String state = stateOf(svc.startUrl(Audience.MOBILE_WEB));

        ApiException ex = catchThrowableOfType(
            ApiException.class, () -> svc.completeCallback("auth-code", state));
        assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(ex.getCode()).isEqualTo("auth/sso-no-account");
    }

    private static String stateOf(String url) {
        return param(url, "state");
    }

    private static String codeOf(String url) {
        return param(url, "code");
    }

    private static String param(String url, String key) {
        int q = url.indexOf('?');
        for (String pair : url.substring(q + 1).split("&")) {
            int eq = pair.indexOf('=');
            if (pair.substring(0, eq).equals(key)) {
                return java.net.URLDecoder.decode(
                    pair.substring(eq + 1), java.nio.charset.StandardCharsets.UTF_8);
            }
        }
        return null;
    }
}
