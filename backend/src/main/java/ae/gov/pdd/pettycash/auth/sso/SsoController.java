package ae.gov.pdd.pettycash.auth.sso;

import ae.gov.pdd.pettycash.auth.dto.LoginResponse;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.view.RedirectView;

import java.io.IOException;

/**
 * HTTP surface for the Smart Dubai (Dubai Gov) OIDC flow.
 *
 * <ul>
 *   <li>{@code GET /api/v1/auth/sso/start} — 302 to the IdP authorize
 *       URL. The browser visits the IdP, signs in, and is redirected
 *       back to {@code /api/v1/auth/sso/callback}.</li>
 *   <li>{@code GET /api/v1/auth/sso/callback} — exchanges the IdP code
 *       for tokens, upserts the user, mints our own JWTs, and 302s the
 *       browser to the Flutter SPA's callback URL with a one-time
 *       exchange code.</li>
 *   <li>{@code POST /api/v1/auth/sso/exchange} — SPA / native client
 *       swaps the one-time code for the JWT pair.</li>
 *   <li>{@code GET /api/v1/auth/sso/logout} — clears the local session
 *       and 302s to the IdP's SAML SLO URL.</li>
 * </ul>
 *
 * See docs/architecture/ADR-001-dda-sso.md for the full flow diagram.
 */
@RestController
@RequestMapping("/api/v1/auth/sso")
public class SsoController {

    private final DubaiGovSsoService sso;

    public SsoController(DubaiGovSsoService sso) {
        this.sso = sso;
    }

    @GetMapping("/start")
    public RedirectView start(
        @RequestParam(name = "audience", defaultValue = "mobileWeb") String audience
    ) {
        DubaiGovSsoService.Audience a = switch (audience) {
            case "portal", "webAdmin" -> DubaiGovSsoService.Audience.PORTAL;
            case "mobileNative", "native" ->
                DubaiGovSsoService.Audience.MOBILE_NATIVE;
            default -> DubaiGovSsoService.Audience.MOBILE_WEB;
        };
        return new RedirectView(sso.startUrl(a));
    }

    @GetMapping("/callback")
    public void callback(
        @RequestParam("code") String code,
        @RequestParam("state") String state,
        HttpServletResponse response
    ) throws IOException {
        // Use sendRedirect rather than RedirectView so we can write
        // arbitrary URLs (including custom-scheme deep links like
        // ae.gov.pdd.pettycash://...) that RedirectView's validator
        // might otherwise refuse.
        response.sendRedirect(sso.completeCallback(code, state));
    }

    @PostMapping("/exchange")
    public LoginResponse exchange(@RequestBody ExchangeRequest body) {
        return sso.exchange(body.code());
    }

    /** Best-effort IdP logout. The OIDC provider doesn't expose
     *  RP-Initiated Logout, so the SAML SLO URL is the documented
     *  path. The mobile/web client should call this from an in-app
     *  browser after clearing local tokens. */
    @GetMapping("/logout-url")
    public LogoutUrlResponse logoutUrl() {
        return new LogoutUrlResponse(sso.samlSloUri());
    }

    public record ExchangeRequest(String code) {}
    public record LogoutUrlResponse(String url) {}
}
