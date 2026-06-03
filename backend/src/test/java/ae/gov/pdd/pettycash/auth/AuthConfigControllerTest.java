package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.auth.sso.DubaiGovProperties;
import ae.gov.pdd.pettycash.auth.sso.UaePassProperties;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Slice test for {@link AuthConfigController} — the public probe the
 * mobile + portal bundles call at boot to decide which sign-in options to
 * render. {@code localLogin.enabled} is hardcoded true until Slice E;
 * {@code sso.dubaigov.enabled} / {@code sso.uaepass.enabled} reflect their
 * feature flags.
 */
class AuthConfigControllerTest {

    private MockMvc mvcFor(boolean dubaigov, boolean uaepass) {
        DubaiGovProperties dg = new DubaiGovProperties();
        dg.setEnabled(dubaigov);
        UaePassProperties up = new UaePassProperties();
        up.setEnabled(uaepass);
        return MockMvcBuilders.standaloneSetup(new AuthConfigController(dg, up)).build();
    }

    @Test
    void reportsBothProvidersEnabled() throws Exception {
        mvcFor(true, true).perform(get("/api/v1/auth/config"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.sso.dubaigov.enabled").value(true))
            .andExpect(jsonPath("$.sso.uaepass.enabled").value(true))
            .andExpect(jsonPath("$.localLogin.enabled").value(true));
    }

    @Test
    void reportsProvidersIndependently() throws Exception {
        mvcFor(false, true).perform(get("/api/v1/auth/config"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.sso.dubaigov.enabled").value(false))
            .andExpect(jsonPath("$.sso.uaepass.enabled").value(true));
    }
}
