package ae.gov.pdd.pettycash.auth.sso;

import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
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
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
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
 * <p>The sign-in page lists the <em>existing local accounts</em> (the
 * seeded demo personas, which have no {@code external_id} yet). Picking
 * one makes the mock emit that user's real email; the service's
 * email-link path then federates the existing account instead of
 * minting a brand-new empty user — so you sign in as the real Khalid /
 * Fatima / … with all their data and their actual role.
 */
@RestController
@RequestMapping("/api/v1/auth/sso/mock")
@ConditionalOnProperty(prefix = "pdd.auth.dubaigov", name = "mock-idp", havingValue = "true")
public class MockIdpController {

    private static final Logger LOG = LoggerFactory.getLogger(MockIdpController.class);

    private final DubaiGovProperties props;
    private final UserRepository users;

    // In-memory, single-use, dev only. code -> userId, accessToken -> userId.
    private final Map<String, UUID> codes = new ConcurrentHashMap<>();
    private final Map<String, UUID> tokens = new ConcurrentHashMap<>();

    public MockIdpController(DubaiGovProperties props, UserRepository users) {
        this.props = props;
        this.users = users;
        LOG.warn("=== Dubai-Gov MOCK IdP mounted — any listed user can sign in, "
            + "NO real authentication. This must never run outside local dev. ===");
    }

    /** Step 1 — the "login page". A real IdP would prompt for credentials;
     *  we list the existing local accounts and let you pick one. */
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
             + "box-shadow:0 10px 40px rgba(0,0,0,.12);max-width:460px;width:90%}")
         .append("h1{font-size:19px;margin:0 0 4px}p.sub{color:#666;font-size:13px;margin:0 0 18px}")
         .append(".warn{background:#fff5e6;border:1px solid #f0c674;padding:9px 12px;border-radius:8px;"
             + "font-size:12px;color:#8a6d3b;margin-bottom:18px;line-height:1.4}")
         .append("a.btn{display:flex;justify-content:space-between;align-items:center;padding:13px 16px;"
             + "margin:9px 0;border-radius:9px;background:#5C4A2F;color:#fff;text-decoration:none;"
             + "font-size:14px;font-weight:500}")
         .append("a.btn:hover{background:#43381f}")
         .append("a.btn .role{font-size:11px;opacity:.8;font-weight:400;text-transform:uppercase;"
             + "letter-spacing:.04em}")
         .append("</style></head><body><div class='card'>")
         .append("<h1>Mock Dubai-Gov sign-in</h1>")
         .append("<p class='sub'>Development stand-in for the Smart Dubai IdP.</p>")
         .append("<div class='warn'>This page is not part of production. It exists only because the "
             + "real demo tenant has not whitelisted our redirect URI yet. Pick the account to sign "
             + "in as — the SSO identity is linked to that existing user by email.</div>");

        List<User> accounts = linkableAccounts();
        if (accounts.isEmpty()) {
            b.append("<p class='sub'>No local accounts found to sign in as.</p>");
        }
        for (User u : accounts) {
            URI link = UriComponentsBuilder.fromPath("/api/v1/auth/sso/mock/approve")
                .queryParam("userId", u.getId().toString())
                .queryParam("redirect_uri", redirectUri)
                .queryParam("state", state == null ? "" : state)
                .encode()
                .build()
                .toUri();
            b.append("<a class='btn' href='")
             .append(HtmlUtils.htmlEscape(link.toString()))
             .append("'><span>")
             .append(HtmlUtils.htmlEscape(u.getDisplayName()))
             .append("</span><span class='role'>")
             .append(HtmlUtils.htmlEscape(label(u.getRole())))
             .append("</span></a>");
        }
        b.append("</div></body></html>");
        return b.toString();
    }

    /** Step 2 — "authenticate" the chosen account, mint a code, and
     *  redirect back to the real callback exactly as a real IdP would.
     *  Accepts {@code userId} (the sign-in page) or {@code role} (a
     *  convenience for tests — resolves to the first linkable account of
     *  that role). */
    @GetMapping("/approve")
    public ResponseEntity<Void> approve(
        @RequestParam(name = "userId", required = false) String userId,
        @RequestParam(name = "role", required = false) UserRole role,
        @RequestParam("redirect_uri") String redirectUri,
        @RequestParam(name = "state", required = false) String state
    ) {
        final User user = resolveUser(userId, role);
        if (user == null) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        final String code = "mockcode-" + UUID.randomUUID();
        codes.put(code, user.getId());
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
    public ResponseEntity<Map<String, Object>> token(
        @RequestParam MultiValueMap<String, String> form
    ) {
        final String code = form.getFirst("code");
        final UUID userId = code == null ? null : codes.remove(code);
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
        }
        final String accessToken = "mocktok-" + UUID.randomUUID();
        tokens.put(accessToken, userId);
        return ResponseEntity.ok(Map.of(
            "access_token", accessToken,
            "token_type", "Bearer",
            "expires_in", 3600,
            "scope", props.getScopes(),
            "id_token", "mock.id.token"
        ));
    }

    /** Step 4 — userinfo. Returns claims for the chosen account: a stable
     *  {@code sub}, their real email (so the service can link), name, and
     *  the configured role claim derived from their role. */
    @GetMapping(value = "/userinfo", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> userinfo(
        @RequestHeader(name = "Authorization", required = false) String authorization
    ) {
        final String token = authorization == null
            ? null
            : authorization.replaceFirst("(?i)^Bearer\\s+", "").trim();
        final UUID userId = token == null ? null : tokens.get(token);
        final User user = userId == null ? null : users.findById(userId).orElse(null);
        if (user == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        Map<String, Object> claims = Map.of(
            "sub", "dda|" + user.getUsername(),
            "name", user.getDisplayName(),
            "preferred_username", user.getUsername(),
            "email", user.getEmail(),
            props.getRoleClaim(), List.of(groupFor(user.getRole()))
        );
        return ResponseEntity.ok(claims);
    }

    /** Real local accounts you can sign in as: active personas, excluding
     *  the synthetic {@code dgov:*} users a prior mock run may have
     *  created. Already-linked personas stay listed (re-login finds them
     *  by external_id), so a persona doesn't vanish after its first SSO.
     *  Sorted by descending privilege then name. */
    private List<User> linkableAccounts() {
        return users.findAll().stream()
            .filter(User::isActive)
            .filter(u -> u.getUsername() == null || !u.getUsername().startsWith("dgov:"))
            .sorted(Comparator
                .comparingInt((User u) -> -u.getRole().ordinal())
                .thenComparing(User::getDisplayName))
            .toList();
    }

    private User resolveUser(String userId, UserRole role) {
        if (userId != null && !userId.isBlank()) {
            try {
                return users.findById(UUID.fromString(userId)).orElse(null);
            } catch (IllegalArgumentException badUuid) {
                return null;
            }
        }
        if (role != null) {
            return linkableAccounts().stream()
                .filter(u -> u.getRole() == role)
                .findFirst()
                .orElse(null);
        }
        return null;
    }

    /** Inverse of the configured role-mapping so the mock stays in sync
     *  with whatever group strings application-local.yml declares. */
    private String groupFor(UserRole role) {
        Optional<String> mapped = props.getRoleMapping().entrySet().stream()
            .filter(e -> e.getValue() == role)
            .map(Map.Entry::getKey)
            .findFirst();
        return mapped.orElse(
            "pdd.delegation-expenses." + role.name().toLowerCase().replace('_', '-'));
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
