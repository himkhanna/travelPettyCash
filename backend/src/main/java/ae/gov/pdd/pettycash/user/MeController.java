package ae.gov.pdd.pettycash.user;

import ae.gov.pdd.pettycash.auth.CurrentUser;
import ae.gov.pdd.pettycash.common.ApiException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class MeController {

    public record UserDto(
        UUID id, String username, String displayName, String displayNameAr,
        String email, Role role, boolean isActive
    ) {
        static UserDto from(User u) {
            return new UserDto(u.getId(), u.getUsername(), u.getDisplayName(), u.getDisplayNameAr(),
                u.getEmail(), u.getRole(), u.isActive());
        }
    }

    private final UserRepository users;
    private final CurrentUser current;

    public MeController(UserRepository users, CurrentUser current) {
        this.users = users;
        this.current = current;
    }

    @GetMapping("/me")
    public UserDto me() {
        return users.findById(current.id())
            .map(UserDto::from)
            .orElseThrow(() -> ApiException.notFound("USER_NOT_FOUND", "Authenticated user not found in DB"));
    }
}
