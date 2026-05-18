package ae.gov.pdd.pettycash.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * MinIO / S3-compatible storage config. See CLAUDE.md §3 (file storage).
 */
@ConfigurationProperties(prefix = "pettycash.storage")
public record StorageProperties(
    String endpoint,
    String accessKey,
    String secretKey,
    String bucket,
    String region
) {}
