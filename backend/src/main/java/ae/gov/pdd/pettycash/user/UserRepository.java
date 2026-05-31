package ae.gov.pdd.pettycash.user;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface UserRepository extends JpaRepository<User, UUID> {
    Optional<User> findByUsername(String username);
    boolean existsByUsername(String username);
    /** Lookup federated users by Smart Dubai OIDC `sub` claim.
     *  See docs/architecture/ADR-001-dda-sso.md. */
    Optional<User> findByExternalId(String externalId);

    /** Case-insensitive search across name + handle for global search. */
    @Query("""
        SELECT u FROM User u
         WHERE LOWER(u.displayName)   LIKE LOWER(CONCAT('%', :q, '%'))
            OR LOWER(u.displayNameAr) LIKE LOWER(CONCAT('%', :q, '%'))
            OR LOWER(u.username)      LIKE LOWER(CONCAT('%', :q, '%'))
            OR LOWER(u.email)         LIKE LOWER(CONCAT('%', :q, '%'))
         ORDER BY u.displayName
        """)
    List<User> searchByText(@Param("q") String q);
}
