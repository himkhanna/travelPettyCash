package ae.gov.pdd.pettycash.auth.sso;

import ae.gov.pdd.pettycash.auth.AuthService;
import ae.gov.pdd.pettycash.auth.JwtService;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.user.UserRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;

import static ae.gov.pdd.pettycash.auth.sso.DubaiGovSsoService.Audience;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;
import static org.mockito.Mockito.mock;

/**
 * Pure unit tests for {@link DubaiGovSsoService} — no Spring context, no
 * HTTP, no DB. Covers the bits that don't depend on the IdP: authorize-URL
 * construction (incl. the scope-encoding regression), the enabled/disabled
 * gate, and the state / exchange-code error paths. The token + userinfo
 * HTTP legs are exercised for real in {@link DubaiGovSsoIT} against the
 * in-process mock IdP.
 */
class DubaiGovSsoServiceTest {

    private DubaiGovProperties props;
    private DubaiGovSsoService svc;

    @BeforeEach
    void setUp() {
        props = new DubaiGovProperties();
        props.setEnabled(true);
        props.setClientId("test-client-123");
        // authorizationUri, redirectUri and scopes keep their class defaults.

        Clock fixed = Clock.fixed(Instant.parse("2026-06-01T09:00:00Z"), ZoneOffset.UTC);
        svc = new DubaiGovSsoService(
            props,
            mock(UserRepository.class),
            mock(AuthService.class),
            mock(JwtService.class),
            new ObjectMapper(),
            fixed
        );
    }

    @Test
    void startUrlBuildsAuthorizeUrlWithAllPkceParams() {
        String url = svc.startUrl(Audience.MOBILE_WEB);

        assertThat(url).startsWith(props.getAuthorizationUri() + "?");
        assertThat(url).contains("response_type=code");
        assertThat(url).contains("client_id=test-client-123");
        assertThat(url).contains("code_challenge_method=S256");
        assertThat(url).contains("code_challenge=");
        assertThat(url).contains("state=");
    }

    /**
     * Regression guard for the {@code build(true)} bug: the {@code scope}
     * value carries literal spaces ("openid profile email"). They must be
     * percent-encoded (%20) — a raw space makes the URL invalid and the
     * /start endpoint 500s.
     */
    @Test
    void startUrlPercentEncodesTheScopeSpaces() {
        String url = svc.startUrl(Audience.MOBILE_WEB);

        assertThat(url).contains("scope=openid%20profile%20email");
        assertThat(url).doesNotContain(" ");
    }

    @Test
    void startUrlMintsAFreshStateEachCall() {
        String first = stateOf(svc.startUrl(Audience.MOBILE_WEB));
        String second = stateOf(svc.startUrl(Audience.MOBILE_WEB));

        assertThat(first).isNotBlank();
        assertThat(second).isNotBlank();
        assertThat(first).isNotEqualTo(second);
    }

    @Test
    void startUrl404sWhenDisabled() {
        props.setEnabled(false);

        ApiException ex = catchThrowableOfType(
            ApiException.class, () -> svc.startUrl(Audience.MOBILE_WEB));

        assertThat(ex).isNotNull();
        assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(ex.getCode()).isEqualTo("auth/sso-disabled");
    }

    @Test
    void completeCallbackRejectsUnknownState() {
        ApiException ex = catchThrowableOfType(
            ApiException.class, () -> svc.completeCallback("any-code", "never-issued-state"));

        assertThat(ex).isNotNull();
        assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(ex.getCode()).isEqualTo("auth/sso-state-unknown");
    }

    @Test
    void exchangeRejectsUnknownOneTimeCode() {
        ApiException ex = catchThrowableOfType(
            ApiException.class, () -> svc.exchange("never-minted"));

        assertThat(ex).isNotNull();
        assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(ex.getCode()).isEqualTo("auth/sso-exchange-unknown");
    }

    @Test
    void exposesEnabledFlagAndSloUri() {
        assertThat(svc.enabled()).isTrue();
        assertThat(svc.samlSloUri()).isEqualTo(props.getSamlSloUri());

        props.setEnabled(false);
        assertThat(svc.enabled()).isFalse();
    }

    private static String stateOf(String url) {
        int i = url.indexOf("state=");
        if (i < 0) return null;
        String tail = url.substring(i + "state=".length());
        int amp = tail.indexOf('&');
        return amp < 0 ? tail : tail.substring(0, amp);
    }
}
