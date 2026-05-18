package ae.gov.pdd.pettycash.storage;

import ae.gov.pdd.pettycash.config.StorageProperties;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.BucketAlreadyOwnedByYouException;
import software.amazon.awssdk.services.s3.model.CreateBucketRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadBucketRequest;
import software.amazon.awssdk.services.s3.model.NoSuchBucketException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;

import java.io.InputStream;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URL;
import java.time.Duration;

/**
 * MinIO / S3-compatible storage service using AWS SDK v2.
 * See CLAUDE.md §3 — file storage is MinIO on-prem at Moro Hub.
 *
 * <p>Path-style addressing is required for MinIO.
 */
@Service
public class MinioStorageService implements StorageService {

    private static final Logger log = LoggerFactory.getLogger(MinioStorageService.class);

    private final StorageProperties props;
    private final S3Client s3;
    private final S3Presigner presigner;

    public MinioStorageService(StorageProperties props) {
        this.props = props;
        URI endpoint = parseEndpoint(props.endpoint());
        AwsBasicCredentials creds = AwsBasicCredentials.create(props.accessKey(), props.secretKey());
        S3Configuration s3Config = S3Configuration.builder()
            .pathStyleAccessEnabled(true)
            .build();
        Region region = Region.of(props.region() == null ? "us-east-1" : props.region());
        this.s3 = S3Client.builder()
            .endpointOverride(endpoint)
            .credentialsProvider(StaticCredentialsProvider.create(creds))
            .region(region)
            .serviceConfiguration(s3Config)
            .build();
        this.presigner = S3Presigner.builder()
            .endpointOverride(endpoint)
            .credentialsProvider(StaticCredentialsProvider.create(creds))
            .region(region)
            .serviceConfiguration(s3Config)
            .build();
    }

    private static URI parseEndpoint(String endpoint) {
        try {
            return new URI(endpoint);
        } catch (URISyntaxException e) {
            throw new IllegalArgumentException("Invalid storage endpoint: " + endpoint, e);
        }
    }

    @PostConstruct
    @Override
    public void ensureBucket() {
        String bucket = props.bucket();
        try {
            s3.headBucket(HeadBucketRequest.builder().bucket(bucket).build());
            log.info("Storage bucket '{}' already present", bucket);
        } catch (NoSuchBucketException nsb) {
            createBucketQuietly(bucket);
        } catch (Exception e) {
            // headBucket can throw S3Exception(404) when the bucket is absent — attempt create.
            log.info("Storage bucket '{}' not reachable via headBucket ({}); attempting create",
                bucket, e.getClass().getSimpleName());
            createBucketQuietly(bucket);
        }
    }

    private void createBucketQuietly(String bucket) {
        try {
            s3.createBucket(CreateBucketRequest.builder().bucket(bucket).build());
            log.info("Created storage bucket '{}'", bucket);
        } catch (BucketAlreadyOwnedByYouException ignored) {
            // Concurrent create or pre-existing — fine.
        } catch (Exception e) {
            log.warn("Could not ensure storage bucket '{}': {}", bucket, e.getMessage());
        }
    }

    @Override
    public String putObject(String key, InputStream content, long contentLength, String contentType) {
        PutObjectRequest req = PutObjectRequest.builder()
            .bucket(props.bucket())
            .key(key)
            .contentType(contentType)
            .contentLength(contentLength)
            .build();
        s3.putObject(req, RequestBody.fromInputStream(content, contentLength));
        return key;
    }

    @Override
    public URL presignGet(String key, Duration ttl) {
        GetObjectRequest get = GetObjectRequest.builder()
            .bucket(props.bucket())
            .key(key)
            .build();
        GetObjectPresignRequest presign = GetObjectPresignRequest.builder()
            .signatureDuration(ttl)
            .getObjectRequest(get)
            .build();
        return presigner.presignGetObject(presign).url();
    }
}
