package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.AllocationStatus;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripStatus;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class FinanceLetterGeneratorTest {

    @Test
    void producesValidPdfWithMagicBytes() {
        UUID tripId = UUID.randomUUID();
        UUID sourceId = UUID.randomUUID();
        UUID toUser = UUID.randomUUID();
        Trip t = new Trip();
        t.setId(tripId);
        t.setName("Riyadh Delegation");
        t.setCountryCode("SA");
        t.setCountryName("Saudi Arabia");
        t.setCurrency("SAR");
        t.setStatus(TripStatus.ACTIVE);
        t.setCreatedBy(UUID.randomUUID());
        t.setLeaderId(UUID.randomUUID());
        t.setTotalBudget(Money.of(5_000_000L, "SAR"));
        t.setMemberIds(new LinkedHashSet<>());
        t.setCreatedAt(OffsetDateTime.now());

        Source s = new Source(sourceId, "Zabeel Office", "مكتب زعبيل", true);
        Allocation a = new Allocation();
        a.setId(UUID.randomUUID());
        a.setTripId(tripId);
        a.setFromUserId(null);
        a.setToUserId(toUser);
        a.setSourceId(sourceId);
        a.setAmount(Money.of(500_000L, "SAR"));
        a.setStatus(AllocationStatus.ACCEPTED);
        a.setCreatedAt(OffsetDateTime.now());

        ReportContext ctx = new ReportContext(
            t, List.of(),
            Map.of(),
            Map.of(sourceId, s),
            Map.of(),
            List.of(a));

        byte[] pdf = new FinanceLetterGenerator().generate(
            new ReportRequest(tripId, ReportType.FINANCE, ReportFormat.PDF, null), ctx);

        // PDF magic: %PDF-
        assertThat(pdf.length).isGreaterThan(100);
        assertThat(new String(pdf, 0, 5)).isEqualTo("%PDF-");
    }

    @Test
    void rejectsXlsxFormat() {
        Trip t = new Trip();
        t.setId(UUID.randomUUID());
        t.setName("X");
        t.setCountryCode("SA");
        t.setCurrency("SAR");
        t.setStatus(TripStatus.ACTIVE);
        t.setCreatedBy(UUID.randomUUID());
        t.setLeaderId(UUID.randomUUID());
        t.setTotalBudget(Money.of(0L, "SAR"));
        t.setMemberIds(new LinkedHashSet<>());

        ReportContext ctx = new ReportContext(t, List.of(), Map.of(), Map.of(), Map.of(), List.of());
        assertThatThrownBy(() -> new FinanceLetterGenerator().generate(
            new ReportRequest(t.getId(), ReportType.FINANCE, ReportFormat.XLSX, null), ctx))
            .isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("PDF-only");
    }
}
