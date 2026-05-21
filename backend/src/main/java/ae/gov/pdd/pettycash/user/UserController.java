package ae.gov.pdd.pettycash.user;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.NotFoundException;
import ae.gov.pdd.pettycash.user.UserDtos.CreateUserRequest;
import ae.gov.pdd.pettycash.user.UserDtos.UpdateUserRequest;
import ae.gov.pdd.pettycash.user.UserDtos.UserView;
import jakarta.validation.Valid;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
public class UserController {

    private final UserRepository users;

    public UserController(UserRepository users) {
        this.users = users;
    }

    @GetMapping("/me")
    public UserView me(@AuthenticationPrincipal AuthenticatedUser me) {
        return UserView.of(users.findById(me.id()).orElseThrow(NotFoundException::new));
    }

    @GetMapping("/users")
    @PreAuthorize("hasAnyRole('ADMIN','SUPER_ADMIN')")
    public List<UserView> list() {
        return users.findAll().stream().map(UserView::of).toList();
    }

    @PostMapping("/users")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<UserView> create(@Valid @RequestBody CreateUserRequest req) {
        if (users.existsByUsernameIgnoreCase(req.username())
                || users.existsByEmailIgnoreCase(req.email())) {
            throw new IllegalArgumentException("Username or email already in use.");
        }
        UserEntity u = new UserEntity(
                "u-" + UUID.randomUUID().toString().substring(0, 8),
                req.username(), req.displayName(), req.displayNameAr(),
                req.email(), req.role(), req.active(), OffsetDateTime.now()
        );
        return ResponseEntity.ok(UserView.of(users.save(u)));
    }

    @PutMapping("/users/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public UserView update(@PathVariable String id, @Valid @RequestBody UpdateUserRequest req) {
        UserEntity u = users.findById(id).orElseThrow(NotFoundException::new);
        u.setDisplayName(req.displayName());
        u.setDisplayNameAr(req.displayNameAr());
        u.setEmail(req.email());
        u.setRole(req.role());
        u.setActive(req.active());
        return UserView.of(users.save(u));
    }
}
