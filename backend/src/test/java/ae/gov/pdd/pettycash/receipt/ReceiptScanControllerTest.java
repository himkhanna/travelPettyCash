package ae.gov.pdd.pettycash.receipt;

import ae.gov.pdd.pettycash.PostgresTestContainerConfig;
import ae.gov.pdd.pettycash.storage.StorageService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.mockito.Mockito.mock;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@ActiveProfiles("test")
@Import({PostgresTestContainerConfig.class, ReceiptScanControllerTest.StubStorage.class})
@Testcontainers
class ReceiptScanControllerTest {

    @Autowired WebApplicationContext ctx;

    private MockMvc mvc() {
        return MockMvcBuilders.webAppContextSetup(ctx).apply(springSecurity()).build();
    }

    @Test
    void scanReturnsExpectedShapeWithJwt() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
            "file", "rcpt.jpg", "image/jpeg", "fake-jpeg-bytes".getBytes());
        mvc().perform(multipart("/api/v1/receipts/scan").file(file)
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .with(jwt().jwt(j -> j
                    .subject("11111111-1111-1111-1111-111111111111")
                    .claim("username", "member1")
                    .claim("role", "MEMBER"))))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.vendor").exists())
            .andExpect(jsonPath("$.amount.amount").isNumber())
            .andExpect(jsonPath("$.amount.currency").value("SAR"))
            .andExpect(jsonPath("$.quantity").isNumber())
            .andExpect(jsonPath("$.categoryHint").exists())
            .andExpect(jsonPath("$.confidence").isNumber())
            .andExpect(jsonPath("$.warning").value(
                "OCR result — please verify before submitting."));
    }

    @Test
    void scanRejectsUnauthenticated() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
            "file", "rcpt.jpg", "image/jpeg", "fake-jpeg-bytes".getBytes());
        mvc().perform(multipart("/api/v1/receipts/scan").file(file)
                .contentType(MediaType.MULTIPART_FORM_DATA))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void scanRejectsWrongContentType() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
            "file", "rcpt.pdf", "application/pdf", "%PDF-1.4".getBytes());
        mvc().perform(multipart("/api/v1/receipts/scan").file(file)
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .with(jwt().jwt(j -> j
                    .subject("11111111-1111-1111-1111-111111111111")
                    .claim("username", "member1")
                    .claim("role", "MEMBER"))))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("RECEIPT_UNSUPPORTED_TYPE"));
    }

    /**
     * Replace the real MinIO-backed storage with a no-op so {@code @PostConstruct}
     * on the real bean doesn't try to dial localhost:9000 during the test.
     */
    @TestConfiguration
    static class StubStorage {
        @Bean
        @Primary
        StorageService storageService() {
            StorageService stub = mock(StorageService.class);
            return stub;
        }
    }
}
