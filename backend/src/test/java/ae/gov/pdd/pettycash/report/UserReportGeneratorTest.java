package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseCategory;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripStatus;
import ae.gov.pdd.pettycash.user.Role;
import ae.gov.pdd.pettycash.user.User;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Pure unit test for {@link UserReportGenerator}. No Spring, no DB — exercises
 * the rendering pipeline directly and parses the produced XLSX back with POI
 * to assert header content and row count.
 */
class UserReportGeneratorTest {

    @Test
    void xlsxContainsBilingualHeadersAndSeedRows() throws Exception {
        UUID tripId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        UUID sourceId = UUID.randomUUID();

        Trip trip = trip(tripId);
        User user = user(userId);
        Source src = source(sourceId);
        ExpenseCategory food = category("FOOD", "Food", "الطعام");

        List<Expense> seed = new ArrayList<>();
        for (int i = 0; i < 3; i++) {
            seed.add(expense(tripId, userId, sourceId, food, 1000L * (i + 1)));
        }

        ReportContext ctx = new ReportContext(
            trip, seed,
            Map.of(userId, user),
            Map.of(sourceId, src),
            Map.of("FOOD", food),
            List.of());

        byte[] bytes = new UserReportGenerator().generate(
            new ReportRequest(tripId, ReportType.USER, ReportFormat.XLSX, userId), ctx);

        try (Workbook wb = new XSSFWorkbook(new ByteArrayInputStream(bytes))) {
            Sheet sheet = wb.getSheetAt(0);
            // The title row, two meta rows, blank, header row, three data rows, blank, total = 10 rows.
            // We don't pin the exact layout — just assert headers contain Arabic + English and
            // there are exactly 3 data rows for the seed expenses.
            Row headerRow = null;
            int firstDataRow = -1;
            for (int r = 0; r <= sheet.getLastRowNum(); r++) {
                Row row = sheet.getRow(r);
                if (row == null) continue;
                org.apache.poi.ss.usermodel.Cell c0 = row.getCell(0);
                if (c0 != null && c0.getStringCellValue().startsWith("Source")) {
                    headerRow = row;
                    firstDataRow = r + 1;
                    break;
                }
            }
            assertThat(headerRow).as("Header row present").isNotNull();
            assertThat(headerRow.getCell(0).getStringCellValue()).contains("Source").contains("المصدر");
            assertThat(headerRow.getCell(1).getStringCellValue()).contains("Category").contains("الفئة");
            assertThat(headerRow.getCell(6).getStringCellValue()).contains("Amount").contains("المبلغ");

            // Walk data rows until we hit a blank or the total row.
            int dataCount = 0;
            for (int r = firstDataRow; r <= sheet.getLastRowNum(); r++) {
                Row row = sheet.getRow(r);
                if (row == null) break;
                org.apache.poi.ss.usermodel.Cell c0 = row.getCell(0);
                if (c0 == null || c0.getStringCellValue().isBlank()) break;
                // The totals row has label in col 5, not col 0.
                if (c0.getStringCellValue().startsWith("Total")) break;
                dataCount++;
            }
            assertThat(dataCount).isEqualTo(3);
        }
    }

    @Test
    void pdfStartsWithMagicBytes() {
        UUID tripId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        UUID sourceId = UUID.randomUUID();

        Trip trip = trip(tripId);
        ReportContext ctx = new ReportContext(
            trip,
            List.of(expense(tripId, userId, sourceId, category("FOOD", "Food", "الطعام"), 100L)),
            Map.of(userId, user(userId)),
            Map.of(sourceId, source(sourceId)),
            Map.of("FOOD", category("FOOD", "Food", "الطعام")),
            List.of());

        byte[] pdf = new UserReportGenerator().generate(
            new ReportRequest(tripId, ReportType.USER, ReportFormat.PDF, userId), ctx);
        assertThat(new String(pdf, 0, 5)).isEqualTo("%PDF-");
    }

    // ---- fixtures ----

    private Trip trip(UUID id) {
        Trip t = new Trip();
        t.setId(id);
        t.setName("Test Trip");
        t.setCountryCode("SA");
        t.setCountryName("Saudi Arabia");
        t.setCurrency("SAR");
        t.setStatus(TripStatus.ACTIVE);
        t.setCreatedBy(UUID.randomUUID());
        t.setLeaderId(UUID.randomUUID());
        t.setTotalBudget(Money.of(5_000_000L, "SAR"));
        t.setCreatedAt(OffsetDateTime.now());
        t.setMemberIds(new java.util.LinkedHashSet<>());
        return t;
    }

    private User user(UUID id) {
        return new User(id, "u" + id.toString().substring(0, 6), "Test User", "مستخدم اختبار",
            "u@pdd.gov.ae", Role.MEMBER, true, OffsetDateTime.now());
    }

    private Source source(UUID id) {
        return new Source(id, "Zabeel Office", "مكتب زعبيل", true);
    }

    private ExpenseCategory category(String code, String en, String ar) {
        return new ExpenseCategory(UUID.randomUUID(), code, en, ar, "icon", true);
    }

    private Expense expense(UUID tripId, UUID userId, UUID sourceId, ExpenseCategory cat, long minor) {
        Expense e = new Expense();
        e.setId(UUID.randomUUID());
        e.setTripId(tripId);
        e.setUserId(userId);
        e.setSourceId(sourceId);
        e.setCategoryId(cat.getId());
        e.setCategoryCode(cat.getCode());
        e.setAmount(Money.of(minor, "SAR"));
        e.setQuantity(1);
        e.setUnitCostAmount(minor);
        e.setDetails("seed");
        e.setVendor("Vendor");
        e.setOccurredAt(OffsetDateTime.parse("2026-05-01T10:00:00+04:00"));
        e.setCreatedAt(OffsetDateTime.now());
        e.setUpdatedAt(OffsetDateTime.now());
        return e;
    }
}
