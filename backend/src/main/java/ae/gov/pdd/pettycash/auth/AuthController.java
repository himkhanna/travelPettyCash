package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.user.UserDtos.UserView;
import ae.gov.pdd.pettycash.user.UserEntity;
import ae.gov.pdd.pettycash.user.UserRepository;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/// Demo auth: username only. No password is checked because the prototype
/// has never had passwords — the landing role-picker is the equivalent
/// today. Wire UAE Pass or password verification before any non-demo use.
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final UserRepository users;
    private final JwtService jwt;

    public AuthController(UserRepository users, JwtService jwt) {
        this.users = users;
        this.jwt = jwt;
    }

    public record LoginRequest(@NotBlank String username) {}

    public record LoginResponse(
            String accessToken,
            long expiresIn,
            UserView user
    ) {}

    @PostMapping("/login")
    public ResponseEntity<LoginResponse> login(@Valid @RequestBody LoginRequest req) {
        UserEntity u = users.findByUsername(req.username())
                .orElseThrow(() -> new IllegalArgumentException("Unknown user"));
        if (!u.isActive()) {
            throw new IllegalArgumentException("User is deactivated");
        }
        String token = jwt.mintAccessToken(u);
        return ResponseEntity.ok(
                new LoginResponse(token, jwt.accessTtlSeconds(), UserView.of(u))
        );
    }
}
