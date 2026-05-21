package ae.gov.pdd.pettycash.api;

import ae.gov.pdd.pettycash.common.NotFoundException;
import ae.gov.pdd.pettycash.expense.ExpenseEntity;
import ae.gov.pdd.pettycash.expense.ExpenseRepository;
import ae.gov.pdd.pettycash.trip.TripEntity;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.user.UserEntity;
import ae.gov.pdd.pettycash.user.UserRepository;
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
import java.awt.Color;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.FillPatternType;
import org.apache.poi.ss.usermodel.IndexedColors;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.xssf.usermodel.XSSFCellStyle;
import org.apache.poi.xssf.usermodel.XSSFFont;
import org.apache.poi.xssf.usermodel.XSSFSheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/// Server-side report generation. xlsx via Apache POI, pdf via OpenPDF
/// (LGPL) — both run synchronously for now; move to @Async + signed URL
/// when a real object store is wired (CLAUDE.md §10).
@RestController
@RequestMapping("/api/v1/reports")
@PreAuthorize("hasAnyRole('ADMIN','SUPER_ADMIN','LEADER','MEMBER')")
public class ReportsController {

    private static final DateTimeFormatter DATE = DateTimeFormatter.ISO_LOCAL_DATE;

    private final TripRepository trips;
    private final ExpenseRepository expenses;
    private final UserRepository users;

    public ReportsController(TripRepository trips, ExpenseRepository expenses, UserRepository users) {
        this.trips = trips;
        this.expenses = expenses;
        this.users = users;
    }

    @GetMapping("/trip/{tripId}")
    public ResponseEntity<byte[]> tripReport(
            @PathVariable String tripId,
            @RequestParam(defaultValue = "xlsx") String format,
            @RequestParam(defaultValue = "team") String scope
    ) throws IOException {
        TripEntity trip = trips.findById(tripId).orElseThrow(NotFoundException::new);
        List<ExpenseEntity> rows = expenses
                .findByTripIdAndDeletedAtIsNullOrderByOccurredAtDesc(tripId);
        Map<String, String> userNames = users.findAll().stream()
                .collect(Collectors.toMap(UserEntity::getId, UserEntity::getDisplayName));

        return switch (format.toLowerCase()) {
            case "xlsx" -> file(
                    "trip-" + trip.getId() + ".xlsx",
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    renderXlsx(trip, rows, userNames, scope)
            );
            case "pdf" -> file(
                    "trip-" + trip.getId() + ".pdf",
                    MediaType.APPLICATION_PDF_VALUE,
                    renderPdf(trip, rows, userNames, scope)
            );
            default -> throw new IllegalArgumentException("Unknown format: " + format);
        };
    }

    private byte[] renderXlsx(TripEntity trip, List<ExpenseEntity> rows,
                              Map<String, String> userNames, String scope) throws IOException {
        try (XSSFWorkbook wb = new XSSFWorkbook();
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            XSSFSheet sheet = wb.createSheet(trip.getName());

            CellStyle header = wb.createCellStyle();
            XSSFFont bold = wb.createFont();
            bold.setBold(true);
            header.setFont(bold);
            header.setFillForegroundColor(IndexedColors.GREY_25_PERCENT.getIndex());
            header.setFillPattern(FillPatternType.SOLID_FOREGROUND);

            int r = 0;
            Row title = sheet.createRow(r++);
            title.createCell(0).setCellValue("PDD Petty Cash — " + trip.getName());
            Row meta = sheet.createRow(r++);
            meta.createCell(0).setCellValue("Scope: " + scope);
            meta.createCell(1).setCellValue("Currency: " + trip.getCurrency());
            meta.createCell(2).setCellValue("Status: " + trip.getStatus().name());

            r++; // blank row
            Row head = sheet.createRow(r++);
            String[] cols = {"Date", "User", "Source", "Category", "Details", "Amount (minor)"};
            for (int i = 0; i < cols.length; i++) {
                head.createCell(i).setCellValue(cols[i]);
                head.getCell(i).setCellStyle(header);
            }

            long totalMinor = 0;
            for (ExpenseEntity e : rows) {
                Row row = sheet.createRow(r++);
                row.createCell(0).setCellValue(DATE.format(e.getOccurredAt().toLocalDate()));
                row.createCell(1).setCellValue(userNames.getOrDefault(e.getUserId(), e.getUserId()));
                row.createCell(2).setCellValue(e.getSourceId());
                row.createCell(3).setCellValue(e.getCategoryCode());
                row.createCell(4).setCellValue(e.getDetails());
                row.createCell(5).setCellValue(e.getAmountMinor());
                totalMinor += e.getAmountMinor();
            }

            Row total = sheet.createRow(r);
            total.createCell(4).setCellValue("TOTAL");
            total.createCell(5).setCellValue(totalMinor);
            total.getCell(4).setCellStyle(header);
            total.getCell(5).setCellStyle(header);

            for (int i = 0; i < cols.length; i++) sheet.autoSizeColumn(i);
            wb.write(out);
            return out.toByteArray();
        }
    }

    private byte[] renderPdf(TripEntity trip, List<ExpenseEntity> rows,
                             Map<String, String> userNames, String scope) {
        try (ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            Document doc = new Document(PageSize.A4);
            PdfWriter.getInstance(doc, out);
            doc.open();

            Font title = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 16);
            Font normal = FontFactory.getFont(FontFactory.HELVETICA, 10);
            doc.add(new Paragraph("PDD Petty Cash — " + trip.getName(), title));
            doc.add(new Paragraph(
                    "Scope: " + scope + "   |   Currency: " + trip.getCurrency()
                            + "   |   Status: " + trip.getStatus().name(),
                    normal));
            doc.add(new Paragraph(" "));

            PdfPTable table = new PdfPTable(6);
            table.setWidthPercentage(100);
            table.setWidths(new float[]{2, 3, 3, 3, 5, 2});
            String[] cols = {"Date", "User", "Source", "Category", "Details", "Amount"};
            for (String c : cols) {
                PdfPCell cell = new PdfPCell(new Phrase(c, FontFactory.getFont(FontFactory.HELVETICA_BOLD, 10)));
                cell.setBackgroundColor(new Color(0xEE, 0xEE, 0xEE));
                table.addCell(cell);
            }

            long totalMinor = 0;
            for (ExpenseEntity e : rows) {
                table.addCell(new Phrase(DATE.format(e.getOccurredAt().toLocalDate()), normal));
                table.addCell(new Phrase(userNames.getOrDefault(e.getUserId(), e.getUserId()), normal));
                table.addCell(new Phrase(e.getSourceId(), normal));
                table.addCell(new Phrase(e.getCategoryCode(), normal));
                table.addCell(new Phrase(e.getDetails(), normal));
                PdfPCell amt = new PdfPCell(new Phrase(Long.toString(e.getAmountMinor()), normal));
                amt.setHorizontalAlignment(Element.ALIGN_RIGHT);
                table.addCell(amt);
                totalMinor += e.getAmountMinor();
            }

            PdfPCell totalLbl = new PdfPCell(new Phrase("TOTAL (minor units)",
                    FontFactory.getFont(FontFactory.HELVETICA_BOLD, 10)));
            totalLbl.setColspan(5);
            totalLbl.setHorizontalAlignment(Element.ALIGN_RIGHT);
            table.addCell(totalLbl);
            PdfPCell totalVal = new PdfPCell(new Phrase(Long.toString(totalMinor),
                    FontFactory.getFont(FontFactory.HELVETICA_BOLD, 10)));
            totalVal.setHorizontalAlignment(Element.ALIGN_RIGHT);
            table.addCell(totalVal);

            doc.add(table);
            doc.close();
            return out.toByteArray();
        } catch (Exception ex) {
            throw new RuntimeException("PDF render failed: " + ex.getMessage(), ex);
        }
    }

    private ResponseEntity<byte[]> file(String name, String contentType, byte[] body) {
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(contentType))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + name + "\"")
                .body(body);
    }
}
