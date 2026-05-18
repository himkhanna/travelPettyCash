package ae.gov.pdd.pettycash.storage;

import ae.gov.pdd.pettycash.config.StorageProperties;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.MinIOContainer;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration test for {@link MinioStorageService} against a real MinIO container.
 * Skipped automatically when Docker is unavailable.
 */
@Testcontainers
class MinioStorageServiceTest {

    private static final DockerImageName MINIO_IMAGE =
        DockerImageName.parse("minio/minio:RELEASE.2024-08-17T01-24-54Z");

    private static MinIOContainer minio;
    private static MinioStorageService service;

    @BeforeAll
    static void start() {
        minio = new MinIOContainer(MINIO_IMAGE)
            .withUserName("testkey")
            .withPassword("testsecret");
        minio.start();
        StorageProperties props = new StorageProperties(
            minio.getS3URL(),
            "testkey",
            "testsecret",
            "pettycash-test",
            "us-east-1"
        );
        service = new MinioStorageService(props);
        service.ensureBucket();
    }

    @AfterAll
    static void stop() {
        if (minio != null) minio.stop();
    }

    @Test
    void uploadsAndRetrievesViaPresignedUrl() throws Exception {
        byte[] payload = "fake-jpeg-bytes".getBytes();
        String key = "receipts/trip-x/exp-y/test.jpg";
        try (InputStream in = new ByteArrayInputStream(payload)) {
            service.putObject(key, in, payload.length, "image/jpeg");
        }

        URL url = service.presignGet(key, Duration.ofMinutes(5));
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        int status = conn.getResponseCode();
        byte[] got = conn.getInputStream().readAllBytes();
        conn.disconnect();

        assertThat(status).isEqualTo(200);
        assertThat(got).isEqualTo(payload);
    }

    @Test
    void ensureBucketIsIdempotent() {
        // Calling twice should not throw — bucket already owned by us.
        service.ensureBucket();
        service.ensureBucket();
    }
}
