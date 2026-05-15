package ae.gov.pdd.pettycash.auth;

import io.jsonwebtoken.JwtException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.lang.NonNull;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * Reads the {@code Authorization: Bearer …} header on every request, verifies
 * the JWT, and populates the {@link org.springframework.security.core.context.SecurityContext}
 * with an {@link AuthenticatedUser} principal.
 *
 * <p>Invalid/expired tokens are silently ignored; the downstream
 * authorization layer will then 401 the request. We do not surface JWT
 * parse errors here because that leaks information about the token shape.
 */
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtService jwtService;

    public JwtAuthenticationFilter(JwtService jwtService) {
        this.jwtService = jwtService;
    }

    @Override
    protected void doFilterInternal(
        @NonNull HttpServletRequest request,
        @NonNull HttpServletResponse response,
        @NonNull FilterChain chain
    ) throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith(BEARER_PREFIX)) {
            String token = header.substring(BEARER_PREFIX.length()).trim();
            try {
                JwtService.Parsed parsed = jwtService.parse(token);
                AuthenticatedUser principal = new AuthenticatedUser(
                    parsed.userId(),
                    parsed.username(),
                    parsed.role()
                );
                UsernamePasswordAuthenticationToken authn = new UsernamePasswordAuthenticationToken(
                    principal,
                    token,
                    List.of(new SimpleGrantedAuthority(parsed.role().authority()))
                );
                authn.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                SecurityContextHolder.getContext().setAuthentication(authn);
            } catch (JwtException ignored) {
                // Drop the token. The endpoint's auth requirement will 401.
            }
        }
        chain.doFilter(request, response);
    }
}
