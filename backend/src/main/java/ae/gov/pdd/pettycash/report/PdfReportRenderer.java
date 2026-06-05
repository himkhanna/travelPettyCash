package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.expense.dto.ExpenseDto;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.user.User;
import com.lowagie.text.Chunk;
import com.lowagie.text.Document;
import com.lowagie.text.DocumentException;
import com.lowagie.text.Element;
import com.lowagie.text.Font;
import com.lowagie.text.FontFactory;
import com.lowagie.text.PageSize;
import com.lowagie.text.Paragraph;
import com.lowagie.text.Phrase;
import com.lowagie.text.Rectangle;
import com.lowagie.text.pdf.PdfPCell;
import com.lowagie.text.pdf.PdfPTable;
import com.lowagie.text.pdf.PdfWriter;
import org.springframework.stereotype.Component;

import java.awt.Color;
import java.io.ByteArrayOutputStream;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/**
 * OpenPDF renderer (LGPL — see CLAUDE.md §3 dependency notes). Produces
 * unsigned PDFs; the digital signature pass is a separate step the Admin
 * triggers later via the existing SignatureService.
 *
 * Style is deliberately government-letter sober: brown title bar, light
 * cream backgrounds for section headers, no images or fancy fonts.
 */
@Component
public class PdfReportRenderer {

    private static final Color BRAND_BROWN = new Color(0x5C, 0x4A, 0x2F);
    private static final Color CREAM = new Color(0xF5, 0xEC, 0xD7);
    private static final Color OUTFLOW = new Color(0xC8, 0x3E, 0x3E);
    private static final Color TEXT_SECONDARY = new Color(0x7B, 0x6F, 0x5C);

    private static final DateTimeFormatter DATE = DateTimeFormatter
        .ofPattern("d MMM yyyy", Locale.ENGLISH)
        .withZone(ZoneId.systemDefault());

    public String contentType() { return "application/pdf"; }

    public byte[] userReport(
        ReportService.ReportContext ctx,
        User target,
        ReportService.ReportData data
    ) {
        return render(doc -> {
            letterhead(doc, "USER EXPENSE REPORT", ctx);
            doc.add(p("Prepared for: " + target.getDisplayName(), bold(12)));
            doc.add(Chunk.NEWLINE);

            for (Map.Entry<UUID, List<ExpenseDto>> grp : data.bySource().entrySet()) {
                Source src = ctx.sourceById.get(grp.getKey());
                String srcName = src != null ? src.getName() : grp.getKey().toString();
                sectionHeader(doc, srcName.toUpperCase(Locale.ROOT));
                expenseTable(doc, ctx, grp.getValue(), /*includeUser*/ false);
                doc.add(Chunk.NEWLINE);
            }

            totalLine(doc, "TOTAL", formatMoney(ctx.trip.currency(), data.totalMinor()));
        });
    }

    public byte[] tripFull(ReportService.ReportContext ctx) {
        return render(doc -> {
            letterhead(doc, "FULL TRIP EXPENSES", ctx);

            var byUser = ctx.expenses.stream().collect(
                java.util.stream.Collectors.groupingBy(ExpenseDto::userId));
            long grand = 0;
            for (var grp : byUser.entrySet()) {
                User u = ctx.userById.get(grp.getKey());
                long subtotal = grp.getValue().stream()
                    .mapToLong(e -> e.amount().amount()).sum();
                grand += subtotal;
                String label = (u != null ? u.getDisplayName() : "Unknown") +
                    "   —   " + formatMoney(ctx.trip.currency(), subtotal);
                sectionHeader(doc, label);
                expenseTable(doc, ctx, grp.getValue(), /*includeUser*/ false);
                doc.add(Chunk.NEWLINE);
            }
            totalLine(doc, "GRAND TOTAL", formatMoney(ctx.trip.currency(), grand));
        });
    }

    public byte[] financeLetter(ReportService.ReportContext ctx) {
        return render(doc -> {
            letterhead(doc, "FINANCE DEPARTMENT LETTER", ctx);

            doc.add(p("To: Finance Department, Protocol Department — " +
                "Government of Dubai", regular(11)));
            doc.add(p("From: Office of the Director General", regular(11)));
            doc.add(Chunk.NEWLINE);

            long totalSpent = ctx.expenses.stream()
                .mapToLong(e -> e.amount().amount()).sum();
            long totalBudget = ctx.trip.totalBudget().amount();
            long returned = totalBudget - totalSpent;
            String currency = ctx.trip.currency();

            doc.add(p("Re: " + ctx.trip.name() + " — " + ctx.trip.countryName(),
                bold(12)));
            doc.add(Chunk.NEWLINE);

            doc.add(p("This letter confirms the reconciliation of petty cash " +
                "advanced for the delegation referenced above, drawn from " +
                "the funding sources noted below.", regular(11)));
            doc.add(Chunk.NEWLINE);

            // Per-source breakdown
            sectionHeader(doc, "SOURCES USED");
            PdfPTable t = new PdfPTable(new float[] { 4f, 2f, 2f, 2f });
            t.setWidthPercentage(100);
            tableHeader(t, "SOURCE", "ALLOCATED", "SPENT", "RETURNED");
            for (Source s : ctx.sourceById.values()) {
                long spent = ctx.expenses.stream()
                    .filter(e -> e.sourceId().equals(s.getId()))
                    .mapToLong(e -> e.amount().amount()).sum();
                long allocated = ctx.allocatedBySource.getOrDefault(s.getId(), 0L);
                if (spent == 0 && allocated == 0) continue;
                // Allocated = accepted admin-pool allocations from this source;
                // returned = allocated − spent (BRD §2.6). Falls back to "—"
                // when allocation data isn't available (e.g. mission rollup).
                String allocatedCell = allocated > 0 ? formatMoney(currency, allocated) : "—";
                String returnedCell = allocated > 0
                    ? formatMoney(currency, allocated - spent) : "—";
                tableRow(t, s.getName(), allocatedCell,
                    formatMoney(currency, spent), returnedCell);
            }
            doc.add(t);
            doc.add(Chunk.NEWLINE);

            // Reconciliation summary
            sectionHeader(doc, "RECONCILIATION SUMMARY");
            PdfPTable r = new PdfPTable(new float[] { 5f, 3f });
            r.setWidthPercentage(60);
            tableRow(r, "Total budget advanced", formatMoney(currency, totalBudget));
            tableRow(r, "Total spent on delegation", formatMoney(currency, totalSpent));
            tableRow(r, "Net balance returned", formatMoney(currency, returned));
            doc.add(r);
            doc.add(Chunk.NEWLINE);
            doc.add(Chunk.NEWLINE);

            doc.add(p("Signed by: ____________________________", regular(11)));
            doc.add(p("Date: " + DATE.format(java.time.Instant.now()), regular(11)));
            doc.add(Chunk.NEWLINE);
            doc.add(p("This document is generated by the PDD Delegation " +
                "Expenses system. A separate digital signature (PAdES) is " +
                "applied by the Admin before submission.", italic(9)));
        });
    }

    public byte[] dgReport(ReportService.ReportContext ctx) {
        return render(doc -> {
            letterhead(doc, "DIRECTOR GENERAL OVERVIEW", ctx);

            // Per-user totals
            sectionHeader(doc, "SPEND BY MEMBER");
            PdfPTable t1 = new PdfPTable(new float[] { 4f, 2f });
            t1.setWidthPercentage(80);
            tableHeader(t1, "MEMBER", "TOTAL");
            var byUser = ctx.expenses.stream().collect(
                java.util.stream.Collectors.groupingBy(
                    ExpenseDto::userId,
                    java.util.stream.Collectors.summingLong(
                        e -> e.amount().amount())));
            byUser.forEach((id, sum) -> {
                User u = ctx.userById.get(id);
                tableRow(t1,
                    u != null ? u.getDisplayName() : id.toString(),
                    formatMoney(ctx.trip.currency(), sum));
            });
            doc.add(t1);
            doc.add(Chunk.NEWLINE);

            // Per-category
            sectionHeader(doc, "SPEND BY CATEGORY");
            PdfPTable t2 = new PdfPTable(new float[] { 4f, 2f });
            t2.setWidthPercentage(80);
            tableHeader(t2, "CATEGORY", "TOTAL");
            var byCat = ctx.expenses.stream().collect(
                java.util.stream.Collectors.groupingBy(
                    ExpenseDto::categoryCode,
                    java.util.stream.Collectors.summingLong(
                        e -> e.amount().amount())));
            byCat.forEach((code, sum) -> {
                var c = ctx.catByCode.get(code);
                tableRow(t2,
                    c != null ? c.getNameEn() : code,
                    formatMoney(ctx.trip.currency(), sum));
            });
            doc.add(t2);
            doc.add(Chunk.NEWLINE);

            long total = ctx.expenses.stream()
                .mapToLong(e -> e.amount().amount()).sum();
            totalLine(doc, "TRIP TOTAL",
                formatMoney(ctx.trip.currency(), total));
            doc.add(p("READ-ONLY · This view is for oversight; the " +
                "Director General does not record financial actions.",
                italic(9)));
        });
    }

    // ---- common ------------------------------------------------------

    @FunctionalInterface
    private interface DocBuilder {
        void build(Document doc) throws DocumentException;
    }

    private byte[] render(DocBuilder body) {
        ByteArrayOutputStream out = new ByteArrayOutputStream(64 * 1024);
        Document doc = new Document(PageSize.A4, 48, 48, 48, 48);
        try {
            PdfWriter.getInstance(doc, out);
            doc.open();
            body.build(doc);
            doc.close();
            return out.toByteArray();
        } catch (DocumentException e) {
            throw new IllegalStateException("PDF generation failed", e);
        }
    }

    private void letterhead(Document doc, String title, ReportService.ReportContext ctx)
            throws DocumentException {
        // Title bar — brand brown background, cream text
        PdfPTable bar = new PdfPTable(1);
        bar.setWidthPercentage(100);
        PdfPCell cell = new PdfPCell();
        cell.setBackgroundColor(BRAND_BROWN);
        cell.setPadding(14f);
        cell.setBorder(Rectangle.NO_BORDER);
        Paragraph wordmark = new Paragraph(
            "PDD Delegation Expenses · صرفيات الوفود الرسمية",
            white(11, true));
        wordmark.setAlignment(Element.ALIGN_LEFT);
        cell.addElement(wordmark);
        Paragraph sub = new Paragraph(
            "Protocol Department · Government of Dubai", white(9, false));
        sub.setAlignment(Element.ALIGN_LEFT);
        cell.addElement(sub);
        bar.addCell(cell);
        doc.add(bar);

        // Title
        doc.add(new Paragraph("\n"));
        Paragraph t = new Paragraph(title, bold(16));
        t.setSpacingAfter(4f);
        doc.add(t);

        // Trip line
        Paragraph trip = new Paragraph(
            ctx.trip.name() + " · " + ctx.trip.countryName() +
            " · " + ctx.trip.currency(), regular(11));
        trip.setSpacingAfter(2f);
        doc.add(trip);
        Paragraph dates = new Paragraph(
            "Created " + DATE.format(ctx.trip.createdAt()) +
            (ctx.trip.closedAt() != null
                ? " → Closed " + DATE.format(ctx.trip.closedAt())
                : "") +
            "   ·   Report generated " + DATE.format(java.time.Instant.now()),
            italic(9));
        dates.setSpacingAfter(16f);
        doc.add(dates);
    }

    private void sectionHeader(Document doc, String text) throws DocumentException {
        PdfPTable t = new PdfPTable(1);
        t.setWidthPercentage(100);
        PdfPCell c = new PdfPCell(new Phrase(text, bold(11)));
        c.setBackgroundColor(CREAM);
        c.setPadding(8f);
        c.setBorder(Rectangle.NO_BORDER);
        t.addCell(c);
        t.setSpacingBefore(6f);
        t.setSpacingAfter(6f);
        doc.add(t);
    }

    private void expenseTable(
        Document doc,
        ReportService.ReportContext ctx,
        List<ExpenseDto> rows,
        boolean includeUser
    ) throws DocumentException {
        int cols = includeUser ? 5 : 4;
        float[] widths = includeUser
            ? new float[] { 1.5f, 2f, 2f, 3f, 1.5f }
            : new float[] { 1.5f, 2f, 3f, 1.5f };
        PdfPTable t = new PdfPTable(widths);
        t.setWidthPercentage(100);
        if (includeUser) {
            tableHeader(t, "DATE", "USER", "CATEGORY", "DETAILS", "AMOUNT");
        } else {
            tableHeader(t, "DATE", "CATEGORY", "DETAILS", "AMOUNT");
        }
        for (ExpenseDto e : rows) {
            if (includeUser) {
                User u = ctx.userById.get(e.userId());
                tableRow(t,
                    DATE.format(e.occurredAt()),
                    u != null ? u.getDisplayName() : "—",
                    catName(ctx, e.categoryCode()),
                    e.details() != null ? e.details() : "—",
                    formatMoney(ctx.trip.currency(), e.amount().amount()));
            } else {
                tableRow(t,
                    DATE.format(e.occurredAt()),
                    catName(ctx, e.categoryCode()),
                    e.details() != null ? e.details() : "—",
                    formatMoney(ctx.trip.currency(), e.amount().amount()));
            }
        }
        doc.add(t);
    }

    private void totalLine(Document doc, String label, String value) throws DocumentException {
        PdfPTable t = new PdfPTable(new float[] { 4f, 2f });
        t.setWidthPercentage(60);
        t.setHorizontalAlignment(Element.ALIGN_LEFT);
        PdfPCell l = new PdfPCell(new Phrase(label, bold(11)));
        l.setBorder(Rectangle.TOP);
        l.setPadding(6f);
        PdfPCell v = new PdfPCell(new Phrase(value, bold(11, BRAND_BROWN)));
        v.setBorder(Rectangle.TOP);
        v.setHorizontalAlignment(Element.ALIGN_RIGHT);
        v.setPadding(6f);
        t.addCell(l);
        t.addCell(v);
        doc.add(t);
        doc.add(new Paragraph("\n"));
    }

    private static String catName(ReportService.ReportContext ctx, String code) {
        var c = ctx.catByCode.get(code);
        return c != null ? c.getNameEn() : code;
    }

    private static String formatMoney(String currency, long minor) {
        return String.format(Locale.ENGLISH, "%s %,.2f", currency, minor / 100.0);
    }

    private static void tableHeader(PdfPTable t, String... cols) {
        for (String c : cols) {
            PdfPCell h = new PdfPCell(new Phrase(c, bold(9)));
            h.setBackgroundColor(new Color(0xE8, 0xE0, 0xC8));
            h.setPadding(5f);
            h.setBorder(Rectangle.BOTTOM);
            t.addCell(h);
        }
    }

    private static void tableRow(PdfPTable t, String... cols) {
        for (int i = 0; i < cols.length; i++) {
            PdfPCell c = new PdfPCell(new Phrase(cols[i], regular(9)));
            c.setPadding(4f);
            c.setBorder(Rectangle.BOTTOM);
            c.setBorderColor(new Color(0xE0, 0xDA, 0xC8));
            // Right-align the last column (amount)
            if (i == cols.length - 1) {
                c.setHorizontalAlignment(Element.ALIGN_RIGHT);
            }
            t.addCell(c);
        }
    }

    private static Paragraph p(String text, Font font) {
        Paragraph p = new Paragraph(text, font);
        p.setSpacingAfter(2f);
        return p;
    }

    private static Font regular(int sz) {
        return FontFactory.getFont(FontFactory.HELVETICA, sz, Color.BLACK);
    }

    private static Font bold(int sz) {
        return FontFactory.getFont(FontFactory.HELVETICA_BOLD, sz, Color.BLACK);
    }

    private static Font bold(int sz, Color c) {
        return FontFactory.getFont(FontFactory.HELVETICA_BOLD, sz, c);
    }

    private static Font italic(int sz) {
        return FontFactory.getFont(FontFactory.HELVETICA_OBLIQUE, sz, TEXT_SECONDARY);
    }

    private static Font white(int sz, boolean isBold) {
        return FontFactory.getFont(
            isBold ? FontFactory.HELVETICA_BOLD : FontFactory.HELVETICA,
            sz, CREAM);
    }
}
