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

import static ae.gov.pdd.pettycash.auth.sso.UaePassSsoService.Audience;
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

/** HTTP-surface slice test for {@link UaePassController}. */
class UaePassControllerTest {

    private UaePassSsoService sso;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        sso = mock(UaePassSsoService.class);
        mvc = MockMvcBuilders.standaloneSetup(new UaePassController(sso))
            .setControllerAdvice(new ProblemDetailHandler())
            .build();
    }

    @Test
    void startDefaultsToMobileWebAndRedirects() throws Exception {
        when(sso.startUrl(Audience.MOBILE_WEB)).thenReturn("https://stg-id.uaepass.ae/idshub/authorize?x=1");

        mvc.perform(get("/api/v1/auth/sso/uaepass/start"))
            .andExpect(status().isFound())
            .andExpect(redirectedUrl("https://stg-id.uaepass.ae/idshub/authorize?x=1"));

        verify(sso).startUrl(Audience.MOBILE_WEB);
    }

    @Test
    void startMapsPortalAudience() throws Exception {
        when(sso.startUrl(any())).thenReturn("https://stg-id.uaepass.ae/idshub/authorize");

        mvc.perform(get("/api/v1/auth/sso/uaepass/start").param("audience", "portal"))
            .andExpect(status().isFound());

        verify(sso).startUrl(Audience.PORTAL);
    }

    @Test
    void callbackRedirectsToTheSpaCallback() throws Exception {
        when(sso.completeCallback("c", "s"))
            .thenReturn("http://localhost:5173/app/auth/uaepass/callback?code=one-time");

        mvc.perform(get("/api/v1/auth/sso/uaepass/callback").param("code", "c").param("state", "s"))
            .andExpect(status().isFound())
            .andExpect(redirectedUrl("http://localhost:5173/app/auth/uaepass/callback?code=one-time"));
    }

    @Test
    void exchangeReturnsTokensAndUser() throws Exception {
        MeResponse me = new MeResponse(
            UUID.fromString("00000000-0000-0000-0000-0000000ad10d"),
            "khalid", "Khalid Al Suwaidi", "خالد السويدي",
            "khalid@protocol.gov.ae", UserRole.ADMIN);
        when(sso.exchange("one-time"))
            .thenReturn(new LoginResponse(me, new AuthTokens("a", "r", 900, 2592000)));

        mvc.perform(post("/api/v1/auth/sso/uaepass/exchange")
                .contentType(APPLICATION_JSON).content("{\"code\":\"one-time\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.tokens.accessToken").value("a"))
            .andExpect(jsonPath("$.user.username").value("khalid"))
            .andExpect(jsonPath("$.user.role").value("ADMIN"));
    }

    @Test
    void logoutUrlReturnsTheUaePassLogoutUri() throws Exception {
        when(sso.logoutUri()).thenReturn("https://stg-id.uaepass.ae/idshub/logout");

        mvc.perform(get("/api/v1/auth/sso/uaepass/logout-url"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.url").value("https://stg-id.uaepass.ae/idshub/logout"));
    }

    @Test
    void unknownIdentityMapsToProblemDetail403() throws Exception {
        when(sso.completeCallback(any(), any())).thenThrow(new ApiException(
            HttpStatus.FORBIDDEN, "auth/sso-no-account",
            "No PDD account", "Your UAE Pass identity is not linked to a PDD account."));

        mvc.perform(get("/api/v1/auth/sso/uaepass/callback").param("code", "c").param("state", "s"))
            .andExpect(status().isForbidden())
            .andExpect(jsonPath("$.code").value("auth/sso-no-account"));
    }
}
