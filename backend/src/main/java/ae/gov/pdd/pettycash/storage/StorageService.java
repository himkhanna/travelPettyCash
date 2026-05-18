package ae.gov.pdd.pettycash.storage;

import java.io.InputStream;
import java.net.URL;
import java.time.Duration;

/**
 * Abstraction over S3-compatible object storage (MinIO in dev / on-prem).
 * See CLAUDE.md §3 — receipts and signed PDF reports live in object storage,
 * never as BLOBs in Postgres.
 */
public interface StorageService {

    /** Upload an object. Returns the object key actually written. */
    String putObject(String key, InputStream content, long contentLength, String contentType);

    /** Generate a time-limited presigned GET URL for an object. */
    URL presignGet(String key, Duration ttl);

    /** Idempotent bucket creation — caller may invoke on startup. */
    void ensureBucket();
}
