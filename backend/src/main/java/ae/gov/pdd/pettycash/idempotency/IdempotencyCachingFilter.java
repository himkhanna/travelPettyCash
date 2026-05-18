package ae.gov.pdd.pettycash.idempotency;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

/**
 * Captures request body bytes into a request attribute, then exposes a re-readable
 * request so Spring's JSON binding still works. Also wraps the response with a
 * {@link ContentCachingResponseWrapper} so {@link IdempotencyInterceptor} can persist
 * the response payload for later replay.
 *
 * <p>Applied to POSTs only.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class IdempotencyCachingFilter extends OncePerRequestFilter {

    public static final String CACHED_BODY_ATTR = "ae.gov.pdd.pettycash.cachedBody";

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        if (!"POST".equalsIgnoreCase(request.getMethod()) || !isJsonRequest(request)) {
            chain.doFilter(request, response);
            return;
        }
        byte[] body = request.getInputStream().readAllBytes();
        request.setAttribute(CACHED_BODY_ATTR, body);
        HttpServletRequest wrapped = new CachedBodyRequest(request, body);
        ContentCachingResponseWrapper resp = new ContentCachingResponseWrapper(response);
        try {
            chain.doFilter(wrapped, resp);
        } finally {
            resp.copyBodyToResponse();
        }
    }

    private static boolean isJsonRequest(HttpServletRequest request) {
        String ct = request.getContentType();
        return ct != null && ct.toLowerCase().startsWith("application/json");
    }

    /** Re-readable request wrapper backed by a byte buffer. */
    private static final class CachedBodyRequest extends HttpServletRequestWrapper {
        private final byte[] body;

        CachedBodyRequest(HttpServletRequest request, byte[] body) {
            super(request);
            this.body = body;
        }

        @Override
        public ServletInputStream getInputStream() {
            ByteArrayInputStream stream = new ByteArrayInputStream(body);
            return new ServletInputStream() {
                @Override public boolean isFinished() { return stream.available() == 0; }
                @Override public boolean isReady() { return true; }
                @Override public void setReadListener(ReadListener l) {}
                @Override public int read() { return stream.read(); }
            };
        }

        @Override
        public BufferedReader getReader() {
            return new BufferedReader(new InputStreamReader(getInputStream(), StandardCharsets.UTF_8));
        }
    }
}
