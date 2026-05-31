package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.auth.sso.DubaiGovProperties;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Public probe the mobile + portal bundles call at boot to decide
 * what to render on the login screen.
 *
 * <ul>
 *   <li>{@code sso.dubaigov.enabled} — show / hide the
 *       "Sign in with Dubai Gov" button.</li>
 *   <li>{@code localLogin.enabled} — show / hide the username +
 *       password form. Off in prod once SSO is mandatory.</li>
 * </ul>
 *
 * Permitted by SecurityConfig (already covered by the
 * /api/v1/auth/** allowlist? No — only /login, /refresh, /sso/** are
 * permitted. This endpoint must be added there explicitly.)
 */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthConfigController {

    private final DubaiGovProperties dubaigov;

    public AuthConfigController(DubaiGovProperties dubaigov) {
        this.dubaigov = dubaigov;
    }

    @GetMapping("/config")
    public AuthConfigResponse config() {
        return new AuthConfigResponse(
            // localLogin defaults to enabled until we wire the flag
            // through Slice E. Hardcoded true for now so demo accounts
            // keep working.
            new LocalLoginConfig(true),
            new SsoConfig(
                new DubaiGovSsoConfig(dubaigov.isEnabled())
            )
        );
    }

    public record AuthConfigResponse(
        LocalLoginConfig localLogin,
        SsoConfig sso
    ) {}

    public record LocalLoginConfig(boolean enabled) {}

    public record SsoConfig(DubaiGovSsoConfig dubaigov) {}

    public record DubaiGovSsoConfig(boolean enabled) {}
}
