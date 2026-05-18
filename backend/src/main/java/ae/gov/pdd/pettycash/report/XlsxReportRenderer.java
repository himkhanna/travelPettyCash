package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.expense.dto.ExpenseDto;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.user.User;
import org.apache.poi.ss.usermodel.BorderStyle;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.FillPatternType;
import org.apache.poi.ss.usermodel.Font;
import org.apache.poi.ss.usermodel.HorizontalAlignment;
import org.apache.poi.ss.usermodel.IndexedColors;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.util.CellRangeAddress;
import org.apache.poi.xssf.usermodel.XSSFSheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Component;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;

/**
 * Apache POI XLSX renderer. Produces a clean two-section workbook:
 * a header band (trip identity, dates, budget), then one table per
 * report kind. Currency values are formatted as the trip's currency
 * code prefix + major-unit decimal, no per-cell custom formats so the
 * output opens cleanly in any spreadsheet.
 */
@Component
public class XlsxReportRenderer {

    private static final DateTimeFormatter DATE = DateTimeFormatter
        .ofPattern("d MMM yyyy", Locale.ENGLISH)
        .withZone(ZoneId.systemDefault());

    public String contentType() {
        return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    }

    public byte[] userReport(
        ReportService.ReportContext ctx,
        User target,
        ReportService.ReportData data
    ) {
        try (XSSFWorkbook wb = new XSSFWorkbook()) {
            XSSFSheet sheet = wb.createSheet("User Report");
            Styles s = new Styles(wb);
            int r = writeHeader(sheet, s,
                "USER EXPENSE REPORT — " + target.getDisplayName(),
                ctx);

            // Per-source group
            for (var grp : data.bySource().entrySet()) {
                Source src = ctx.sourceById.get(grp.getKey());
                String srcName = src != null ? src.getName() : grp.getKey().toString();
                r = writeSourceHeader(sheet, s, r, srcName);
                r = writeExpenseTable(sheet, s, r, ctx, grp.getValue());
                r++;
            }
            // Grand total
            Row row = sheet.createRow(r);
            cell(row, 0, "GRAND TOTAL", s.bold);
            cell(row, 4, formatMoney(ctx.trip.currency(), data.totalMinor()), s.boldRight);
            autosize(sheet, 7);
            return toBytes(wb);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public byte[] tripFull(ReportService.ReportContext ctx) {
        try (XSSFWorkbook wb = new XSSFWorkbook()) {
            XSSFSheet sheet = wb.createSheet("Trip Expenses");
            Styles s = new Styles(wb);
            int r = writeHeader(sheet, s,
                "FULL TRIP EXPENSES — " + ctx.trip.name(), ctx);

            // Group by user
            var byUser = ctx.expenses.stream().collect(
                java.util.stream.Collectors.groupingBy(ExpenseDto::userId));
            long grandTotal = 0;
            for (var grp : byUser.entrySet()) {
                User u = ctx.userById.get(grp.getKey());
                String name = u != null ? u.getDisplayName() : grp.getKey().toString();
                long subtotal = grp.getValue().stream()
                    .mapToLong(e -> e.amount().amount()).sum();
                grandTotal += subtotal;
                r = writeSourceHeader(sheet, s, r, name +
                    "   —   " + formatMoney(ctx.trip.currency(), subtotal));
                r = writeExpenseTable(sheet, s, r, ctx, grp.getValue());
                r++;
            }
            Row row = sheet.createRow(r);
            cell(row, 0, "GRAND TOTAL", s.bold);
            cell(row, 4, formatMoney(ctx.trip.currency(), grandTotal), s.boldRight);
            autosize(sheet, 7);
            return toBytes(wb);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    // ---- helpers -----------------------------------------------------

    private int writeHeader(XSSFSheet sheet, Styles s, String title,
                            ReportService.ReportContext ctx) {
        Row r0 = sheet.createRow(0);
        cell(r0, 0, "PDD Delegation Expenses", s.title);
        sheet.addMergedRegion(new CellRangeAddress(0, 0, 0, 6));
        Row r1 = sheet.createRow(1);
        cell(r1, 0, "صرفيات الوفود الرسمية", s.subtle);
        sheet.addMergedRegion(new CellRangeAddress(1, 1, 0, 6));
        Row r2 = sheet.createRow(2);
        cell(r2, 0, title, s.h1);
        sheet.addMergedRegion(new CellRangeAddress(2, 2, 0, 6));
        Row r3 = sheet.createRow(3);
        cell(r3, 0, ctx.trip.name() + " · " + ctx.trip.countryName() +
            " · " + ctx.trip.currency(), s.subtle);
        sheet.addMergedRegion(new CellRangeAddress(3, 3, 0, 6));
        Row r4 = sheet.createRow(4);
        cell(r4, 0, "Generated " + DATE.format(java.time.Instant.now()), s.subtle);
        sheet.addMergedRegion(new CellRangeAddress(4, 4, 0, 6));
        return 6;
    }

    private int writeSourceHeader(XSSFSheet sheet, Styles s, int r, String text) {
        Row row = sheet.createRow(r);
        cell(row, 0, text, s.sectionHeader);
        sheet.addMergedRegion(new CellRangeAddress(r, r, 0, 6));
        return r + 1;
    }

    private int writeExpenseTable(
        XSSFSheet sheet, Styles s, int startRow,
        ReportService.ReportContext ctx, List<ExpenseDto> rows
    ) {
        Row header = sheet.createRow(startRow);
        cell(header, 0, "DATE", s.tableHead);
        cell(header, 1, "USER", s.tableHead);
        cell(header, 2, "CATEGORY", s.tableHead);
        cell(header, 3, "DETAILS", s.tableHead);
        cell(header, 4, "AMOUNT", s.tableHeadRight);
        int r = startRow + 1;
        for (ExpenseDto e : rows) {
            Row row = sheet.createRow(r++);
            cell(row, 0, DATE.format(e.occurredAt()), s.cell);
            User u = ctx.userById.get(e.userId());
            cell(row, 1, u != null ? u.getDisplayName() : "—", s.cell);
            var cat = ctx.catByCode.get(e.categoryCode());
            cell(row, 2, cat != null ? cat.getNameEn() : e.categoryCode(), s.cell);
            cell(row, 3, e.details() != null ? e.details() : "—", s.cell);
            cell(row, 4,
                formatMoney(ctx.trip.currency(), e.amount().amount()),
                s.cellRight);
        }
        return r;
    }

    private static void cell(Row r, int col, String text, CellStyle style) {
        Cell c = r.createCell(col);
        c.setCellValue(text);
        if (style != null) c.setCellStyle(style);
    }

    private static void autosize(XSSFSheet sheet, int upTo) {
        for (int i = 0; i < upTo; i++) sheet.autoSizeColumn(i);
    }

    private static String formatMoney(String currency, long minor) {
        return String.format(Locale.ENGLISH, "%s %,.2f", currency, minor / 100.0);
    }

    private static byte[] toBytes(XSSFWorkbook wb) throws IOException {
        try (ByteArrayOutputStream out = new ByteArrayOutputStream(64 * 1024)) {
            wb.write(out);
            return out.toByteArray();
        }
    }

    /** Small bag of reusable styles per workbook. */
    private static final class Styles {
        final CellStyle title;
        final CellStyle h1;
        final CellStyle subtle;
        final CellStyle sectionHeader;
        final CellStyle tableHead;
        final CellStyle tableHeadRight;
        final CellStyle cell;
        final CellStyle cellRight;
        final CellStyle bold;
        final CellStyle boldRight;

        Styles(XSSFWorkbook wb) {
            Font bigBold = wb.createFont();
            bigBold.setBold(true);
            bigBold.setFontHeightInPoints((short) 16);
            title = wb.createCellStyle();
            title.setFont(bigBold);

            Font hFont = wb.createFont();
            hFont.setBold(true);
            hFont.setFontHeightInPoints((short) 12);
            h1 = wb.createCellStyle();
            h1.setFont(hFont);

            Font subFont = wb.createFont();
            subFont.setItalic(true);
            subFont.setColor(IndexedColors.GREY_50_PERCENT.getIndex());
            subtle = wb.createCellStyle();
            subtle.setFont(subFont);

            Font sectionFont = wb.createFont();
            sectionFont.setBold(true);
            sectionFont.setColor(IndexedColors.WHITE.getIndex());
            sectionHeader = wb.createCellStyle();
            sectionHeader.setFont(sectionFont);
            sectionHeader.setFillForegroundColor(IndexedColors.BROWN.getIndex());
            sectionHeader.setFillPattern(FillPatternType.SOLID_FOREGROUND);

            Font headFont = wb.createFont();
            headFont.setBold(true);
            tableHead = wb.createCellStyle();
            tableHead.setFont(headFont);
            tableHead.setFillForegroundColor(IndexedColors.GREY_25_PERCENT.getIndex());
            tableHead.setFillPattern(FillPatternType.SOLID_FOREGROUND);
            tableHead.setBorderBottom(BorderStyle.THIN);
            tableHeadRight = wb.createCellStyle();
            tableHeadRight.cloneStyleFrom(tableHead);
            tableHeadRight.setAlignment(HorizontalAlignment.RIGHT);

            cell = wb.createCellStyle();
            cell.setBorderBottom(BorderStyle.THIN);
            cellRight = wb.createCellStyle();
            cellRight.cloneStyleFrom(cell);
            cellRight.setAlignment(HorizontalAlignment.RIGHT);

            Font bf = wb.createFont();
            bf.setBold(true);
            bold = wb.createCellStyle();
            bold.setFont(bf);
            boldRight = wb.createCellStyle();
            boldRight.setFont(bf);
            boldRight.setAlignment(HorizontalAlignment.RIGHT);
        }
    }
}
