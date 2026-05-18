package ae.gov.pdd.pettycash.idempotency;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Optional;
import java.util.UUID;

/**
 * Idempotency-Key persistence service. See CLAUDE.md §9 — 24h contract.
 */
@Service
public class IdempotencyService {

    private final IdempotencyRecordRepository repo;

    public IdempotencyService(IdempotencyRecordRepository repo) {
        this.repo = repo;
    }

    @Transactional(readOnly = true)
    public Optional<IdempotencyRecord> find(String key, UUID actorId) {
        return repo.findById(new IdempotencyRecord.Pk(key, actorId));
    }

    /**
     * Persist a record in its own transaction. Run after the business write commits,
     * so a failed business call leaves no idempotency residue.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public IdempotencyRecord persist(String key, UUID actorId, String requestHash,
                                     String responseBody, int statusCode) {
        IdempotencyRecord rec = new IdempotencyRecord(key, actorId, requestHash, responseBody, statusCode);
        return repo.save(rec);
    }

    public static String hashBody(byte[] body) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(body == null ? new byte[0] : body);
            StringBuilder sb = new StringBuilder(64);
            for (byte b : digest) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }

    public static String canonicalize(String body) {
        if (body == null) return "";
        // Cheap canonicalization: strip whitespace. A full JSON canonicalizer
        // (RFC 8785) is overkill for v1 — clients send the same body bytes.
        return body.replaceAll("\\s+", "");
    }

    public static String hashCanonical(String body) {
        return hashBody(canonicalize(body).getBytes(StandardCharsets.UTF_8));
    }
}
