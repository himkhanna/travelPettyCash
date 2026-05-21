package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.user.UserRole;

public record AuthenticatedUser(String id, String username, UserRole role) {}
