package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseCategory;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.user.User;
import com.lowagie.text.Document;
import com.lowagie.text.Element;
import com.lowagie.text.Font;
import com.lowagie.text.FontFactory;
import com.lowagie.text.PageSize;
import com.lowagie.text.Paragraph;
import com.lowagie.text.pdf.PdfPCell;
import com.lowagie.text.pdf.PdfPTable;
import com.lowagie.text.pdf.PdfWriter;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.IndexedColors;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Component;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * USER report — single user's expenses grouped by source then category.
 * Both XLSX and PDF formats supported. See CLAUDE.md §10.
 *
 * <p>Headers are bilingual EN + AR per the brief; category names come from
 * {@link ExpenseCategory#getNameEn()} / {@link ExpenseCategory#getNameAr()}.
 */
@Component
public class UserReportGenerator implements ReportGenerator {

    @Override public ReportType type() { return ReportType.USER; }
    @Override public ReportFormat format() {
        // This generator handles both XLSX and PDF; the registry uses the (type, format)
        // pair to dispatch. We return XLSX as the primary; PDF is also delivered via the
        // same component using ReportRequest.format().
        return ReportFormat.XLSX;
    }

    @Override
    public byte[] generate(ReportRequest request, ReportContext context) {
        return switch (request.format()) {
            case XLSX -> generateXlsx(request, context);
            case PDF  -> generatePdf(request, context);
        };
    }

    private byte[] generateXlsx(ReportRequest request, ReportContext context) {
        Trip trip = context.trip();
        UUID userId = request.userId();
        String userLabel = userLabel(context.usersById().get(userId), userId);

        try (Workbook wb = new XSSFWorkbook(); ByteArrayOutputStream bos = new ByteArrayOutputStream()) {
            Sheet sheet = wb.createSheet("User Expenses");
            CellStyle header = wb.createCellStyle();
            org.apache.poi.ss.usermodel.Font headerFont = wb.createFont();
            headerFont.setBold(true);
            header.setFont(headerFont);
            header.setFillForegroundColor(IndexedColors.GREY_25_PERCENT.getIndex());
            header.setFillPattern(org.apache.poi.ss.usermodel.FillPatternType.SOLID_FOREGROUND);

            int r = 0;
            // Title row.
            Row titleRow = sheet.createRow(r++);
            titleRow.createCell(0).setCellValue("PDD Petty Cash — User Report / تقرير صرفيات المستخدم");
            Row metaRow = sheet.createRow(r++);
            metaRow.createCell(0).setCellValue("Trip / الرحلة:");
            metaRow.createCell(1).setCellValue(trip.getName());
            Row userRow = sheet.createRow(r++);
            userRow.createCell(0).setCellValue("User / المستخدم:");
            userRow.createCell(1).setCellValue(userLabel);
            r++;

            // Column headers EN + AR.
            String[] headers = {
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
                org.apache.poi.ss.usermodel.Cell c = headRow.createCell(i);
                c.setCellValue(headers[i]);
                c.setCellStyle(header);
            }

            // Group by source, then category. Stable insertion order via LinkedHashMap.
            Map<UUID, Map<String, List<Expense>>> bySrcThenCat = new LinkedHashMap<>();
            for (Expense e : context.expenses()) {
                if (userId != null && !userId.equals(e.getUserId())) continue;
                bySrcThenCat
                    .computeIfAbsent(e.getSourceId(), k -> new LinkedHashMap<>())
                    .computeIfAbsent(e.getCategoryCode(), k -> new java.util.ArrayList<>())
                    .add(e);
            }

            long grandTotalMinor = 0L;
            for (Map.Entry<UUID, Map<String, List<Expense>>> srcEntry : bySrcThenCat.entrySet()) {
                Source src = context.sourcesById().get(srcEntry.getKey());
                String srcLabel = src == null ? srcEntry.getKey().toString() : (src.getName() + " / " + src.getNameAr());
                for (Map.Entry<String, List<Expense>> catEntry : srcEntry.getValue().entrySet()) {
                    ExpenseCategory cat = context.categoriesByCode().get(catEntry.getKey());
                    String catLabel = cat == null ? catEntry.getKey() : (cat.getNameEn() + " / " + cat.getNameAr());
                    for (Expense e : catEntry.getValue()) {
                        Row row = sheet.createRow(r++);
                        row.createCell(0).setCellValue(srcLabel);
                        row.createCell(1).setCellValue(catLabel);
                        row.createCell(2).setCellValue(e.getOccurredAt().toString());
                        row.createCell(3).setCellValue(e.getVendor() == null ? "" : e.getVendor());
                        row.createCell(4).setCellValue(e.getDetails() == null ? "" : e.getDetails());
                        row.createCell(5).setCellValue(e.getQuantity());
                        // Display in minor units; finance reconciles via the currency column.
                        row.createCell(6).setCellValue(e.getAmount().amount());
                        row.createCell(7).setCellValue(e.getAmount().currency());
                        grandTotalMinor += e.getAmount().amount();
                    }
                }
            }

            r++;
            Row total = sheet.createRow(r);
            org.apache.poi.ss.usermodel.Cell tlabel = total.createCell(5);
            tlabel.setCellValue("Total / الإجمالي:");
            tlabel.setCellStyle(header);
            total.createCell(6).setCellValue(grandTotalMinor);
            total.createCell(7).setCellValue(trip.getCurrency());

            for (int i = 0; i < headers.length; i++) sheet.autoSizeColumn(i);

            wb.write(bos);
            return bos.toByteArray();
        } catch (IOException ex) {
            throw new IllegalStateException("Failed to write USER xlsx report", ex);
        }
    }

    private byte[] generatePdf(ReportRequest request, ReportContext context) {
        Trip trip = context.trip();
        UUID userId = request.userId();
        String userLabel = userLabel(context.usersById().get(userId), userId);

        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        Document doc = new Document(PageSize.A4);
        PdfWriter.getInstance(doc, bos);
        doc.open();
        Font titleFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 14);
        doc.add(new Paragraph("PDD Petty Cash — User Report / تقرير صرفيات المستخدم", titleFont));
        doc.add(new Paragraph("Trip / الرحلة: " + trip.getName()));
        doc.add(new Paragraph("User / المستخدم: " + userLabel));
        doc.add(new Paragraph(" "));

        PdfPTable table = new PdfPTable(6);
        table.setWidthPercentage(100);
        for (String h : new String[]{
            "Source / المصدر", "Category / الفئة", "Date / التاريخ",
            "Vendor / المورد", "Amount / المبلغ", "Currency / العملة"
        }) {
            PdfPCell c = new PdfPCell(new Paragraph(h));
            c.setHorizontalAlignment(Element.ALIGN_CENTER);
            table.addCell(c);
        }

        long total = 0L;
        for (Expense e : context.expenses()) {
            if (userId != null && !userId.equals(e.getUserId())) continue;
            Source src = context.sourcesById().get(e.getSourceId());
            ExpenseCategory cat = context.categoriesByCode().get(e.getCategoryCode());
            table.addCell(src == null ? e.getSourceId().toString() : (src.getName() + " / " + src.getNameAr()));
            table.addCell(cat == null ? e.getCategoryCode() : (cat.getNameEn() + " / " + cat.getNameAr()));
            table.addCell(e.getOccurredAt().toString());
            table.addCell(e.getVendor() == null ? "" : e.getVendor());
            table.addCell(Long.toString(e.getAmount().amount()));
            table.addCell(e.getAmount().currency());
            total += e.getAmount().amount();
        }
        doc.add(table);
        doc.add(new Paragraph("Total / الإجمالي: " + total + " " + trip.getCurrency()));
        doc.close();
        return bos.toByteArray();
    }

    private String userLabel(User u, UUID id) {
        if (u == null) return id == null ? "(unknown)" : id.toString();
        return u.getDisplayName() + " / " + u.getDisplayNameAr();
    }
}
