package ae.gov.pdd.pettycash.user;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.OffsetDateTime;

@Entity
@Table(name = "users")
public class UserEntity {
    @Id
    private String id;
    @Column(nullable = false, unique = true)
    private String username;
    @Column(name = "display_name", nullable = false)
    private String displayName;
    @Column(name = "display_name_ar", nullable = false)
    private String displayNameAr;
    @Column(nullable = false, unique = true)
    private String email;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private UserRole role;
    @Column(name = "is_active", nullable = false)
    private boolean active;
    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected UserEntity() {}

    public UserEntity(String id, String username, String displayName, String displayNameAr,
                      String email, UserRole role, boolean active, OffsetDateTime createdAt) {
        this.id = id;
        this.username = username;
        this.displayName = displayName;
        this.displayNameAr = displayNameAr;
        this.email = email;
        this.role = role;
        this.active = active;
        this.createdAt = createdAt;
    }

    public String getId() { return id; }
    public String getUsername() { return username; }
    public String getDisplayName() { return displayName; }
    public String getDisplayNameAr() { return displayNameAr; }
    public String getEmail() { return email; }
    public UserRole getRole() { return role; }
    public boolean isActive() { return active; }
    public OffsetDateTime getCreatedAt() { return createdAt; }

    public void setDisplayName(String v) { this.displayName = v; }
    public void setDisplayNameAr(String v) { this.displayNameAr = v; }
    public void setEmail(String v) { this.email = v; }
    public void setRole(UserRole v) { this.role = v; }
    public void setActive(boolean v) { this.active = v; }
}
