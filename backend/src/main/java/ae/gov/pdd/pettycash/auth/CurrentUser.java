package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.common.ApiException;
import ae.gov.pdd.pettycash.user.Role;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Helper to read the authenticated user from the SecurityContext.
 * The principal is a {@link Jwt} placed there by Spring Security's resource-server filter.
 */
@Component
public class CurrentUser {

    public UUID id() {
        Jwt jwt = jwt();
        return UUID.fromString(jwt.getSubject());
    }

    public String username() {
        return jwt().getClaim("username");
    }

    public Role role() {
        String role = jwt().getClaim("role");
        return Role.valueOf(role);
    }

    private Jwt jwt() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof Jwt jwt)) {
            throw ApiException.forbidden("UNAUTHENTICATED", "No authenticated principal");
        }
        return jwt;
    }
}
