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
 * HTTP surface for the UAE Pass OIDC flow. Mirrors {@link SsoController}
 * (Dubai-Gov). See docs/architecture/ADR-002-uaepass-sso.md.
 *
 * <ul>
 *   <li>{@code GET /api/v1/auth/sso/uaepass/start} — 302 to the UAE Pass
 *       authorize URL.</li>
 *   <li>{@code GET /api/v1/auth/sso/uaepass/callback} — exchanges the
 *       code, links the identity to a PDD account, mints our JWTs, and
 *       302s to the SPA with a one-time exchange code.</li>
 *   <li>{@code POST /api/v1/auth/sso/uaepass/exchange} — swap the
 *       one-time code for the JWT pair.</li>
 *   <li>{@code GET /api/v1/auth/sso/uaepass/logout-url} — RP-initiated
 *       logout URL.</li>
 * </ul>
 */
@RestController
@RequestMapping("/api/v1/auth/sso/uaepass")
public class UaePassController {

    private final UaePassSsoService sso;

    public UaePassController(UaePassSsoService sso) {
        this.sso = sso;
    }

    @GetMapping("/start")
    public RedirectView start(
        @RequestParam(name = "audience", defaultValue = "mobileWeb") String audience
    ) {
        UaePassSsoService.Audience a = switch (audience) {
            case "portal", "webAdmin" -> UaePassSsoService.Audience.PORTAL;
            default -> UaePassSsoService.Audience.MOBILE_WEB;
        };
        return new RedirectView(sso.startUrl(a));
    }

    @GetMapping("/callback")
    public void callback(
        @RequestParam("code") String code,
        @RequestParam("state") String state,
        HttpServletResponse response
    ) throws IOException {
        response.sendRedirect(sso.completeCallback(code, state));
    }

    @PostMapping("/exchange")
    public LoginResponse exchange(@RequestBody ExchangeRequest body) {
        return sso.exchange(body.code());
    }

    @GetMapping("/logout-url")
    public LogoutUrlResponse logoutUrl() {
        return new LogoutUrlResponse(sso.logoutUri());
    }

    public record ExchangeRequest(String code) {}
    public record LogoutUrlResponse(String url) {}
}
