package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.auth.sso.DubaiGovProperties;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Slice test for {@link AuthConfigController} — the public probe the
 * mobile + portal bundles call at boot to decide whether to render the
 * "Sign in with Dubai Gov" button. {@code localLogin.enabled} is hardcoded
 * true until Slice E; {@code sso.dubaigov.enabled} reflects the property.
 */
class AuthConfigControllerTest {

    private MockMvc mvcFor(boolean ssoEnabled) {
        DubaiGovProperties props = new DubaiGovProperties();
        props.setEnabled(ssoEnabled);
        return MockMvcBuilders.standaloneSetup(new AuthConfigController(props)).build();
    }

    @Test
    void reportsSsoEnabledWhenTheFlagIsOn() throws Exception {
        mvcFor(true).perform(get("/api/v1/auth/config"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.sso.dubaigov.enabled").value(true))
            .andExpect(jsonPath("$.localLogin.enabled").value(true));
    }

    @Test
    void reportsSsoDisabledWhenTheFlagIsOff() throws Exception {
        mvcFor(false).perform(get("/api/v1/auth/config"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.sso.dubaigov.enabled").value(false))
            .andExpect(jsonPath("$.localLogin.enabled").value(true));
    }
}
