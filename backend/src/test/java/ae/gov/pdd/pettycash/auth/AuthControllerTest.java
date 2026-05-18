package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.PostgresTestContainerConfig;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Map;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@ActiveProfiles("test")
@Import(PostgresTestContainerConfig.class)
@Testcontainers
class AuthControllerTest {

    @Autowired WebApplicationContext ctx;
    @Autowired ObjectMapper json;

    private MockMvc mvc() {
        return MockMvcBuilders.webAppContextSetup(ctx).build();
    }

    @Test
    void loginWithUaePassReturnsJwt() throws Exception {
        String body = json.writeValueAsString(Map.of("provider", "UAE_PASS", "code", "anything"));
        mvc().perform(post("/api/v1/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.accessToken").exists())
            .andExpect(jsonPath("$.refreshToken").exists())
            .andExpect(jsonPath("$.user.username").value("uaepass-test"))
            .andExpect(jsonPath("$.user.role").value("LEADER"));
    }

    @Test
    void loginWithPddSsoReturnsAdminUser() throws Exception {
        String body = json.writeValueAsString(Map.of("provider", "PDD_SSO", "code", "x"));
        mvc().perform(post("/api/v1/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.user.username").value("pddsso-test"))
            .andExpect(jsonPath("$.user.role").value("ADMIN"));
    }
}
