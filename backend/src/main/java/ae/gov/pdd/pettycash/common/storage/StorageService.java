package ae.gov.pdd.pettycash.common.storage;

import java.io.InputStream;
import java.time.Duration;

/**
 * Backend-side abstraction over the receipt object store (CLAUDE.md §3 —
 * MinIO on-prem in production). Receipts and signed PDF reports go through
 * this interface; bytes never live in the relational DB.
 */
public interface StorageService {

    /**
     * Streams {@code bytes} into the bucket under {@code objectKey}.
     * Returns the object's storage key (always {@code objectKey} in this
     * impl; the return is here so a future hashed-prefix scheme can rewrite
     * the key without changing callers).
     */
    String putObject(
        String objectKey,
        String contentType,
        long contentLength,
        InputStream bytes
    );

    /**
     * Returns a presigned HTTP GET URL the client can use directly. The TTL
     * is short — long enough for the photo to render in the receipt viewer,
     * not long enough to share around.
     */
    String presignedGetUrl(String objectKey, Duration ttl);

    /** Best-effort delete. No-op if the object doesn't exist. */
    void deleteObject(String objectKey);
}
