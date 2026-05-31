package ae.gov.pdd.pettycash.auth.sso;

import ae.gov.pdd.pettycash.auth.AuthService;
import ae.gov.pdd.pettycash.auth.JwtService;
import ae.gov.pdd.pettycash.auth.dto.LoginResponse;
import ae.gov.pdd.pettycash.auth.dto.MeResponse;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriComponentsBuilder;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Drives the Smart Dubai OIDC Auth Code + PKCE flow.
 *
 * <p>Why not Spring's built-in OAuth2 client filter? Spring's client
 * integrates deeply with session-based principals and the
 * {@code OAuth2AuthenticationToken} model. Our API is stateless: every
 * request carries its own JWT, and login is a one-shot exchange that
 * lands a token pair in the user's pocket. The flow here is therefore
 * a thin manual driver — three HTTP calls in total — that ends in
 * {@link AuthService}-minted tokens, leaving the rest of the security
 * stack unchanged.
 *
 * <p>See docs/architecture/ADR-001-dda-sso.md for the full plan.
 */
@Service
public class DubaiGovSsoService {

    private static final Logger LOG =
        LoggerFactory.getLogger(DubaiGovSsoService.class);

    private final DubaiGovProperties props;
    private final UserRepository users;
    private final AuthService auth;
    private final JwtService jwt;
    private final RestClient http;
    private final ObjectMapper json;
    private final Clock clock;

    // state ↔ pending-login map. TTL'd by {@link #pruneExpired}.
    private final Map<String, PendingLogin> pending = new ConcurrentHashMap<>();
    // one-time exchange code ↔ minted token pair. Same TTL story.
    private final Map<String, MintedTokens> awaitingExchange =
        new ConcurrentHashMap<>();

    private static final long STATE_TTL_SECONDS = 300; // 5 min
    private static final long EXCHANGE_TTL_SECONDS = 60; // 1 min

    @Autowired
    public DubaiGovSsoService(
        DubaiGovProperties props,
        UserRepository users,
        AuthService auth,
        JwtService jwt,
        ObjectMapper json
    ) {
        this(props, users, auth, jwt, json, Clock.systemUTC());
    }

    DubaiGovSsoService(
        DubaiGovProperties props,
        UserRepository users,
        AuthService auth,
        JwtService jwt,
        ObjectMapper json,
        Clock clock
    ) {
        this.props = props;
        this.users = users;
        this.auth = auth;
        this.jwt = jwt;
        this.json = json;
        this.clock = clock;
        this.http = RestClient.builder().build();
    }

    // ---------------------------------------------------------------
    // Step 1 — build the authorize URL the browser is sent to.
    // ---------------------------------------------------------------

    /** Returns the IdP authorize URL the browser should be 302'd to.
     *  Persists the PKCE verifier + audience under a fresh `state`. */
    public String startUrl(Audience audience) {
        requireEnabled();
        final String verifier = randomUrlSafe(64);
        final String challenge = sha256Base64Url(verifier);
        final String state = randomUrlSafe(32);
        pending.put(state, new PendingLogin(
            verifier, audience, clock.instant()
        ));
        pruneExpired();

        return UriComponentsBuilder.fromUriString(props.getAuthorizationUri())
            .queryParam("response_type", "code")
            .queryParam("client_id", props.getClientId())
            .queryParam("redirect_uri", props.getRedirectUri())
            .queryParam("scope", props.getScopes())
            .queryParam("state", state)
            .queryParam("code_challenge", challenge)
            .queryParam("code_challenge_method", "S256")
            .build(true)
            .toUriString();
    }

    // ---------------------------------------------------------------
    // Step 2 — IdP redirects to our callback with `code` + `state`.
    // ---------------------------------------------------------------

    /** Exchanges the IdP's code for an ID + access token, fetches
     *  userinfo, upserts the User, mints our own JWTs, and returns the
     *  destination URL the browser should be redirected to (with a
     *  one-time exchange code the SPA can swap for the tokens).
     */
    @Transactional
    public String completeCallback(String code, String state) {
        requireEnabled();
        PendingLogin pendingLogin = pending.remove(state);
        if (pendingLogin == null) {
            throw new ApiException(
                HttpStatus.BAD_REQUEST, "auth/sso-state-unknown",
                "Unknown or expired SSO state",
                "Restart the sign-in flow from the login page."
            );
        }

        Map<String, Object> tokenResponse =
            exchangeCodeForTokens(code, pendingLogin.codeVerifier);
        Map<String, Object> userInfo =
            fetchUserInfo((String) tokenResponse.get("access_token"));
        if (userInfo == null) {
            throw new ApiException(
                HttpStatus.BAD_GATEWAY, "auth/sso-userinfo-failed",
                "Userinfo lookup failed",
                "The IdP returned no user information for the access token."
            );
        }

        User u = upsertFromClaims(userInfo);
        AuthService.LoginResult login = auth.mintForUser(u);

        // Hand the SPA a one-time exchange code rather than putting the
        // JWTs straight in the URL. The SPA POSTs it to /sso/exchange to
        // collect the real tokens. Same fingerprint protection as Auth
        // Code itself — single-use, short-lived, host-fixed.
        final String exchangeCode = randomUrlSafe(32);
        awaitingExchange.put(exchangeCode, new MintedTokens(
            login, clock.instant()
        ));
        pruneExpired();

        final String dest = switch (pendingLogin.audience) {
            case MOBILE_WEB -> props.getWebMobileCallback();
            case PORTAL -> props.getWebPortalCallback();
            case MOBILE_NATIVE -> props.getNativeCallback();
        };
        return UriComponentsBuilder.fromUriString(dest)
            .queryParam("code", exchangeCode)
            .build(true)
            .toUriString();
    }

    // ---------------------------------------------------------------
    // Step 3 — SPA / native client swaps the one-time code for tokens.
    // ---------------------------------------------------------------

    public LoginResponse exchange(String oneTimeCode) {
        requireEnabled();
        MintedTokens minted = awaitingExchange.remove(oneTimeCode);
        if (minted == null) {
            throw new ApiException(
                HttpStatus.BAD_REQUEST, "auth/sso-exchange-unknown",
                "Unknown or expired exchange code",
                "Restart the sign-in flow from the login page."
            );
        }
        return new LoginResponse(
            MeResponse.from(minted.login.user()),
            minted.login.tokens()
        );
    }

    /** Returns the IdP SAML SLO URL the browser should be redirected
     *  to after we've cleared the local session. */
    public String samlSloUri() {
        return props.getSamlSloUri();
    }

    public boolean enabled() {
        return props.isEnabled();
    }

    // ---------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------

    private void requireEnabled() {
        if (!props.isEnabled()) {
            throw new ApiException(
                HttpStatus.NOT_FOUND, "auth/sso-disabled",
                "SSO is not enabled",
                "Dubai-Gov SSO is disabled in this environment."
            );
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> exchangeCodeForTokens(
        String code, String codeVerifier
    ) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "authorization_code");
        form.add("code", code);
        form.add("redirect_uri", props.getRedirectUri());
        form.add("client_id", props.getClientId());
        form.add("client_secret", props.getClientSecret());
        form.add("code_verifier", codeVerifier);

        try {
            return http.post()
                .uri(props.getTokenUri())
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .accept(MediaType.APPLICATION_JSON)
                .body(form)
                .retrieve()
                .body(Map.class);
        } catch (Exception e) {
            LOG.error("Token exchange failed", e);
            throw new ApiException(
                HttpStatus.BAD_GATEWAY, "auth/sso-token-failed",
                "Token exchange failed",
                "The IdP rejected the code exchange: " + e.getMessage()
            );
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> fetchUserInfo(String accessToken) {
        try {
            return http.get()
                .uri(props.getUserInfoUri())
                .header("Authorization", "Bearer " + accessToken)
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .body(Map.class);
        } catch (Exception e) {
            LOG.error("Userinfo fetch failed", e);
            throw new ApiException(
                HttpStatus.BAD_GATEWAY, "auth/sso-userinfo-failed",
                "Userinfo fetch failed",
                "The IdP rejected the access token: " + e.getMessage()
            );
        }
    }

    private User upsertFromClaims(Map<String, Object> claims) {
        final String sub = stringClaim(claims, "sub");
        if (sub == null || sub.isBlank()) {
            throw new ApiException(
                HttpStatus.BAD_GATEWAY, "auth/sso-no-sub",
                "Missing sub claim",
                "The IdP did not return a stable user identifier."
            );
        }
        final UserRole role = mapRole(claims);

        return users.findByExternalId(sub)
            .map(existing -> {
                // Reflect upstream changes that affect what the user sees.
                existing.setRole(role);
                final String name = stringClaim(claims, "name");
                if (name != null && !name.isBlank()) {
                    existing.setDisplayName(name);
                }
                final String email = stringClaim(claims, "email");
                if (email != null && !email.isBlank()) {
                    existing.setEmail(email);
                }
                return existing;
            })
            .orElseGet(() -> {
                final String display = firstNonBlank(
                    stringClaim(claims, "name"),
                    stringClaim(claims, "preferred_username"),
                    "User"
                );
                final String email = firstNonBlank(
                    stringClaim(claims, "email"),
                    sub + "@dubaigov.local"
                );
                // username is unique in the schema; sub is globally unique.
                final String synthUsername = "dgov:" + sub;
                User u = new User(
                    UUID.randomUUID(),
                    synthUsername,
                    display,
                    display, // displayNameAr — IdP doesn't give us Arabic
                    email,
                    // No local password; passwordHash NOT NULL on the
                    // schema, so we stash an unreachable sentinel.
                    "!sso:" + UUID.randomUUID(),
                    role
                );
                u.setExternalId(sub);
                return users.save(u);
            });
    }

    /** Walk the configured role-claim list. First matching mapping wins.
     *  Falls back to {@link DubaiGovProperties#getDefaultRole()}. */
    private UserRole mapRole(Map<String, Object> claims) {
        Object raw = claims.get(props.getRoleClaim());
        if (raw == null) return props.getDefaultRole();
        Iterable<?> values;
        if (raw instanceof Iterable<?> it) {
            values = it;
        } else if (raw instanceof String s) {
            values = java.util.List.of(s);
        } else {
            return props.getDefaultRole();
        }
        UserRole best = null;
        for (Object v : values) {
            UserRole mapped = props.getRoleMapping().get(String.valueOf(v));
            if (mapped == null) continue;
            if (best == null || mapped.ordinal() > best.ordinal()) {
                best = mapped;
            }
        }
        return best != null ? best : props.getDefaultRole();
    }

    private static String stringClaim(Map<String, Object> claims, String key) {
        Object v = claims.get(key);
        return v == null ? null : String.valueOf(v);
    }

    private static String firstNonBlank(String... candidates) {
        for (String c : candidates) {
            if (c != null && !c.isBlank()) return c;
        }
        return "";
    }

    private void pruneExpired() {
        final Instant cutoffPending =
            clock.instant().minusSeconds(STATE_TTL_SECONDS);
        pending.values().removeIf(p -> p.createdAt.isBefore(cutoffPending));
        final Instant cutoffExchange =
            clock.instant().minusSeconds(EXCHANGE_TTL_SECONDS);
        awaitingExchange.values().removeIf(m -> m.createdAt.isBefore(cutoffExchange));
    }

    // ---------------------------------------------------------------
    // PKCE helpers
    // ---------------------------------------------------------------

    private static final SecureRandom RNG = new SecureRandom();
    private static final Base64.Encoder URL = Base64.getUrlEncoder().withoutPadding();

    private static String randomUrlSafe(int byteLen) {
        byte[] raw = new byte[byteLen];
        RNG.nextBytes(raw);
        return URL.encodeToString(raw);
    }

    private static String sha256Base64Url(String input) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] hashed = md.digest(input.getBytes(StandardCharsets.US_ASCII));
            return URL.encodeToString(hashed);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }

    // ---------------------------------------------------------------
    // Inner records
    // ---------------------------------------------------------------

    /**
     * Where the IdP callback should land the user after exchange. The
     * `state` parameter round-trips this through the IdP so the
     * callback can pick the right destination.
     */
    public enum Audience { MOBILE_WEB, PORTAL, MOBILE_NATIVE }

    private record PendingLogin(
        String codeVerifier,
        Audience audience,
        Instant createdAt
    ) {}

    private record MintedTokens(
        AuthService.LoginResult login,
        Instant createdAt
    ) {}
}
