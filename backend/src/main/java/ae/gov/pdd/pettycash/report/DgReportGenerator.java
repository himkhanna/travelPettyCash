package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseCategory;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.AllocationStatus;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.user.User;
import com.lowagie.text.Document;
import com.lowagie.text.Element;
import com.lowagie.text.Font;
import com.lowagie.text.FontFactory;
import com.lowagie.text.PageSize;
import com.lowagie.text.Paragraph;
import com.lowagie.text.Phrase;
import com.lowagie.text.pdf.PdfPCell;
import com.lowagie.text.pdf.PdfPTable;
import com.lowagie.text.pdf.PdfWriter;
import org.springframework.stereotype.Component;

import java.awt.Color;
import java.io.ByteArrayOutputStream;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * DG report — per-user spend, per-category spend, current balances.
 * PDF only, read-only summary for the Director General view. See CLAUDE.md §10.
 */
@Component
public class DgReportGenerator implements ReportGenerator {

    @Override public ReportType type() { return ReportType.DG; }
    @Override public ReportFormat format() { return ReportFormat.PDF; }

    @Override
    public byte[] generate(ReportRequest request, ReportContext context) {
        if (request.format() != ReportFormat.PDF) {
            throw new IllegalArgumentException("DG report is PDF-only — see CLAUDE.md §10");
        }
        Trip trip = context.trip();
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        Document doc = new Document(PageSize.A4);
        PdfWriter.getInstance(doc, bos);
        doc.open();

        Font titleFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 16);
        Font hFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 12);
        Font normalFont = FontFactory.getFont(FontFactory.HELVETICA, 11);

        Paragraph title = new Paragraph(
            "PDD Petty Cash — Director General Summary\n" +
            "ملخص المدير العام",
            titleFont);
        title.setAlignment(Element.ALIGN_CENTER);
        doc.add(title);
        doc.add(new Paragraph(" "));
        doc.add(new Paragraph("Trip / الرحلة: " + trip.getName(), normalFont));
        doc.add(new Paragraph("Currency / العملة: " + trip.getCurrency(), normalFont));
        doc.add(new Paragraph(" "));

        // Per-user spend.
        Map<UUID, Long> spendByUser = new LinkedHashMap<>();
        Map<UUID, Long> receivedByUser = new LinkedHashMap<>();
        Map<String, Long> spendByCategory = new LinkedHashMap<>();
        for (Expense e : context.expenses()) {
            spendByUser.merge(e.getUserId(), e.getAmount().amount(), Long::sum);
            spendByCategory.merge(e.getCategoryCode(), e.getAmount().amount(), Long::sum);
        }
        for (Allocation a : context.allocations()) {
            if (a.getStatus() == AllocationStatus.ACCEPTED) {
                receivedByUser.merge(a.getToUserId(), a.getAmount().amount(), Long::sum);
            }
        }

        doc.add(new Paragraph("Per-user spend / إنفاق المستخدمين", hFont));
        PdfPTable userTable = new PdfPTable(3);
        userTable.setWidthPercentage(100);
        addHeader(userTable, "User / المستخدم", "Spent / المنفق", "Balance / الرصيد");
        for (Map.Entry<UUID, Long> en : spendByUser.entrySet()) {
            User u = context.usersById().get(en.getKey());
            long received = receivedByUser.getOrDefault(en.getKey(), 0L);
            long balance = received - en.getValue();
            userTable.addCell(u == null ? en.getKey().toString()
                : u.getDisplayName() + " / " + u.getDisplayNameAr());
            userTable.addCell(Long.toString(en.getValue()));
            userTable.addCell(Long.toString(balance));
        }
        doc.add(userTable);
        doc.add(new Paragraph(" "));

        doc.add(new Paragraph("Per-category spend / إنفاق الفئات", hFont));
        PdfPTable catTable = new PdfPTable(2);
        catTable.setWidthPercentage(100);
        addHeader(catTable, "Category / الفئة", "Spent / المنفق");
        for (Map.Entry<String, Long> en : spendByCategory.entrySet()) {
            ExpenseCategory c = context.categoriesByCode().get(en.getKey());
            catTable.addCell(c == null ? en.getKey() : c.getNameEn() + " / " + c.getNameAr());
            catTable.addCell(Long.toString(en.getValue()));
        }
        doc.add(catTable);
        doc.close();
        return bos.toByteArray();
    }

    private void addHeader(PdfPTable table, String... cols) {
        for (String c : cols) {
            PdfPCell cell = new PdfPCell(new Phrase(c));
            cell.setBackgroundColor(new Color(220, 220, 220));
            table.addCell(cell);
        }
    }
}
