package ae.gov.pdd.pettycash.expense;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIf;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.containers.MinIOContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end receipt flow against a real Postgres + MinIO via Testcontainers.
 * Verifies upload → object lands in MinIO → row points at it → presigned URL
 * fetches the exact bytes back. Plus the permission boundaries.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Testcontainers
@EnabledIf("ae.gov.pdd.pettycash.expense.ReceiptsIT#dockerReachable")
class ReceiptsIT {

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

    @Container
    static MinIOContainer minio = new MinIOContainer("minio/minio:RELEASE.2025-01-20T14-49-07Z")
        .withUserName("pdd")
        .withPassword("pdd-minio-secret");

    @DynamicPropertySource
    static void wireProps(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", postgres::getJdbcUrl);
        r.add("spring.datasource.username", postgres::getUsername);
        r.add("spring.datasource.password", postgres::getPassword);
        r.add("pdd.storage.endpoint", minio::getS3URL);
        r.add("pdd.storage.access-key", minio::getUserName);
        r.add("pdd.storage.secret-key", minio::getPassword);
    }

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;

    private static final byte[] FAKE_JPEG = new byte[] {
        (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0x00, 0x10,
        'J', 'F', 'I', 'F', 0x00, 0x01, 0x01, 0x00,
        0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        (byte) 0xFF, (byte) 0xD9
    };

    @Test
    void ownerUpload_pointsTheRowAtObject_andSignedUrlReturnsSameBytes() throws Exception {
        String tok = token("ahmed");
        String expId = pickAhmedKsaExpense(tok);

        MockMultipartFile file = new MockMultipartFile(
            "file", "receipt.jpg", "image/jpeg", FAKE_JPEG
        );

        String uploaded = mvc.perform(multipart("/api/v1/expenses/" + expId + "/receipt")
                .file(file)
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.receiptObjectKey").exists())
            .andReturn().getResponse().getContentAsString();
        String objectKey = json.readTree(uploaded).path("receiptObjectKey").asText();
        assert objectKey.startsWith("receipts/" + expId + "/");

        // Presigned GET should fetch the same bytes back.
        String urlBody = mvc.perform(get("/api/v1/expenses/" + expId + "/receipt")
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.url").exists())
            .andReturn().getResponse().getContentAsString();
        String url = json.readTree(urlBody).path("url").asText();

        HttpResponse<byte[]> dl = HttpClient.newHttpClient().send(
            HttpRequest.newBuilder(URI.create(url)).GET().build(),
            HttpResponse.BodyHandlers.ofByteArray()
        );
        assert dl.statusCode() == 200 : "presigned GET status " + dl.statusCode();
        assert java.util.Arrays.equals(dl.body(), FAKE_JPEG)
            : "downloaded bytes differ from uploaded";
    }

    @Test
    void nonOwnerCannotUpload() throws Exception {
        String ahmed = token("ahmed");
        String mohammed = token("mohammed");
        String expId = pickAhmedKsaExpense(ahmed);
        MockMultipartFile file = new MockMultipartFile(
            "file", "x.jpg", "image/jpeg", FAKE_JPEG
        );
        mvc.perform(multipart("/api/v1/expenses/" + expId + "/receipt")
                .file(file)
                .header("Authorization", "Bearer " + mohammed))
            // Members can't see other members' expense rows at all → 404
            // (don't leak existence).
            .andExpect(status().isNotFound());
    }

    @Test
    void emptyFileIs400() throws Exception {
        String tok = token("ahmed");
        String expId = pickAhmedKsaExpense(tok);
        mvc.perform(multipart("/api/v1/expenses/" + expId + "/receipt")
                .file(new MockMultipartFile("file", "empty.jpg", "image/jpeg", new byte[0]))
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("validation/empty-receipt"));
    }

    @Test
    void unsupportedMimeTypeIs415() throws Exception {
        String tok = token("ahmed");
        String expId = pickAhmedKsaExpense(tok);
        mvc.perform(multipart("/api/v1/expenses/" + expId + "/receipt")
                .file(new MockMultipartFile("file", "x.txt", "text/plain", "hello".getBytes()))
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isUnsupportedMediaType())
            .andExpect(jsonPath("$.code").value("validation/unsupported-receipt-type"));
    }

    @Test
    void getReceiptUrlOnExpenseWithoutReceiptIs404() throws Exception {
        String tok = token("ahmed");
        String expId = pickAhmedKsaExpenseWithoutReceipt(tok);
        mvc.perform(get("/api/v1/expenses/" + expId + "/receipt")
                .header("Authorization", "Bearer " + tok))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.code").value("expenses/no-receipt"));
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

    private String pickAhmedKsaExpense(String token) throws Exception {
        String resp = mvc.perform(get("/api/v1/trips")
                .header("Authorization", "Bearer " + token))
            .andReturn().getResponse().getContentAsString();
        String tripId = null;
        for (JsonNode t : json.readTree(resp)) {
            if (t.path("countryCode").asText().equals("SA")) {
                tripId = t.path("id").asText();
                break;
            }
        }
        String list = mvc.perform(get("/api/v1/trips/" + tripId + "/expenses")
                .header("Authorization", "Bearer " + token))
            .andReturn().getResponse().getContentAsString();
        return json.readTree(list).get(0).path("id").asText();
    }

    private String pickAhmedKsaExpenseWithoutReceipt(String token) throws Exception {
        String resp = mvc.perform(get("/api/v1/trips")
                .header("Authorization", "Bearer " + token))
            .andReturn().getResponse().getContentAsString();
        String tripId = null;
        for (JsonNode t : json.readTree(resp)) {
            if (t.path("countryCode").asText().equals("SA")) {
                tripId = t.path("id").asText();
                break;
            }
        }
        String list = mvc.perform(get("/api/v1/trips/" + tripId + "/expenses")
                .header("Authorization", "Bearer " + token))
            .andReturn().getResponse().getContentAsString();
        for (JsonNode e : json.readTree(list)) {
            if (e.path("receiptObjectKey").isNull()) {
                return e.path("id").asText();
            }
        }
        throw new IllegalStateException("No receipt-less expense seeded for Ahmed on KSA");
    }
}
