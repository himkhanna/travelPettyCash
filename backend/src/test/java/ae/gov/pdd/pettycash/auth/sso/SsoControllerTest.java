package ae.gov.pdd.pettycash.auth.sso;

import ae.gov.pdd.pettycash.auth.dto.AuthTokens;
import ae.gov.pdd.pettycash.auth.dto.LoginResponse;
import ae.gov.pdd.pettycash.auth.dto.MeResponse;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.common.error.ProblemDetailHandler;
import ae.gov.pdd.pettycash.user.UserRole;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.UUID;

import static ae.gov.pdd.pettycash.auth.sso.DubaiGovSsoService.Audience;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * HTTP-surface slice test for {@link SsoController}. Standalone MockMvc so
 * the JWT filter / full security chain stays out of the slice; the service
 * is mocked. Verifies audience mapping, redirects, JSON bodies, and that an
 * {@link ApiException} (e.g. SSO-disabled) maps to an RFC-7807 problem
 * detail via {@link ProblemDetailHandler}.
 */
class SsoControllerTest {

    private DubaiGovSsoService sso;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        sso = mock(DubaiGovSsoService.class);
        mvc = MockMvcBuilders.standaloneSetup(new SsoController(sso))
            .setControllerAdvice(new ProblemDetailHandler())
            .build();
    }

    @Test
    void startDefaultsToMobileWebAndRedirectsToTheAuthorizeUrl() throws Exception {
        when(sso.startUrl(Audience.MOBILE_WEB)).thenReturn("https://idp.example/authorize?x=1");

        mvc.perform(get("/api/v1/auth/sso/start"))
            .andExpect(status().isFound())
            .andExpect(redirectedUrl("https://idp.example/authorize?x=1"));

        verify(sso).startUrl(Audience.MOBILE_WEB);
    }

    @Test
    void startMapsPortalAudience() throws Exception {
        when(sso.startUrl(any())).thenReturn("https://idp.example/authorize");

        mvc.perform(get("/api/v1/auth/sso/start").param("audience", "portal"))
            .andExpect(status().isFound());

        verify(sso).startUrl(Audience.PORTAL);
    }

    @Test
    void startMapsNativeAudience() throws Exception {
        when(sso.startUrl(any())).thenReturn("https://idp.example/authorize");

        mvc.perform(get("/api/v1/auth/sso/start").param("audience", "mobileNative"))
            .andExpect(status().isFound());

        verify(sso).startUrl(Audience.MOBILE_NATIVE);
    }

    @Test
    void callbackRedirectsToTheSpaCallbackUrl() throws Exception {
        when(sso.completeCallback("the-code", "the-state"))
            .thenReturn("http://localhost:5173/app/auth/callback?code=one-time");

        mvc.perform(get("/api/v1/auth/sso/callback")
                .param("code", "the-code")
                .param("state", "the-state"))
            .andExpect(status().isFound())
            .andExpect(redirectedUrl("http://localhost:5173/app/auth/callback?code=one-time"));
    }

    @Test
    void exchangeReturnsTheTokenPairAndUser() throws Exception {
        MeResponse me = new MeResponse(
            UUID.fromString("e5e0d2cd-77a3-4d9d-afa5-c589ca11023e"),
            "dgov:mock|ADMIN", "Mock Admin", "Mock Admin",
            "admin@mock.dubai.gov.ae", UserRole.ADMIN);
        AuthTokens tokens = new AuthTokens("access-jwt", "refresh-tok", 900, 2592000);
        when(sso.exchange("one-time")).thenReturn(new LoginResponse(me, tokens));

        mvc.perform(post("/api/v1/auth/sso/exchange")
                .contentType(APPLICATION_JSON)
                .content("{\"code\":\"one-time\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.tokens.accessToken").value("access-jwt"))
            .andExpect(jsonPath("$.tokens.refreshToken").value("refresh-tok"))
            .andExpect(jsonPath("$.user.username").value("dgov:mock|ADMIN"))
            .andExpect(jsonPath("$.user.role").value("ADMIN"));
    }

    @Test
    void logoutUrlReturnsTheSamlSloUrl() throws Exception {
        when(sso.samlSloUri()).thenReturn("https://idp.example/saml/slo");

        mvc.perform(get("/api/v1/auth/sso/logout-url"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.url").value("https://idp.example/saml/slo"));
    }

    @Test
    void disabledSsoMapsToProblemDetail404() throws Exception {
        when(sso.startUrl(any())).thenThrow(new ApiException(
            HttpStatus.NOT_FOUND, "auth/sso-disabled",
            "SSO is not enabled", "Dubai-Gov SSO is disabled in this environment."));

        mvc.perform(get("/api/v1/auth/sso/start"))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.code").value("auth/sso-disabled"))
            .andExpect(jsonPath("$.title").value("SSO is not enabled"));
    }
}
