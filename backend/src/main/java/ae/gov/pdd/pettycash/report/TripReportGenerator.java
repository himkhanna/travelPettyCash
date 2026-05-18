package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseCategory;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.user.User;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.FillPatternType;
import org.apache.poi.ss.usermodel.IndexedColors;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Component;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.UUID;

/**
 * TRIP report — every expense by every member. XLSX only per CLAUDE.md §10.
 */
@Component
public class TripReportGenerator implements ReportGenerator {

    @Override public ReportType type() { return ReportType.TRIP; }
    @Override public ReportFormat format() { return ReportFormat.XLSX; }

    @Override
    public byte[] generate(ReportRequest request, ReportContext context) {
        if (request.format() != ReportFormat.XLSX) {
            throw new IllegalArgumentException("TRIP report is XLSX-only — see CLAUDE.md §10");
        }
        Trip trip = context.trip();
        try (Workbook wb = new XSSFWorkbook(); ByteArrayOutputStream bos = new ByteArrayOutputStream()) {
            Sheet sheet = wb.createSheet("Trip Expenses");
            CellStyle header = wb.createCellStyle();
            var headerFont = wb.createFont();
            headerFont.setBold(true);
            header.setFont(headerFont);
            header.setFillForegroundColor(IndexedColors.GREY_25_PERCENT.getIndex());
            header.setFillPattern(FillPatternType.SOLID_FOREGROUND);

            int r = 0;
            Row titleRow = sheet.createRow(r++);
            titleRow.createCell(0).setCellValue("PDD Petty Cash — Trip Report / تقرير الرحلة");
            Row metaRow = sheet.createRow(r++);
            metaRow.createCell(0).setCellValue("Trip / الرحلة:");
            metaRow.createCell(1).setCellValue(trip.getName());
            r++;

            String[] headers = {
                "Member / العضو",
                "Source / المصدر",
                "Category / الفئة",
                "Date / التاريخ",
                "Vendor / المورد",
                "Details / التفاصيل",
                "Qty / الكمية",
                "Amount / المبلغ",
                "Currency / العملة"
            };
            Row headRow = sheet.createRow(r++);
            for (int i = 0; i < headers.length; i++) {
                var c = headRow.createCell(i);
                c.setCellValue(headers[i]);
                c.setCellStyle(header);
            }

            long total = 0L;
            for (Expense e : context.expenses()) {
                User u = context.usersById().get(e.getUserId());
                Source src = context.sourcesById().get(e.getSourceId());
                ExpenseCategory cat = context.categoriesByCode().get(e.getCategoryCode());
                Row row = sheet.createRow(r++);
                row.createCell(0).setCellValue(u == null ? e.getUserId().toString()
                    : u.getDisplayName() + " / " + u.getDisplayNameAr());
                row.createCell(1).setCellValue(src == null ? e.getSourceId().toString()
                    : src.getName() + " / " + src.getNameAr());
                row.createCell(2).setCellValue(cat == null ? e.getCategoryCode()
                    : cat.getNameEn() + " / " + cat.getNameAr());
                row.createCell(3).setCellValue(e.getOccurredAt().toString());
                row.createCell(4).setCellValue(e.getVendor() == null ? "" : e.getVendor());
                row.createCell(5).setCellValue(e.getDetails() == null ? "" : e.getDetails());
                row.createCell(6).setCellValue(e.getQuantity());
                row.createCell(7).setCellValue(e.getAmount().amount());
                row.createCell(8).setCellValue(e.getAmount().currency());
                total += e.getAmount().amount();
            }

            r++;
            Row tot = sheet.createRow(r);
            var tl = tot.createCell(6);
            tl.setCellValue("Total / الإجمالي:");
            tl.setCellStyle(header);
            tot.createCell(7).setCellValue(total);
            tot.createCell(8).setCellValue(trip.getCurrency());

            for (int i = 0; i < headers.length; i++) sheet.autoSizeColumn(i);
            wb.write(bos);
            return bos.toByteArray();
        } catch (IOException ex) {
            throw new IllegalStateException("Failed to write TRIP xlsx report", ex);
        }
    }

    @SuppressWarnings("unused")
    private static UUID _ignored() { return null; }
}
