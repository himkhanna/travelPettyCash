package ae.gov.pdd.pettycash.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * OCR feature configuration. See CLAUDE.md §15 and ADR-005.
 *
 * <p>v1 ships with provider = MOCK (deterministic canned responses).
 * Production toggles via {@code pettycash.ocr.enabled=false} disable the
 * endpoint until real Tesseract is wired.
 */
@ConfigurationProperties(prefix = "pettycash.ocr")
public record OcrProperties(
    Boolean enabled,
    String provider
) {
    public OcrProperties {
        if (enabled == null) enabled = Boolean.TRUE;
        if (provider == null) provider = "MOCK";
    }
}
