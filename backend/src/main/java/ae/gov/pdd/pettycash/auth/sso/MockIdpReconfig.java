package ae.gov.pdd.pettycash.auth.sso;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * DEV-ONLY. When {@code pdd.auth.dubaigov.mock-idp=true}, repoints the
 * authorize / token / userinfo URIs at the in-process
 * {@link MockIdpController} so {@link DubaiGovSsoService} runs unchanged
 * against the local fake. The redirect URI is left alone — the mock
 * redirects the browser back to our real {@code /callback}, exactly as a
 * real IdP would. Off by default; never set outside local dev.
 *
 * <p>See docs/architecture/ADR-001-dda-sso.md.
 */
@Component
@ConditionalOnProperty(prefix = "pdd.auth.dubaigov", name = "mock-idp", havingValue = "true")
class MockIdpReconfig implements InitializingBean {

    private static final Logger LOG = LoggerFactory.getLogger(MockIdpReconfig.class);

    private final DubaiGovProperties props;

    MockIdpReconfig(DubaiGovProperties props) {
        this.props = props;
    }

    @Override
    public void afterPropertiesSet() {
        // Derive the server base from the (real) redirect URI so this
        // works regardless of the configured port.
        final String base = props.getRedirectUri()
            .replace("/api/v1/auth/sso/callback", "");
        props.setAuthorizationUri(base + "/api/v1/auth/sso/mock/authorize");
        props.setTokenUri(base + "/api/v1/auth/sso/mock/token");
        props.setUserInfoUri(base + "/api/v1/auth/sso/mock/userinfo");
        LOG.warn("Dubai-Gov MOCK IdP enabled — OIDC endpoints repointed to {}"
            + "/api/v1/auth/sso/mock/* (DEV ONLY).", base);
    }
}
