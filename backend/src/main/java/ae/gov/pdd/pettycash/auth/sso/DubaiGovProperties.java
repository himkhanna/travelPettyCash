package ae.gov.pdd.pettycash.auth.sso;

import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.Map;

/**
 * Externalised configuration for the Smart Dubai OIDC integration.
 * Reads the `pdd.auth.dubaigov.*` namespace from application.yml /
 * environment variables. Credentials themselves live under
 * `spring.security.oauth2.client.registration.dubaigov.*` and are
 * supplied via env vars (PDD_SMARTDUBAI_CLIENT_ID + _SECRET).
 *
 * <p>See docs/architecture/ADR-001-dda-sso.md for the full plan.
 */
@ConfigurationProperties(prefix = "pdd.auth.dubaigov")
public class DubaiGovProperties {

    /**
     * Feature flag. When false the SSO endpoints return 404; when true
     * the mobile + CMS login screens show the "Sign in with Dubai Gov"
     * button. Off by default until DDA has whitelisted our callback
     * URI for the registered client.
     */
    private boolean enabled = false;

    /** OAuth client id (mirrors Spring's registration; kept here for
     *  logging + the start-URL builder which doesn't go through
     *  Spring's OAuth2 client filter). */
    private String clientId = "";

    /** OAuth client secret. Read from PDD_SMARTDUBAI_CLIENT_SECRET. */
    private String clientSecret = "";

    /** Full URL we tell the IdP to redirect back to. Must exactly match
     *  one of the URIs DDA has whitelisted against our client. */
    private String redirectUri = "http://localhost:8080/api/v1/auth/sso/callback";

    /** OIDC discovery endpoints. Defaults point at the demo tenant. */
    private String authorizationUri =
        "https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/authorize";
    private String tokenUri =
        "https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/token";
    private String userInfoUri =
        "https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/userinfo";
    private String issuer = "https://demoidp.dubai.gov.ae";

    /** Browser redirect URL for the IdP's SAML 2.0 SLO endpoint —
     *  the IdP doesn't expose OIDC RP-Initiated Logout. */
    private String samlSloUri =
        "https://demoidp.dubai.gov.ae/isam/sps/idpdubaigov/saml20/sloinitial";

    /** Where the Flutter Web bundle lives, by audience. The callback
     *  redirects here with a one-time exchange code so the SPA can
     *  collect its JWT pair without leaking it through the URL bar. */
    private String webMobileCallback = "http://localhost:5173/app/auth/callback";
    private String webPortalCallback = "http://localhost:5173/portal/auth/callback";
    /** Custom-scheme deep link for native mobile builds. */
    private String nativeCallback = "ae.gov.pdd.pettycash://auth/callback";

    /** Scope set to request from the IdP. `openid` is mandatory;
     *  `profile` + `email` give us the userinfo claims we map onto
     *  display name / email. The role-claim scope (e.g. `groups`)
     *  gets added here once DDA confirms its name. */
    private String scopes = "openid profile email";

    /** Name of the claim that carries the user's role membership. */
    private String roleClaim = "groups";

    /** group-string → UserRole mapping. The first match in the user's
     *  claim list wins, scanned by descending privilege. */
    private Map<String, UserRole> roleMapping = Map.of();

    /** Used when no entry in {@link #roleMapping} matches anything in
     *  the user's claim. Keeps a federated user functional rather than
     *  locked out. */
    private UserRole defaultRole = UserRole.MEMBER;

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }

    public String getClientId() { return clientId; }
    public void setClientId(String v) { this.clientId = v; }

    public String getClientSecret() { return clientSecret; }
    public void setClientSecret(String v) { this.clientSecret = v; }

    public String getRedirectUri() { return redirectUri; }
    public void setRedirectUri(String v) { this.redirectUri = v; }

    public String getAuthorizationUri() { return authorizationUri; }
    public void setAuthorizationUri(String v) { this.authorizationUri = v; }

    public String getTokenUri() { return tokenUri; }
    public void setTokenUri(String v) { this.tokenUri = v; }

    public String getUserInfoUri() { return userInfoUri; }
    public void setUserInfoUri(String v) { this.userInfoUri = v; }

    public String getIssuer() { return issuer; }
    public void setIssuer(String v) { this.issuer = v; }

    public String getSamlSloUri() { return samlSloUri; }
    public void setSamlSloUri(String v) { this.samlSloUri = v; }

    public String getWebMobileCallback() { return webMobileCallback; }
    public void setWebMobileCallback(String v) { this.webMobileCallback = v; }

    public String getWebPortalCallback() { return webPortalCallback; }
    public void setWebPortalCallback(String v) { this.webPortalCallback = v; }

    public String getNativeCallback() { return nativeCallback; }
    public void setNativeCallback(String v) { this.nativeCallback = v; }

    public String getScopes() { return scopes; }
    public void setScopes(String v) { this.scopes = v; }

    public String getRoleClaim() { return roleClaim; }
    public void setRoleClaim(String v) { this.roleClaim = v; }

    public Map<String, UserRole> getRoleMapping() { return roleMapping; }
    public void setRoleMapping(Map<String, UserRole> v) {
        this.roleMapping = v == null ? Map.of() : v;
    }

    public UserRole getDefaultRole() { return defaultRole; }
    public void setDefaultRole(UserRole v) { this.defaultRole = v; }
}
