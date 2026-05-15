package ae.gov.pdd.pettycash.auth.dto;

/** Issued by {@code /auth/login} and {@code /auth/refresh}. */
public record AuthTokens(
    String accessToken,
    String refreshToken,
    long   accessExpiresInSeconds,
    long   refreshExpiresInSeconds
) {}
