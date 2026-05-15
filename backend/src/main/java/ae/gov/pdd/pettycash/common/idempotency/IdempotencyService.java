package ae.gov.pdd.pettycash.common.idempotency;

import ae.gov.pdd.pettycash.common.error.ApiException;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Supplier;

/**
 * Implements CLAUDE.md §9 Idempotency-Key semantics: a POST replayed with the
 * same key + caller + endpoint inside the 24h window returns the originally
 * cached response instead of re-running the side-effect.
 *
 * <p>Callers thread the key in from a controller method like:
 * <pre>{@code
 * return idempotency.runOrReplay(key, caller.userId(), "/trips/{id}/allocations",
 *     AllocationDto[].class, () -> service.create(...));
 * }</pre>
 *
 * The handler {@code supplier} is only invoked on a cache miss; on a hit
 * the cached body is deserialised back to the expected response type.
 */
@Service
public class IdempotencyService {

    /** TTL per CLAUDE.md §9 — keys are valid for 24 hours. */
    public static final Duration TTL = Duration.ofHours(24);

    private final IdempotencyKeyRepository repo;
    private final ObjectMapper json;
    private final Clock clock;

    @Autowired
    public IdempotencyService(IdempotencyKeyRepository repo, ObjectMapper json) {
        this(repo, json, Clock.systemUTC());
    }

    IdempotencyService(IdempotencyKeyRepository repo, ObjectMapper json, Clock clock) {
        this.repo = repo;
        this.json = json;
        this.clock = clock;
    }

    public static String require(String headerValue) {
        if (headerValue == null || headerValue.isBlank()) {
            throw new ApiException(
                HttpStatus.BAD_REQUEST,
                "validation/missing-idempotency-key",
                "Missing Idempotency-Key",
                "POSTs to this endpoint require an Idempotency-Key header (CLAUDE.md §9)."
            );
        }
        if (headerValue.length() > 128) {
            throw new ApiException(
                HttpStatus.BAD_REQUEST,
                "validation/invalid-idempotency-key",
                "Idempotency-Key too long",
                "Idempotency-Key must be at most 128 characters."
            );
        }
        return headerValue;
    }

    @Transactional
    public <T> T runOrReplay(
        String key,
        UUID userId,
        String endpoint,
        Class<T> responseType,
        Supplier<T> handler
    ) {
        Optional<IdempotencyKey> hit = repo.findByKeyAndUserIdAndEndpoint(key, userId, endpoint);
        if (hit.isPresent()) {
            IdempotencyKey existing = hit.get();
            if (existing.getExpiresAt().isAfter(clock.instant())) {
                return deserialize(existing.getResponseBody(), responseType);
            }
            // Expired row exists — fall through and overwrite via uniqueness
            // violation handled by the save below. Simpler: delete-and-recreate.
            repo.delete(existing);
        }

        T response = handler.get();
        IdempotencyKey row = new IdempotencyKey(
            UUID.randomUUID(),
            key,
            userId,
            endpoint,
            200,
            serialize(response),
            clock.instant().plus(TTL)
        );
        repo.save(row);
        return response;
    }

    private String serialize(Object value) {
        try {
            return json.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Failed to serialize idempotency response", e);
        }
    }

    private <T> T deserialize(String body, Class<T> type) {
        try {
            return json.readValue(body, type);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Corrupt idempotency cache entry", e);
        }
    }
}
