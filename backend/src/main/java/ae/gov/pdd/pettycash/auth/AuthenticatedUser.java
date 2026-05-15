package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.user.UserRole;

import java.util.UUID;

/** Principal stored on the SecurityContext after JWT verification. */
public record AuthenticatedUser(UUID userId, String username, UserRole role) {}
