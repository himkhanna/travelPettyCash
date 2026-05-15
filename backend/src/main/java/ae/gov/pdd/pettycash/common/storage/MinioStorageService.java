package ae.gov.pdd.pettycash.common.storage;

import io.minio.BucketExistsArgs;
import io.minio.GetPresignedObjectUrlArgs;
import io.minio.MakeBucketArgs;
import io.minio.MinioClient;
import io.minio.PutObjectArgs;
import io.minio.RemoveObjectArgs;
import io.minio.errors.ErrorResponseException;
import io.minio.http.Method;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.InputStream;
import java.time.Duration;
import java.util.concurrent.TimeUnit;

/**
 * MinIO-backed {@link StorageService}. The bucket is created on first boot
 * if missing (in production the bucket is provisioned by the {@code minio_init}
 * compose job, but doing it here too keeps tests + bare-metal restarts simple).
 */
@Service
public class MinioStorageService implements StorageService {

    private static final Logger log = LoggerFactory.getLogger(MinioStorageService.class);

    private final String endpoint;
    private final String accessKey;
    private final String secretKey;
    private final String bucket;
    private MinioClient client;

    public MinioStorageService(
        @Value("${pdd.storage.endpoint}") String endpoint,
        @Value("${pdd.storage.access-key}") String accessKey,
        @Value("${pdd.storage.secret-key}") String secretKey,
        @Value("${pdd.storage.bucket}") String bucket
    ) {
        this.endpoint = endpoint;
        this.accessKey = accessKey;
        this.secretKey = secretKey;
        this.bucket = bucket;
    }

    @PostConstruct
    void init() {
        this.client = MinioClient.builder()
            .endpoint(endpoint)
            .credentials(accessKey, secretKey)
            .build();
        // Best-effort bucket bootstrap. The compose `minio_init` job and the
        // production provisioning script create the bucket already; if this
        // side-call fails (MinIO unreachable on early dev start, or in tests
        // that don't exercise receipts), log a warning and let the bean come
        // up. The first real upload will surface a clear error otherwise.
        try {
            boolean exists = client.bucketExists(
                BucketExistsArgs.builder().bucket(bucket).build()
            );
            if (!exists) {
                client.makeBucket(MakeBucketArgs.builder().bucket(bucket).build());
                log.info("Created MinIO bucket '{}'", bucket);
            }
        } catch (Exception e) {
            log.warn(
                "Could not verify MinIO bucket '{}' at {} on startup ({}). "
                    + "Receipt uploads will fail until the bucket is reachable.",
                bucket, endpoint, e.getMessage()
            );
        }
    }

    @Override
    public String putObject(
        String objectKey,
        String contentType,
        long contentLength,
        InputStream bytes
    ) {
        try {
            client.putObject(PutObjectArgs.builder()
                .bucket(bucket)
                .object(objectKey)
                .contentType(contentType)
                .stream(bytes, contentLength, -1)
                .build());
        } catch (Exception e) {
            throw new IllegalStateException("Failed to upload " + objectKey, e);
        }
        return objectKey;
    }

    @Override
    public String presignedGetUrl(String objectKey, Duration ttl) {
        try {
            return client.getPresignedObjectUrl(GetPresignedObjectUrlArgs.builder()
                .method(Method.GET)
                .bucket(bucket)
                .object(objectKey)
                .expiry((int) ttl.getSeconds(), TimeUnit.SECONDS)
                .build());
        } catch (Exception e) {
            throw new IllegalStateException("Failed to presign " + objectKey, e);
        }
    }

    @Override
    public void deleteObject(String objectKey) {
        try {
            client.removeObject(RemoveObjectArgs.builder()
                .bucket(bucket).object(objectKey).build());
        } catch (ErrorResponseException e) {
            // NoSuchKey → ignore.
            if (!"NoSuchKey".equals(e.errorResponse().code())) {
                throw new IllegalStateException("Failed to delete " + objectKey, e);
            }
        } catch (Exception e) {
            throw new IllegalStateException("Failed to delete " + objectKey, e);
        }
    }
}
