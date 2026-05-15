package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.auth.dto.LoginRequest;
import ae.gov.pdd.pettycash.auth.dto.LoginResponse;
import ae.gov.pdd.pettycash.auth.dto.MeResponse;
import ae.gov.pdd.pettycash.auth.dto.RefreshRequest;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.user.User;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** CLAUDE.md §9 — /api/v1/auth/* and /api/v1/me. */
@RestController
@RequestMapping("/api/v1")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/auth/login")
    public LoginResponse login(@Valid @RequestBody LoginRequest body) {
        AuthService.LoginResult result = authService.login(body.username(), body.password());
        return new LoginResponse(MeResponse.from(result.user()), result.tokens());
    }

    @PostMapping("/auth/refresh")
    public LoginResponse refresh(@Valid @RequestBody RefreshRequest body) {
        AuthService.LoginResult result = authService.refresh(body.refreshToken());
        return new LoginResponse(MeResponse.from(result.user()), result.tokens());
    }

    @GetMapping("/me")
    public MeResponse me(@AuthenticationPrincipal AuthenticatedUser principal) {
        if (principal == null) {
            throw new ApiException(
                HttpStatus.UNAUTHORIZED,
                "auth/unauthenticated",
                "Unauthenticated",
                "Authentication is required to access this resource."
            );
        }
        User user = authService.findActive(principal.userId())
            .orElseThrow(() -> new ApiException(
                HttpStatus.UNAUTHORIZED,
                "auth/account-disabled",
                "Account disabled",
                "This account is no longer active."
            ));
        return MeResponse.from(user);
    }
}
