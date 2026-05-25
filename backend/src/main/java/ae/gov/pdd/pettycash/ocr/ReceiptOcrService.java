package ae.gov.pdd.pettycash.ocr;

import jakarta.annotation.PostConstruct;
import net.sourceforge.tess4j.ITesseract;
import net.sourceforge.tess4j.Tesseract;
import net.sourceforge.tess4j.TesseractException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Wraps tess4j to extract a few useful fields from a receipt image.
 *
 * The native libtesseract binary must be installed on the host and the
 * tessdata directory must contain at least {@code eng.traineddata}
 * (and ideally {@code ara.traineddata}). If either is missing the service
 * stays usable — {@link #ocr(byte[])} returns an {@link OcrResult} with
 * {@code engineAvailable=false} and the caller (mobile) shows a "not
 * configured" toast rather than blocking expense submission. See
 * backend/README.md for install steps.
 */
@Service
public class ReceiptOcrService {

    private static final Logger LOG = LoggerFactory.getLogger(ReceiptOcrService.class);

    // Captures e.g. "1,234.56", "1234.56", "12,99" (EU comma decimal).
    // Anchored to a word boundary so "abc123" doesn't match the trailing
    // digits, and requires at least one decimal-separated group so we
    // don't pick up phone numbers or invoice IDs.
    private static final Pattern AMOUNT =
        Pattern.compile("(?<![\\d.,])(\\d{1,3}(?:[, ]\\d{3})*[.,]\\d{2,3}|\\d+[.,]\\d{2,3})(?![\\d.,])");

    // All formats are slash-form — the date text from the regex is
    // normalized to slashes before parsing, so we only need one separator.
    // ISO (uuuu-MM-dd) is normalized to uuuu/MM/dd and matched here too.
    private static final List<DateTimeFormatter> DATE_FORMATS = List.of(
        DateTimeFormatter.ofPattern("d/M/uuuu"),
        DateTimeFormatter.ofPattern("dd/MM/uuuu"),
        DateTimeFormatter.ofPattern("uuuu/MM/dd")
    );

    // 2- and 4-digit year forms. Captures dd/mm/yy too — parser tries both
    // expansions (20xx then 19xx).
    private static final Pattern DATE =
        Pattern.compile("\\b(\\d{1,2}[/.\\-]\\d{1,2}[/.\\-]\\d{2,4}|\\d{4}-\\d{2}-\\d{2})\\b");

    private final String tessdataPath;
    private final String languages;
    private final String installDir;

    private volatile ITesseract engine;
    private volatile boolean available;

    public ReceiptOcrService(
        @Value("${pdd.ocr.tessdata-path:}") String tessdataPath,
        @Value("${pdd.ocr.languages:eng}") String languages,
        @Value("${pdd.ocr.install-dir:}") String installDir
    ) {
        this.tessdataPath = tessdataPath;
        this.languages = languages;
        this.installDir = installDir;
    }

    @PostConstruct
    void init() {
        // Probe Tesseract once at startup. Configuration mistakes (missing
        // native lib, missing traineddata) surface in the boot logs rather
        // than the first user request.
        try {
            // JNA loads libtesseract*.dll from System PATH + jna.library.path.
            // On Windows the typical install (C:\Program Files\Tesseract-OCR)
            // is NOT on PATH, so we prepend the configured install-dir to
            // jna.library.path here. Also derive tessdata-path from it when
            // not set explicitly — the install always ships a tessdata/
            // subdir next to the DLLs.
            String effectiveTessdata = tessdataPath;
            if (installDir != null && !installDir.isBlank()) {
                String existing =
                    System.getProperty("jna.library.path", "");
                String sep = existing.isEmpty() ? "" : ";";
                System.setProperty(
                    "jna.library.path", installDir + sep + existing);
                if (effectiveTessdata == null || effectiveTessdata.isBlank()) {
                    effectiveTessdata = installDir.replaceAll("[\\\\/]+$", "")
                        + "/tessdata";
                }
            }
            Tesseract t = new Tesseract();
            if (effectiveTessdata != null && !effectiveTessdata.isBlank()) {
                t.setDatapath(effectiveTessdata);
            }
            t.setLanguage(languages);
            // Tiny synthetic image — 1x1 transparent PNG bytes. We're not
            // checking the output, just whether the call throws.
            BufferedImage probe = new BufferedImage(8, 8, BufferedImage.TYPE_INT_RGB);
            t.doOCR(probe);
            this.engine = t;
            this.available = true;
            LOG.info("Receipt OCR engine initialized (langs='{}', tessdata='{}').",
                languages,
                (effectiveTessdata == null || effectiveTessdata.isBlank())
                    ? "<default>" : effectiveTessdata);
        } catch (UnsatisfiedLinkError | NoClassDefFoundError e) {
            this.available = false;
            LOG.warn("Receipt OCR disabled: native libtesseract not loadable ({}). "
                + "Install Tesseract OCR on the host and restart to enable.",
                e.getMessage());
        } catch (TesseractException e) {
            this.available = false;
            LOG.warn("Receipt OCR disabled: Tesseract probe failed ({}). "
                + "Check tessdata-path and that the requested language data files exist.",
                e.getMessage());
        } catch (Exception e) {
            this.available = false;
            LOG.warn("Receipt OCR disabled: unexpected init failure", e);
        }
    }

    public OcrResult ocr(byte[] imageBytes) {
        if (!available || engine == null) {
            return OcrResult.unavailable();
        }
        BufferedImage img;
        try {
            img = ImageIO.read(new ByteArrayInputStream(imageBytes));
        } catch (IOException e) {
            LOG.debug("ocr: ImageIO.read failed", e);
            return OcrResult.empty("Could not decode image.");
        }
        if (img == null) {
            return OcrResult.empty("Unsupported image format.");
        }
        String text;
        try {
            text = engine.doOCR(img);
        } catch (TesseractException e) {
            LOG.warn("ocr: doOCR failed", e);
            return OcrResult.empty("OCR engine failed: " + e.getMessage());
        }
        return extract(text);
    }

    OcrResult extract(String rawText) {
        if (rawText == null || rawText.isBlank()) {
            return OcrResult.empty("No text detected.");
        }
        String[] lines = rawText.split("\\R");

        // Vendor: first non-empty line at the top that has at least one
        // letter — receipts usually start with the merchant name. Skip
        // numeric-only lines (machine IDs, register numbers).
        String vendor = null;
        for (String line : lines) {
            String trimmed = line.trim();
            if (trimmed.length() >= 3 && trimmed.matches(".*[A-Za-z\\p{IsArabic}].*")) {
                vendor = trimmed;
                break;
            }
        }

        // Amount: largest amount-shaped match anywhere in the text. Receipts
        // typically print subtotal/tax/total in ascending order so the
        // largest wins is a robust heuristic without parsing labels.
        Long bestMinor = null;
        Matcher am = AMOUNT.matcher(rawText);
        while (am.find()) {
            String raw = am.group(1);
            Long minor = toMinor(raw);
            if (minor != null && (bestMinor == null || minor > bestMinor)) {
                bestMinor = minor;
            }
        }

        // Date: first match, parsed by the formatters in order. Two-digit
        // years are expanded to 20xx/19xx before parsing. Reject anything
        // outside 2000-2099 so an OCR misread like "12/05/0231" doesn't
        // become an absurd prefill.
        LocalDate date = null;
        Matcher dm = DATE.matcher(rawText);
        while (dm.find() && date == null) {
            String normalized =
                dm.group(1).replace('.', '/').replace('-', '/');
            String expanded = expandTwoDigitYear(normalized);
            for (DateTimeFormatter f : DATE_FORMATS) {
                try {
                    LocalDate parsed = LocalDate.parse(expanded, f);
                    if (parsed.getYear() >= 2000 && parsed.getYear() <= 2099) {
                        date = parsed;
                        break;
                    }
                } catch (DateTimeParseException ignore) {
                    // try next format
                }
            }
        }

        return new OcrResult(
            true,
            rawText.trim(),
            vendor,
            bestMinor,
            date,
            null
        );
    }

    private static String expandTwoDigitYear(String slashed) {
        String[] parts = slashed.split("/");
        if (parts.length != 3) return slashed;
        String y = parts[2];
        if (y.length() == 2) {
            int yi = Integer.parseInt(y);
            y = (yi <= 69 ? "20" : "19") + (yi < 10 ? "0" + yi : String.valueOf(yi));
            return parts[0] + "/" + parts[1] + "/" + y;
        }
        return slashed;
    }

    /**
     * Convert "1,234.56" / "1.234,56" / "12.50" to minor units (12500 / 1234,
     * etc.). The decimal separator is always the LAST `.` or `,` — everything
     * else is a thousands separator that we strip.
     */
    static Long toMinor(String raw) {
        if (raw == null) return null;
        String s = raw.replace(" ", "");
        int lastDot = s.lastIndexOf('.');
        int lastComma = s.lastIndexOf(',');
        int decIdx = Math.max(lastDot, lastComma);
        if (decIdx < 0) {
            try { return Long.parseLong(s) * 100; }
            catch (NumberFormatException e) { return null; }
        }
        String intPart = s.substring(0, decIdx).replaceAll("[.,]", "");
        String fracPart = s.substring(decIdx + 1);
        if (fracPart.length() > 3) fracPart = fracPart.substring(0, 3);
        // pad to exactly 2
        if (fracPart.length() == 1) fracPart += "0";
        if (fracPart.length() == 3) fracPart = fracPart.substring(0, 2);
        try {
            long major = intPart.isEmpty() ? 0 : Long.parseLong(intPart);
            long frac = Long.parseLong(fracPart);
            return major * 100 + frac;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    public boolean isAvailable() { return available; }
}
