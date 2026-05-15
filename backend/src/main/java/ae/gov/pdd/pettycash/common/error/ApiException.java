package ae.gov.pdd.pettycash.common.error;

import org.springframework.http.HttpStatus;

/**
 * Domain-level exception that maps cleanly to an RFC 7807 ProblemDetail.
 *
 * <p>{@code code} is the stable, machine-parseable client identifier (e.g.
 * {@code auth/invalid-credentials}). {@code title} is short human text;
 * {@code detail} is the long-form. {@code type} is derived from {@code code}.
 */
public class ApiException extends RuntimeException {
    private final HttpStatus status;
    private final String code;
    private final String title;

    public ApiException(HttpStatus status, String code, String title, String detail) {
        super(detail);
        this.status = status;
        this.code = code;
        this.title = title;
    }

    public HttpStatus getStatus() { return status; }
    public String getCode() { return code; }
    public String getTitle() { return title; }
    public String getDetail() { return getMessage(); }
}
