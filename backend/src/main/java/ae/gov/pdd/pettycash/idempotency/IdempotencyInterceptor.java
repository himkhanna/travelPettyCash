package ae.gov.pdd.pettycash.idempotency;

import ae.gov.pdd.pettycash.common.ApiException;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.util.ContentCachingResponseWrapper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.UUID;

/**
 * Enforces Idempotency-Key on handlers annotated with {@link Idempotent}.
 * See CLAUDE.md §9.
 *
 * <ul>
 *   <li>Missing header → 400 {@code IDEMPOTENCY_KEY_REQUIRED}</li>
 *   <li>Replay with matching hash → 200/201 with stored body and original status</li>
 *   <li>Same key, different body → 409 {@code IDEMPOTENCY_KEY_CONFLICT}</li>
 *   <li>Fresh key → executes, persists on 2xx in {@code afterCompletion}</li>
 * </ul>
 */
@Component
public class IdempotencyInterceptor implements HandlerInterceptor {

    private static final Logger log = LoggerFactory.getLogger(IdempotencyInterceptor.class);
    public static final String HEADER = "Idempotency-Key";
    private static final String ATTR_KEY  = "ae.gov.pdd.pettycash.idempotencyKey";
    private static final String ATTR_HASH = "ae.gov.pdd.pettycash.idempotencyHash";
    private static final String ATTR_ACTOR = "ae.gov.pdd.pettycash.idempotencyActor";

    private final IdempotencyService service;
    private final ObjectMapper mapper;

    public IdempotencyInterceptor(IdempotencyService service, ObjectMapper mapper) {
        this.service = service;
        this.mapper = mapper;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
            throws Exception {
        if (!(handler instanceof HandlerMethod hm)) return true;
        if (hm.getMethodAnnotation(Idempotent.class) == null) return true;

        String key = request.getHeader(HEADER);
        if (key == null || key.isBlank()) {
            throw ApiException.badRequest("IDEMPOTENCY_KEY_REQUIRED",
                "Header '" + HEADER + "' is required on this endpoint");
        }
        if (key.length() > 80) {
            throw ApiException.badRequest("IDEMPOTENCY_KEY_REQUIRED",
                "Header '" + HEADER + "' exceeds 80 characters");
        }
        UUID actorId = currentActorId();
        if (actorId == null) {
            // No principal — auth filter should already have rejected; let the call proceed.
            return true;
        }
        byte[] body = (byte[]) request.getAttribute(IdempotencyCachingFilter.CACHED_BODY_ATTR);
        String bodyStr = body == null ? "" : new String(body, StandardCharsets.UTF_8);
        String hash = IdempotencyService.hashCanonical(bodyStr);

        Optional<IdempotencyRecord> existing = service.find(key, actorId);
        if (existing.isPresent()) {
            IdempotencyRecord rec = existing.get();
            if (!rec.getRequestHash().equals(hash)) {
                throw new ApiException(org.springframework.http.HttpStatus.CONFLICT,
                    "IDEMPOTENCY_KEY_CONFLICT",
                    "Idempotency-Key reused with a different request body");
            }
            // Replay the stored response.
            response.setStatus(rec.getStatusCode());
            response.setContentType("application/json");
            byte[] respBytes = rec.getResponseBody() == null
                ? new byte[0]
                : rec.getResponseBody().getBytes(StandardCharsets.UTF_8);
            response.setContentLength(respBytes.length);
            response.getOutputStream().write(respBytes);
            response.getOutputStream().flush();
            log.debug("Idempotency replay for key={} actor={} status={}", key, actorId, rec.getStatusCode());
            return false;
        }

        request.setAttribute(ATTR_KEY, key);
        request.setAttribute(ATTR_HASH, hash);
        request.setAttribute(ATTR_ACTOR, actorId);
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response,
                                Object handler, Exception ex) throws IOException {
        if (ex != null) return;
        if (!(handler instanceof HandlerMethod hm)) return;
        if (hm.getMethodAnnotation(Idempotent.class) == null) return;

        String key = (String) request.getAttribute(ATTR_KEY);
        if (key == null) return;
        int status = response.getStatus();
        if (status < 200 || status >= 300) return;

        UUID actor = (UUID) request.getAttribute(ATTR_ACTOR);
        String hash = (String) request.getAttribute(ATTR_HASH);

        String responseBody = "";
        if (response instanceof ContentCachingResponseWrapper wrapper) {
            byte[] bytes = wrapper.getContentAsByteArray();
            if (bytes.length > 0) {
                responseBody = new String(bytes, StandardCharsets.UTF_8);
            }
        }

        // Validate it's actually JSON (it should be for our controllers).
        try {
            if (!responseBody.isBlank()) mapper.readTree(responseBody);
        } catch (Exception parseErr) {
            log.warn("Idempotent response not valid JSON; skipping persist (key={})", key);
            return;
        }

        try {
            service.persist(key, actor, hash, responseBody, status);
        } catch (Exception persistErr) {
            // Don't fail the request because we couldn't persist replay state.
            log.warn("Failed to persist idempotency record for key={}: {}", key, persistErr.getMessage());
        }
    }

    private UUID currentActorId() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof Jwt jwt)) return null;
        try {
            return UUID.fromString(jwt.getSubject());
        } catch (IllegalArgumentException e) {
            return null;
        }
    }
}
