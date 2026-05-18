package ae.gov.pdd.pettycash.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * JWT config — see CLAUDE.md §12. Secret never lives in YAML in prod.
 * TODO(§16): replace HMAC secret with RSA / HSM key once UAE Pass / PDD SSO is wired.
 */
@ConfigurationProperties(prefix = "pettycash.jwt")
public record JwtProperties(
    String issuer,
    String secret,
    int accessTtlMinutes,
    int refreshTtlDays
) {}
