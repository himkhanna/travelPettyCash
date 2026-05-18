package ae.gov.pdd.pettycash.user;

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
@EnabledIf("ae.gov.pdd.pettycash.user.UserControllerIT#dockerReachable")
class UserControllerIT {

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
    static void wire(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", postgres::getJdbcUrl);
        r.add("spring.datasource.username", postgres::getUsername);
        r.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;

    @Test
    void adminCreatesUser_thenTheyCanLogIn() throws Exception {
        String admin = token("khalid");
        JsonNode created = postJson("/api/v1/users", admin, """
            {
              "username": "newhire1",
              "displayName": "New Hire 1",
              "displayNameAr": "موظف جديد 1",
              "email": "newhire1@protocol.gov.ae",
              "role": "MEMBER",
              "password": "temp1234pw"
            }
            """);
        assert "newhire1".equals(created.path("username").asText());
        assert "MEMBER".equals(created.path("role").asText());

        // Login as the new user.
        mvc.perform(post("/api/v1/auth/login")
                .contentType(APPLICATION_JSON)
                .content("""
                    {"username":"newhire1","password":"temp1234pw"}
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.user.role").value("MEMBER"));
    }

    @Test
    void duplicateUsernameIs409() throws Exception {
        String admin = token("khalid");
        mvc.perform(post("/api/v1/users")
                .header("Authorization", "Bearer " + admin)
                .contentType(APPLICATION_JSON)
                .content("""
                    {
                      "username": "fatima",
                      "displayName": "x",
                      "displayNameAr": "x",
                      "email": "x@y.com",
                      "role": "MEMBER",
                      "password": "abcdef123"
                    }
                    """))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("users/duplicate-username"));
    }

    @Test
    void memberCannotCreateUser() throws Exception {
        String ahmed = token("ahmed");
        mvc.perform(post("/api/v1/users")
                .header("Authorization", "Bearer " + ahmed)
                .contentType(APPLICATION_JSON)
                .content("""
                    {
                      "username": "rogue",
                      "displayName": "Rogue",
                      "displayNameAr": "متجاوز",
                      "email": "r@y.com",
                      "role": "ADMIN",
                      "password": "abcdef123"
                    }
                    """))
            .andExpect(status().isForbidden());
    }

    @Test
    void adminPromotesMemberToLeader() throws Exception {
        String admin = token("khalid");
        String layla = "00000000-0000-0000-0000-00000001a71a";
        mvc.perform(patch("/api/v1/users/" + layla)
                .header("Authorization", "Bearer " + admin)
                .contentType(APPLICATION_JSON)
                .content("{\"role\":\"LEADER\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.role").value("LEADER"));
        // Revert so the rest of the test suite isn't affected.
        mvc.perform(patch("/api/v1/users/" + layla)
                .header("Authorization", "Bearer " + admin)
                .contentType(APPLICATION_JSON)
                .content("{\"role\":\"MEMBER\"}"));
    }

    @Test
    void adminCannotChangeOwnRole() throws Exception {
        String admin = token("khalid");
        String khalid = "00000000-0000-0000-0000-0000000ad10d";
        mvc.perform(patch("/api/v1/users/" + khalid)
                .header("Authorization", "Bearer " + admin)
                .contentType(APPLICATION_JSON)
                .content("{\"role\":\"MEMBER\"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("users/self-role-change"));
    }

    @Test
    void adminCannotDeactivateSelf() throws Exception {
        String admin = token("khalid");
        String khalid = "00000000-0000-0000-0000-0000000ad10d";
        mvc.perform(patch("/api/v1/users/" + khalid)
                .header("Authorization", "Bearer " + admin)
                .contentType(APPLICATION_JSON)
                .content("{\"active\":false}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("users/self-deactivate"));
    }

    @Test
    void deactivatingUserLocksLogin() throws Exception {
        String admin = token("khalid");
        // Create a throwaway user, then deactivate.
        JsonNode created = postJson("/api/v1/users", admin, """
            {
              "username": "throwaway",
              "displayName": "Throwaway",
              "displayNameAr": "مؤقت",
              "email": "throw@y.com",
              "role": "MEMBER",
              "password": "abcdef123"
            }
            """);
        String id = created.path("id").asText();
        mvc.perform(patch("/api/v1/users/" + id)
                .header("Authorization", "Bearer " + admin)
                .contentType(APPLICATION_JSON)
                .content("{\"active\":false}"))
            .andExpect(status().isOk());
        mvc.perform(post("/api/v1/auth/login")
                .contentType(APPLICATION_JSON)
                .content("""
                    {"username":"throwaway","password":"abcdef123"}
                    """))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.code").value("auth/invalid-credentials"));
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

    private JsonNode postJson(String path, String tok, String body) throws Exception {
        String resp = mvc.perform(post(path)
                .header("Authorization", "Bearer " + tok)
                .contentType(APPLICATION_JSON).content(body))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        return json.readTree(resp);
    }
}
