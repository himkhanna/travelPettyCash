package ae.gov.pdd.pettycash.audit;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

/**
 * Append-only audit recorder with SHA-256 hash chain. See CLAUDE.md §5, §10.
 * Wired in as proof-of-concept on expense create and allocation create.
 */
@Service
public class AuditService {

    private static final String GENESIS = "0".repeat(64);

    private final AuditLogRepository repo;
    private final ObjectMapper mapper;

    public AuditService(AuditLogRepository repo, ObjectMapper mapper) {
        this.repo = repo;
        this.mapper = mapper;
    }

    /**
     * Append an event. Runs in its own transaction so failures don't roll back caller work,
     * but in practice we want it inside the same TX — keep REQUIRED here.
     */
    @Transactional(propagation = Propagation.REQUIRED)
    public AuditLog recordEvent(String entityType, String entityId, UUID actorId,
                                String action, Map<String, Object> before, Map<String, Object> after) {
        AuditLog entry = new AuditLog();
        entry.setId(UUID.randomUUID());
        entry.setEntityType(entityType);
        entry.setEntityId(entityId);
        entry.setActorId(actorId);
        entry.setAction(action);
        entry.setBefore(before);
        entry.setAfter(after);
        entry.setAt(OffsetDateTime.now());

        String prevHash = repo.findLatest().map(AuditLog::getHashSelf).orElse(GENESIS);
        entry.setHashPrev(prevHash);
        entry.setHashSelf(computeHash(prevHash, entry));

        return repo.save(entry);
    }

    private String computeHash(String prevHash, AuditLog entry) {
        try {
            String canonical = mapper.writeValueAsString(Map.of(
                "id", entry.getId().toString(),
                "entityType", entry.getEntityType(),
                "entityId", entry.getEntityId(),
                "actorId", entry.getActorId() == null ? "" : entry.getActorId().toString(),
                "action", entry.getAction(),
                "before", entry.getBefore() == null ? Map.of() : entry.getBefore(),
                "after", entry.getAfter() == null ? Map.of() : entry.getAfter(),
                "at", entry.getAt().toString()
            ));
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            md.update(prevHash.getBytes(StandardCharsets.UTF_8));
            byte[] digest = md.digest(canonical.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(64);
            for (byte b : digest) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (NoSuchAlgorithmException | JsonProcessingException e) {
            throw new IllegalStateException("Failed to compute audit hash", e);
        }
    }
}
