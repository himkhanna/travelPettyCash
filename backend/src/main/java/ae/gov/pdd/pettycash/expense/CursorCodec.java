package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.common.ApiException;

import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.Base64;
import java.util.UUID;

/**
 * Opaque cursor codec for cursor pagination. See CLAUDE.md §9 — cursor pagination
 * is the canonical list shape; offset pagination is forbidden for expense feeds.
 *
 * <p>Encoding is intentionally trivial: base64({occurredAtIso}|{uuid}). Cursors
 * are server-issued and clients must echo them verbatim — they should not be
 * inspected client-side. If we want to harden against tampering we can HMAC the
 * payload; we don't today because the cursor names rows the caller is already
 * authorized to read.
 */
final class CursorCodec {

    private static final String SEP = "|";

    private CursorCodec() {}

    /** Encode the (occurredAt, id) tie-breaker tuple to an opaque base64 string. */
    static String encode(OffsetDateTime occurredAt, UUID id) {
        String raw = occurredAt.toString() + SEP + id.toString();
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(raw.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * Decode an opaque cursor string back into its components.
     * Throws {@link ApiException#badRequest(String, String)} with code
     * {@code INVALID_CURSOR} on any parse failure.
     */
    static Cursor decode(String cursor) {
        if (cursor == null || cursor.isBlank()) {
            throw ApiException.badRequest("INVALID_CURSOR", "Cursor is blank");
        }
        try {
            byte[] bytes = Base64.getUrlDecoder().decode(cursor);
            String raw = new String(bytes, StandardCharsets.UTF_8);
            int sep = raw.indexOf(SEP);
            if (sep <= 0 || sep == raw.length() - 1) {
                throw ApiException.badRequest("INVALID_CURSOR", "Malformed cursor payload");
            }
            OffsetDateTime occurredAt = OffsetDateTime.parse(raw.substring(0, sep));
            UUID id = UUID.fromString(raw.substring(sep + 1));
            return new Cursor(occurredAt, id);
        } catch (ApiException e) {
            throw e;
        } catch (IllegalArgumentException | DateTimeParseException e) {
            throw ApiException.badRequest("INVALID_CURSOR", "Cursor could not be decoded");
        }
    }

    record Cursor(OffsetDateTime occurredAt, UUID id) {}
}
