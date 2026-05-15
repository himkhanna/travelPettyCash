package ae.gov.pdd.pettycash.user;

/** Roles match CLAUDE.md §5 / §7. Stored as VARCHAR per V001 check constraint. */
public enum UserRole {
    MEMBER,
    LEADER,
    ADMIN,
    SUPER_ADMIN;

    /** Spring Security expects "ROLE_" prefix on authorities. */
    public String authority() {
        return "ROLE_" + name();
    }
}
