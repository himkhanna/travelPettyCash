package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.AllocationStatus;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.trip.Trip;
import com.lowagie.text.Document;
import com.lowagie.text.Element;
import com.lowagie.text.Font;
import com.lowagie.text.FontFactory;
import com.lowagie.text.PageSize;
import com.lowagie.text.Paragraph;
import com.lowagie.text.Phrase;
import com.lowagie.text.pdf.PdfContentByte;
import com.lowagie.text.pdf.PdfGState;
import com.lowagie.text.pdf.PdfPCell;
import com.lowagie.text.pdf.PdfPTable;
import com.lowagie.text.pdf.PdfPageEventHelper;
import com.lowagie.text.pdf.PdfWriter;
import org.springframework.stereotype.Component;

import java.awt.Color;
import java.io.ByteArrayOutputStream;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * FINANCE letterhead — sources used, totals per source, net balance returned.
 *
 * <p>PDF only per CLAUDE.md §10. <b>Watermarked "DRAFT — unsigned"</b> until
 * PAdES signing is unblocked by ADR-003 (signing key custody pending). The
 * watermark is a low-opacity rotated overlay so the page is clearly identified
 * as not-yet-signed in any printout.
 */
@Component
public class FinanceLetterGenerator implements ReportGenerator {

    @Override public ReportType type() { return ReportType.FINANCE; }
    @Override public ReportFormat format() { return ReportFormat.PDF; }

    @Override
    public byte[] generate(ReportRequest request, ReportContext context) {
        if (request.format() != ReportFormat.PDF) {
            throw new IllegalArgumentException("FINANCE letter is PDF-only — see CLAUDE.md §10");
        }
        Trip trip = context.trip();
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        Document doc = new Document(PageSize.A4);
        PdfWriter writer = PdfWriter.getInstance(doc, bos);
        writer.setPageEvent(new DraftWatermark());
        doc.open();

        Font titleFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 16);
        Font normalFont = FontFactory.getFont(FontFactory.HELVETICA, 11);

        Paragraph title = new Paragraph(
            "PDD Petty Cash — Finance Reconciliation Letter\n" +
            "خطاب تسوية صرفيات السفر",
            titleFont);
        title.setAlignment(Element.ALIGN_CENTER);
        doc.add(title);
        doc.add(new Paragraph(" "));

        doc.add(new Paragraph("Trip / الرحلة: " + trip.getName(), normalFont));
        doc.add(new Paragraph("Country / الدولة: " + trip.getCountryName()
            + " (" + trip.getCountryCode() + ")", normalFont));
        doc.add(new Paragraph("Currency / العملة: " + trip.getCurrency(), normalFont));
        doc.add(new Paragraph(" "));

        // Per-source totals: received via allocations, spent via expenses, balance.
        Map<UUID, long[]> bySource = new LinkedHashMap<>();
        // index 0 = received (ACCEPTED allocations), 1 = spent (expenses)
        for (Allocation a : context.allocations()) {
            if (a.getStatus() != AllocationStatus.ACCEPTED) continue;
            bySource.computeIfAbsent(a.getSourceId(), k -> new long[2])[0] += a.getAmount().amount();
        }
        for (Expense e : context.expenses()) {
            bySource.computeIfAbsent(e.getSourceId(), k -> new long[2])[1] += e.getAmount().amount();
        }

        PdfPTable table = new PdfPTable(4);
        table.setWidthPercentage(100);
        for (String h : new String[]{
            "Source / المصدر",
            "Received / المستلم",
            "Spent / المنفق",
            "Returned / المرتجع"
        }) {
            PdfPCell c = new PdfPCell(new Phrase(h));
            c.setBackgroundColor(new Color(220, 220, 220));
            table.addCell(c);
        }
        long totalReceived = 0, totalSpent = 0;
        for (Map.Entry<UUID, long[]> en : bySource.entrySet()) {
            Source src = context.sourcesById().get(en.getKey());
            long received = en.getValue()[0];
            long spent = en.getValue()[1];
            long returned = received - spent;
            table.addCell(src == null ? en.getKey().toString() : (src.getName() + " / " + src.getNameAr()));
            table.addCell(Long.toString(received));
            table.addCell(Long.toString(spent));
            table.addCell(Long.toString(returned));
            totalReceived += received;
            totalSpent += spent;
        }
        // Totals row
        PdfPCell totalLabel = new PdfPCell(new Phrase("Total / الإجمالي"));
        totalLabel.setBackgroundColor(new Color(240, 240, 200));
        table.addCell(totalLabel);
        table.addCell(Long.toString(totalReceived));
        table.addCell(Long.toString(totalSpent));
        table.addCell(Long.toString(totalReceived - totalSpent));
        doc.add(table);

        doc.add(new Paragraph(" "));
        doc.add(new Paragraph("Net balance returned / صافي الرصيد المرتجع: "
            + (totalReceived - totalSpent) + " " + trip.getCurrency(), normalFont));
        doc.add(new Paragraph(" "));
        doc.add(new Paragraph(
            "This document is UNSIGNED. Digital signature pending — see ADR-003.\n"
            + "هذا المستند غير موقع. التوقيع الرقمي معلق.", normalFont));

        doc.close();
        return bos.toByteArray();
    }

    /** Diagonal "DRAFT — unsigned" overlay drawn on every page via a page-event hook. */
    private static final class DraftWatermark extends PdfPageEventHelper {
        @Override
        public void onEndPage(PdfWriter writer, Document document) {
            PdfContentByte under = writer.getDirectContentUnder();
            under.saveState();
            PdfGState gs = new PdfGState();
            gs.setFillOpacity(0.18f);
            under.setGState(gs);
            under.beginText();
            Font f = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 64);
            under.setFontAndSize(f.getBaseFont(), 64);
            under.setColorFill(new Color(180, 0, 0));
            under.showTextAligned(Element.ALIGN_CENTER,
                "DRAFT — UNSIGNED",
                PageSize.A4.getWidth() / 2,
                PageSize.A4.getHeight() / 2,
                45f);
            under.endText();
            under.restoreState();
        }
    }
}
