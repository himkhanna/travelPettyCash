package ae.gov.pdd.pettycash.auth.sso;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Externalised configuration for the UAE Pass (TDRA national digital ID)
 * OIDC integration. Reads the {@code pdd.auth.uaepass.*} namespace.
 * Defaults target the public staging sandbox. See
 * docs/architecture/ADR-002-uaepass-sso.md.
 *
 * <p>Unlike Dubai-Gov, UAE Pass returns identity only (Emirates ID, name,
 * email) and no app role — role resolution is local (link-to-existing),
 * so there is no role-claim / role-mapping config here.
 */
@ConfigurationProperties(prefix = "pdd.auth.uaepass")
public class UaePassProperties {

    /** Feature flag. When false the {@code /auth/sso/uaepass/*} endpoints
     *  return 404 and the login screens hide the UAE Pass button. Off by
     *  default until TDRA has registered our redirect URI. */
    private boolean enabled = false;

    /** OAuth client id. Sandbox value is {@code sandbox_stage}. */
    private String clientId = "sandbox_stage";

    /** OAuth client secret. Sandbox value is {@code sandbox_stage}. Read
     *  from PDD_UAEPASS_CLIENT_SECRET in real environments. */
    private String clientSecret = "sandbox_stage";

    /** Full URL UAE Pass redirects back to after authentication. Must match
     *  a URI TDRA has whitelisted against our client. */
    private String redirectUri = "http://localhost:8080/api/v1/auth/sso/uaepass/callback";

    /** OIDC endpoints. Defaults point at the staging sandbox. */
    private String authorizationUri = "https://stg-id.uaepass.ae/idshub/authorize";
    private String tokenUri = "https://stg-id.uaepass.ae/idshub/token";
    private String userInfoUri = "https://stg-id.uaepass.ae/idshub/userinfo";
    private String logoutUri = "https://stg-id.uaepass.ae/idshub/logout";

    /** Where the Flutter Web bundle's UAE Pass callback lives, by audience.
     *  The callback hands the SPA a one-time exchange code. */
    private String webMobileCallback = "http://localhost:5173/app/auth/uaepass/callback";
    private String webPortalCallback = "http://localhost:5173/portal/auth/uaepass/callback";

    /** UAE Pass digital-id profile scope. */
    private String scope = "urn:uae:digitalid:profile:general";

    /** Authentication context class — assurance level. The web redirect
     *  flow uses the "low" Safelayer policy; the native app-to-app flow
     *  (urn:digitalid:authentication:flow:mobileondevice) is v2. */
    private String acrValues = "urn:safelayer:tws:policies:authentication:level:low";

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean v) { this.enabled = v; }

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

    public String getLogoutUri() { return logoutUri; }
    public void setLogoutUri(String v) { this.logoutUri = v; }

    public String getWebMobileCallback() { return webMobileCallback; }
    public void setWebMobileCallback(String v) { this.webMobileCallback = v; }

    public String getWebPortalCallback() { return webPortalCallback; }
    public void setWebPortalCallback(String v) { this.webPortalCallback = v; }

    public String getScope() { return scope; }
    public void setScope(String v) { this.scope = v; }

    public String getAcrValues() { return acrValues; }
    public void setAcrValues(String v) { this.acrValues = v; }
}
