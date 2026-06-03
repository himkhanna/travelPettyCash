package ae.gov.pdd.pettycash.auth.sso;

import ae.gov.pdd.pettycash.auth.AuthService;
import ae.gov.pdd.pettycash.auth.dto.LoginResponse;
import ae.gov.pdd.pettycash.auth.dto.MeResponse;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
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

import java.security.SecureRandom;
import java.time.Clock;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Drives the UAE Pass (TDRA) OIDC Authorization-Code flow.
 *
 * <p>Mirrors {@link DubaiGovSsoService} but with the UAE-Pass specifics:
 * no PKCE (the token call authenticates with HTTP Basic client creds),
 * and — crucially — UAE Pass returns <em>identity only</em>, no app role.
 * So {@link #linkOrReject} resolves the asserted identity to a
 * pre-provisioned PDD account (by {@code external_id}, then email) and
 * keeps that account's existing role; an unknown identity is rejected
 * rather than auto-provisioned.
 *
 * <p>See docs/architecture/ADR-002-uaepass-sso.md.
 */
@Service
public class UaePassSsoService {

    private static final Logger LOG = LoggerFactory.getLogger(UaePassSsoService.class);

    private final UaePassProperties props;
    private final UserRepository users;
    private final AuthService auth;
    private final RestClient http;
    private final Clock clock;

    private final Map<String, PendingLogin> pending = new ConcurrentHashMap<>();
    private final Map<String, MintedTokens> awaitingExchange = new ConcurrentHashMap<>();

    private static final long STATE_TTL_SECONDS = 300;
    private static final long EXCHANGE_TTL_SECONDS = 120;

    @Autowired
    public UaePassSsoService(
        UaePassProperties props,
        UserRepository users,
        AuthService auth
    ) {
        this(props, users, auth, Clock.systemUTC(), RestClient.builder().build());
    }

    UaePassSsoService(
        UaePassProperties props,
        UserRepository users,
        AuthService auth,
        Clock clock,
        RestClient http
    ) {
        this.props = props;
        this.users = users;
        this.auth = auth;
        this.clock = clock;
        this.http = http;
    }

    public enum Audience { MOBILE_WEB, PORTAL }

    public boolean enabled() {
        return props.isEnabled();
    }

    /** Browser redirect URL for UAE Pass logout (RP-initiated). */
    public String logoutUri() {
        return props.getLogoutUri();
    }

    // ---------------------------------------------------------------
    // Step 1 — authorize URL
    // ---------------------------------------------------------------

    public String startUrl(Audience audience) {
        requireEnabled();
        final String state = randomUrlSafe(32);
        pending.put(state, new PendingLogin(audience, clock.instant()));
        pruneExpired();

        return UriComponentsBuilder.fromUriString(props.getAuthorizationUri())
            .queryParam("response_type", "code")
            .queryParam("client_id", props.getClientId())
            .queryParam("scope", props.getScope())
            .queryParam("state", state)
            .queryParam("redirect_uri", props.getRedirectUri())
            .queryParam("acr_values", props.getAcrValues())
            // encode (not build(true)) — scope + acr_values carry ':' and
            // (for scope) literal spaces that must be percent-encoded.
            .encode()
            .build()
            .toUriString();
    }

    // ---------------------------------------------------------------
    // Step 2 — callback: exchange code, fetch userinfo, link, mint
    // ---------------------------------------------------------------

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

        Map<String, Object> tokenResponse = exchangeCodeForTokens(code);
        Map<String, Object> userInfo =
            fetchUserInfo((String) tokenResponse.get("access_token"));
        if (userInfo == null) {
            throw new ApiException(
                HttpStatus.BAD_GATEWAY, "auth/sso-userinfo-failed",
                "Userinfo lookup failed",
                "UAE Pass returned no user information for the access token."
            );
        }

        User user = linkOrReject(userInfo);
        AuthService.LoginResult login = auth.mintForUser(user);

        final String exchangeCode = randomUrlSafe(32);
        awaitingExchange.put(exchangeCode, new MintedTokens(login, clock.instant()));
        pruneExpired();

        final String dest = switch (pendingLogin.audience) {
            case MOBILE_WEB -> props.getWebMobileCallback();
            case PORTAL -> props.getWebPortalCallback();
        };
        return UriComponentsBuilder.fromUriString(dest)
            .queryParam("code", exchangeCode)
            .encode()
            .build()
            .toUriString();
    }

    // ---------------------------------------------------------------
    // Step 3 — SPA swaps the one-time code for the JWT pair
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

    // ---------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------

    private void requireEnabled() {
        if (!props.isEnabled()) {
            throw new ApiException(
                HttpStatus.NOT_FOUND, "auth/sso-disabled",
                "SSO is not enabled",
                "UAE Pass SSO is disabled in this environment."
            );
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> exchangeCodeForTokens(String code) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "authorization_code");
        form.add("code", code);
        form.add("redirect_uri", props.getRedirectUri());
        try {
            return http.post()
                .uri(props.getTokenUri())
                // UAE Pass token endpoint authenticates the client with
                // HTTP Basic (base64 client_id:client_secret), not form creds.
                .headers(h -> h.setBasicAuth(props.getClientId(), props.getClientSecret()))
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .accept(MediaType.APPLICATION_JSON)
                .body(form)
                .retrieve()
                .body(Map.class);
        } catch (Exception e) {
            LOG.error("UAE Pass token exchange failed", e);
            throw new ApiException(
                HttpStatus.BAD_GATEWAY, "auth/sso-token-failed",
                "Token exchange failed",
                "UAE Pass rejected the code exchange: " + e.getMessage()
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
            LOG.error("UAE Pass userinfo fetch failed", e);
            throw new ApiException(
                HttpStatus.BAD_GATEWAY, "auth/sso-userinfo-failed",
                "Userinfo fetch failed",
                "UAE Pass rejected the access token: " + e.getMessage()
            );
        }
    }

    /**
     * Resolve the UAE Pass identity to a pre-provisioned PDD account.
     * Match by {@code external_id} (returning user), then by Emirates ID
     * (the stable national identifier — preferred), then by email. Reject
     * unknown identities — UAE Pass carries no app role, so we never
     * auto-provision. The account's existing role is preserved; the
     * Emirates ID is backfilled on first link. ADR-002 decision 2.
     */
    private User linkOrReject(Map<String, Object> claims) {
        final String uuid = uuidOf(claims);
        if (uuid == null || uuid.isBlank()) {
            throw new ApiException(
                HttpStatus.BAD_GATEWAY, "auth/sso-no-sub",
                "Missing user identifier",
                "UAE Pass did not return a stable user identifier."
            );
        }
        final String externalId = "uaepass|" + uuid;
        final String email = stringClaim(claims, "email");
        final String emiratesId = stringClaim(claims, "idn");
        final String displayName = displayNameOf(claims);

        // 1. Returning federated user (by external_id).
        Optional<User> byExt = users.findByExternalId(externalId);
        if (byExt.isPresent()) {
            return refresh(byExt.get(), displayName, email, emiratesId);
        }

        // 2. First login — link to a pre-provisioned account. Prefer the
        //    Emirates ID (stable, unique), then fall back to email.
        if (emiratesId != null && !emiratesId.isBlank()) {
            Optional<User> byIdn = users.findByEmiratesId(emiratesId);
            if (byIdn.isPresent()) {
                User u = byIdn.get();
                u.setExternalId(externalId); // role untouched — local source of truth
                return refresh(u, displayName, email, emiratesId);
            }
        }
        if (email != null && !email.isBlank()) {
            Optional<User> byEmail = users.findByEmailIgnoreCase(email);
            if (byEmail.isPresent()) {
                User u = byEmail.get();
                u.setExternalId(externalId); // role untouched — local source of truth
                return refresh(u, displayName, email, emiratesId);
            }
        }

        // 3. Unknown identity — UAE Pass authenticated them, but they are
        //    not a PDD user. Do not auto-provision.
        throw new ApiException(
            HttpStatus.FORBIDDEN, "auth/sso-no-account",
            "No PDD account",
            "Your UAE Pass identity is not linked to a PDD Delegation Expenses "
                + "account. Contact your administrator to be added."
        );
    }

    /** Reflect IdP-owned fields onto the linked account: refresh name +
     *  email, and backfill the Emirates ID if we didn't have it yet (it is
     *  stable, so we don't overwrite an existing value). Role is never
     *  touched — it's local source of truth. */
    private User refresh(User u, String displayName, String email, String emiratesId) {
        if (displayName != null && !displayName.isBlank()) {
            u.setDisplayName(displayName);
        }
        if (email != null && !email.isBlank()) {
            u.setEmail(email);
        }
        if (emiratesId != null && !emiratesId.isBlank()
            && (u.getEmiratesId() == null || u.getEmiratesId().isBlank())) {
            u.setEmiratesId(emiratesId);
        }
        return u;
    }

    /** UAE Pass carries the UUID in a {@code uuid} claim and also inside
     *  {@code sub} as {@code "UAEPASS/{uuid}"}. Prefer the explicit claim. */
    private static String uuidOf(Map<String, Object> claims) {
        String uuid = stringClaim(claims, "uuid");
        if (uuid != null && !uuid.isBlank()) {
            return uuid;
        }
        String sub = stringClaim(claims, "sub");
        if (sub == null) {
            return null;
        }
        int slash = sub.indexOf('/');
        return slash >= 0 ? sub.substring(slash + 1) : sub;
    }

    /** SOP3 gives {@code fullnameEN}; lower assurance levels give the name
     *  in parts. Fall back to the Emirates ID / a generic label. */
    private static String displayNameOf(Map<String, Object> claims) {
        String full = stringClaim(claims, "fullnameEN");
        if (full != null && !full.isBlank()) {
            return full;
        }
        String first = stringClaim(claims, "firstnameEN");
        String last = stringClaim(claims, "lastnameEN");
        String combined = ((first == null ? "" : first) + " "
            + (last == null ? "" : last)).trim();
        return combined.isBlank() ? null : combined;
    }

    private static String stringClaim(Map<String, Object> claims, String key) {
        Object v = claims.get(key);
        return v == null ? null : String.valueOf(v);
    }

    private void pruneExpired() {
        final Instant pCut = clock.instant().minusSeconds(STATE_TTL_SECONDS);
        pending.values().removeIf(p -> p.createdAt.isBefore(pCut));
        final Instant eCut = clock.instant().minusSeconds(EXCHANGE_TTL_SECONDS);
        awaitingExchange.values().removeIf(m -> m.createdAt.isBefore(eCut));
    }

    private static final SecureRandom RNG = new SecureRandom();
    private static final Base64.Encoder URL = Base64.getUrlEncoder().withoutPadding();

    private static String randomUrlSafe(int byteLen) {
        byte[] raw = new byte[byteLen];
        RNG.nextBytes(raw);
        return URL.encodeToString(raw);
    }

    private record PendingLogin(Audience audience, Instant createdAt) {}

    private record MintedTokens(AuthService.LoginResult login, Instant createdAt) {}
}
