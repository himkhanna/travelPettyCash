package ae.gov.pdd.pettycash.auth.sso;

import ae.gov.pdd.pettycash.user.UserRole;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.util.HtmlUtils;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * DEV-ONLY fake OIDC Identity Provider standing in for the Smart Dubai
 * (Dubai-Gov) IdP. It exists only so the full SSO flow can be exercised
 * end-to-end while the real demo tenant has not yet whitelisted our
 * redirect URI (ADR-001 "Still to confirm with DDA", item 2).
 *
 * <p>Mounted only when {@code pdd.auth.dubaigov.mock-idp=true} (off by
 * default, never set in staging/prod). {@link MockIdpReconfig} repoints
 * the authorize/token/userinfo URIs here at startup, so
 * {@link DubaiGovSsoService} runs its real, unchanged code path against
 * this fake — the only thing faked is the IdP's HTTP responses.
 *
 * <p>Flow it implements (mirrors a real Authorization-Code provider):
 * <ol>
 *   <li>{@code GET /authorize} — renders a sign-in page (a role picker
 *       standing in for the IdP's credential prompt).</li>
 *   <li>{@code GET /approve} — "authenticates", mints a one-time code,
 *       302s back to our real {@code /callback} with {@code code+state}.</li>
 *   <li>{@code POST /token} — swaps the code for an access token.</li>
 *   <li>{@code GET /userinfo} — returns canned claims (sub/name/email +
 *       the configured role claim) for the chosen role.</li>
 * </ol>
 */
@RestController
@RequestMapping("/api/v1/auth/sso/mock")
@ConditionalOnProperty(prefix = "pdd.auth.dubaigov", name = "mock-idp", havingValue = "true")
public class MockIdpController {

    private static final Logger LOG = LoggerFactory.getLogger(MockIdpController.class);

    private final DubaiGovProperties props;

    // In-memory, single-use, dev only. code -> role, accessToken -> role.
    private final Map<String, UserRole> codes = new ConcurrentHashMap<>();
    private final Map<String, UserRole> tokens = new ConcurrentHashMap<>();

    public MockIdpController(DubaiGovProperties props) {
        this.props = props;
        LOG.warn("=== Dubai-Gov MOCK IdP mounted — any role can sign in, NO real "
            + "authentication. This must never run outside local dev. ===");
    }

    /** Step 1 — the "login page". A real IdP would prompt for credentials
     *  here; we render a role picker instead. */
    @GetMapping(value = "/authorize", produces = MediaType.TEXT_HTML_VALUE)
    public String authorize(
        @RequestParam("redirect_uri") String redirectUri,
        @RequestParam(name = "state", required = false) String state
    ) {
        StringBuilder b = new StringBuilder();
        b.append("<!doctype html><html lang='en'><head><meta charset='utf-8'>")
         .append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
         .append("<title>Mock Dubai-Gov sign-in</title><style>")
         .append("body{font-family:system-ui,Segoe UI,sans-serif;background:#f4f1ea;color:#2a2a2a;"
             + "display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0}")
         .append(".card{background:#fff;padding:32px 40px;border-radius:14px;"
             + "box-shadow:0 10px 40px rgba(0,0,0,.12);max-width:440px;width:90%}")
         .append("h1{font-size:19px;margin:0 0 4px}p.sub{color:#666;font-size:13px;margin:0 0 18px}")
         .append(".warn{background:#fff5e6;border:1px solid #f0c674;padding:9px 12px;border-radius:8px;"
             + "font-size:12px;color:#8a6d3b;margin-bottom:18px;line-height:1.4}")
         .append("a.btn{display:block;padding:13px 16px;margin:9px 0;border-radius:9px;background:#5C4A2F;"
             + "color:#fff;text-decoration:none;font-size:14px;text-align:center;font-weight:500}")
         .append("a.btn:hover{background:#43381f}")
         .append("</style></head><body><div class='card'>")
         .append("<h1>Mock Dubai-Gov sign-in</h1>")
         .append("<p class='sub'>Development stand-in for the Smart Dubai IdP.</p>")
         .append("<div class='warn'>This page is not part of production. It only exists because the "
             + "real demo tenant has not whitelisted our redirect URI yet. Pick a role to sign in as.</div>");
        for (UserRole role : List.of(
            UserRole.SUPER_ADMIN, UserRole.ADMIN, UserRole.LEADER, UserRole.MEMBER)) {
            URI link = UriComponentsBuilder.fromPath("/api/v1/auth/sso/mock/approve")
                .queryParam("role", role.name())
                .queryParam("redirect_uri", redirectUri)
                .queryParam("state", state == null ? "" : state)
                .encode()
                .build()
                .toUri();
            b.append("<a class='btn' href='")
             .append(HtmlUtils.htmlEscape(link.toString()))
             .append("'>Sign in as ")
             .append(HtmlUtils.htmlEscape(label(role)))
             .append("</a>");
        }
        b.append("</div></body></html>");
        return b.toString();
    }

    /** Step 2 — "authenticate" the chosen role, mint a code, redirect
     *  back to the real callback exactly as a real IdP would. */
    @GetMapping("/approve")
    public ResponseEntity<Void> approve(
        @RequestParam("role") UserRole role,
        @RequestParam("redirect_uri") String redirectUri,
        @RequestParam(name = "state", required = false) String state
    ) {
        final String code = "mockcode-" + UUID.randomUUID();
        codes.put(code, role);
        URI dest = UriComponentsBuilder.fromUriString(redirectUri)
            .queryParam("code", code)
            .queryParam("state", state == null ? "" : state)
            .encode()
            .build()
            .toUri();
        return ResponseEntity.status(HttpStatus.FOUND).location(dest).build();
    }

    /** Step 3 — token endpoint. Swaps the single-use code for an access
     *  token. Ignores PKCE / client_secret (it's a fake). */
    @PostMapping(value = "/token", produces = MediaType.APPLICATION_JSON_VALUE)
    public Map<String, Object> token(@RequestParam MultiValueMap<String, String> form) {
        final String code = form.getFirst("code");
        UserRole role = code == null ? null : codes.remove(code);
        if (role == null) {
            role = props.getDefaultRole();
        }
        final String accessToken = "mocktok-" + UUID.randomUUID();
        tokens.put(accessToken, role);
        return Map.of(
            "access_token", accessToken,
            "token_type", "Bearer",
            "expires_in", 3600,
            "scope", props.getScopes(),
            "id_token", "mock.id.token"
        );
    }

    /** Step 4 — userinfo. Returns canned claims for the role, including
     *  the configured role claim so DubaiGovSsoService maps it correctly. */
    @GetMapping(value = "/userinfo", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> userinfo(
        @RequestHeader(name = "Authorization", required = false) String authorization
    ) {
        final String token = authorization == null
            ? null
            : authorization.replaceFirst("(?i)^Bearer\\s+", "").trim();
        final UserRole role = token == null ? null : tokens.get(token);
        if (role == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        final String slug = role.name().toLowerCase();
        Map<String, Object> claims = Map.of(
            "sub", "mock|" + role.name(),
            "name", "Mock " + label(role),
            "preferred_username", "mock." + slug,
            "email", slug + "@mock.dubai.gov.ae",
            props.getRoleClaim(), List.of(groupFor(role))
        );
        return ResponseEntity.ok(claims);
    }

    /** Inverse of the configured role-mapping so the mock stays in sync
     *  with whatever group strings application-local.yml declares. */
    private String groupFor(UserRole role) {
        for (Map.Entry<String, UserRole> e : props.getRoleMapping().entrySet()) {
            if (e.getValue() == role) {
                return e.getKey();
            }
        }
        return "pdd.delegation-expenses." + role.name().toLowerCase().replace('_', '-');
    }

    private static String label(UserRole role) {
        return switch (role) {
            case SUPER_ADMIN -> "Super Admin (DG)";
            case ADMIN -> "Admin";
            case LEADER -> "Team Leader";
            case MEMBER -> "Team Member";
        };
    }
}
