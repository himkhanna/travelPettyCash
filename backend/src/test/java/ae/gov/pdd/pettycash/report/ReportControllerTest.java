package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.common.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.net.URL;
import java.time.OffsetDateTime;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = ReportController.class)
@AutoConfigureMockMvc(addFilters = false)
class ReportControllerTest {

    @Autowired MockMvc mvc;
    @MockBean ReportService service;
    @MockBean ae.gov.pdd.pettycash.idempotency.IdempotencyService idempotencyService;

    private final UUID tripId = UUID.fromString("cccccccc-0000-0000-0000-000000000001");

    @Test
    void permittedRequestReturnsPresignedUrl() throws Exception {
        UUID reportId = UUID.randomUUID();
        ReportService.GenerateResult result = new ReportService.GenerateResult(
            reportId,
            new URL("https://minio.local/x/y.xlsx?signed=1"),
            OffsetDateTime.parse("2026-05-18T12:05:00+04:00"),
            "abc123");
        when(service.generate(any())).thenReturn(result);

        mvc.perform(get("/api/v1/reports/trip/" + tripId)
                .param("type", "USER")
                .param("format", "XLSX"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.reportId").value(reportId.toString()))
            .andExpect(jsonPath("$.url").value("https://minio.local/x/y.xlsx?signed=1"))
            .andExpect(jsonPath("$.sha256").value("abc123"));
    }

    @Test
    void forbiddenWhenServiceRejects() throws Exception {
        when(service.generate(any())).thenThrow(ApiException.forbidden("FORBIDDEN", "no"));

        mvc.perform(get("/api/v1/reports/trip/" + tripId)
                .param("type", "FINANCE")
                .param("format", "PDF"))
            .andExpect(status().isForbidden())
            .andExpect(jsonPath("$.code").value("FORBIDDEN"));
    }

    @Test
    void invalidTypeYields400() throws Exception {
        mvc.perform(get("/api/v1/reports/trip/" + tripId)
                .param("type", "BANANAS")
                .param("format", "PDF"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("REPORT_TYPE_UNKNOWN"));
    }

    @Test
    void signEndpointStill501() throws Exception {
        mvc.perform(post("/api/v1/reports/" + UUID.randomUUID() + "/sign"))
            .andExpect(status().isNotImplemented())
            .andExpect(jsonPath("$.code").value("SIGNING_DEFERRED"));
    }
}
