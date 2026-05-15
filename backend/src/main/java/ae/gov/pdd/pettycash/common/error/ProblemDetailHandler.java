package ae.gov.pdd.pettycash.common.error;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.net.URI;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Centralised RFC 7807 mapping (CLAUDE.md §9). Every error response includes
 * {@code type}, {@code title}, {@code status}, {@code detail}, {@code instance},
 * and a stable {@code code} field for client logic.
 */
@RestControllerAdvice
public class ProblemDetailHandler {

    private static final URI BASE_TYPE = URI.create("https://pdd.gov.ae/errors/");

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ProblemDetail> onApi(ApiException ex, HttpServletRequest req) {
        return ResponseEntity
            .status(ex.getStatus())
            .body(build(ex.getStatus(), ex.getCode(), ex.getTitle(), ex.getDetail(), req));
    }

    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<ProblemDetail> onAuth(AuthenticationException ex, HttpServletRequest req) {
        return ResponseEntity
            .status(HttpStatus.UNAUTHORIZED)
            .body(build(
                HttpStatus.UNAUTHORIZED,
                "auth/unauthenticated",
                "Unauthenticated",
                "Authentication is required to access this resource.",
                req
            ));
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ProblemDetail> onAccessDenied(AccessDeniedException ex, HttpServletRequest req) {
        return ResponseEntity
            .status(HttpStatus.FORBIDDEN)
            .body(build(
                HttpStatus.FORBIDDEN,
                "auth/forbidden",
                "Forbidden",
                "Your role does not permit this action.",
                req
            ));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ProblemDetail> onValidation(
        MethodArgumentNotValidException ex,
        HttpServletRequest req
    ) {
        ProblemDetail pd = build(
            HttpStatus.BAD_REQUEST,
            "validation/invalid-request",
            "Validation failed",
            "One or more fields failed validation.",
            req
        );
        List<Map<String, String>> errors = ex.getBindingResult().getFieldErrors().stream()
            .map(fe -> Map.of(
                "field", fe.getField(),
                "message", fe.getDefaultMessage() == null ? "invalid" : fe.getDefaultMessage()
            ))
            .toList();
        pd.setProperty("errors", errors);
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(pd);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ProblemDetail> onUnexpected(Exception ex, HttpServletRequest req) {
        return ResponseEntity
            .status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(build(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "server/internal",
                "Internal server error",
                "An unexpected error occurred.",
                req
            ));
    }

    private static ProblemDetail build(
        HttpStatus status,
        String code,
        String title,
        String detail,
        HttpServletRequest req
    ) {
        ProblemDetail pd = ProblemDetail.forStatus(status);
        pd.setType(BASE_TYPE.resolve(code));
        pd.setTitle(title);
        pd.setDetail(detail);
        pd.setInstance(URI.create(req.getRequestURI()));
        // Stable, machine-parseable code (CLAUDE.md §9).
        Map<String, Object> properties = new LinkedHashMap<>();
        properties.put("code", code);
        properties.forEach(pd::setProperty);
        return pd;
    }
}
