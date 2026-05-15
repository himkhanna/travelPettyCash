package ae.gov.pdd.pettycash.config;

import ae.gov.pdd.pettycash.user.UserRole;

import java.util.List;
import java.util.UUID;

/**
 * Canonical demo personas, mirrored from
 * {@code mobile/assets/demo/users.json}. Shared by every {@code Demo*Seeder}
 * so trip / allocation / expense seeders can reference users by username
 * without hard-coding UUIDs.
 */
public final class DemoPersonas {

    public record Persona(
        UUID id,
        String username,
        String displayName,
        String displayNameAr,
        String email,
        UserRole role
    ) {}

    public static final Persona AHMED = new Persona(
        UUID.fromString("00000000-0000-0000-0000-0000000a4d00"),
        "ahmed", "Ahmed Al Maktoum", "أحمد آل مكتوم",
        "ahmed@protocol.gov.ae", UserRole.MEMBER
    );
    public static final Persona FATIMA = new Persona(
        UUID.fromString("00000000-0000-0000-0000-0000000fa71a"),
        "fatima", "Fatima Al Hashimi", "فاطمة الهاشمي",
        "fatima@protocol.gov.ae", UserRole.LEADER
    );
    public static final Persona MOHAMMED = new Persona(
        UUID.fromString("00000000-0000-0000-0000-00000000ed01"),
        "mohammed", "Mohammed Ali", "محمد علي",
        "mohammed@protocol.gov.ae", UserRole.MEMBER
    );
    public static final Persona LAYLA = new Persona(
        UUID.fromString("00000000-0000-0000-0000-00000001a71a"),
        "layla", "Layla Al Mansouri", "ليلى المنصوري",
        "layla@protocol.gov.ae", UserRole.MEMBER
    );
    public static final Persona KHALID = new Persona(
        UUID.fromString("00000000-0000-0000-0000-0000000ad10d"),
        "khalid", "Khalid Al Suwaidi", "خالد السويدي",
        "khalid@protocol.gov.ae", UserRole.ADMIN
    );
    public static final Persona NOURA = new Persona(
        UUID.fromString("00000000-0000-0000-0000-00000000d061"),
        "noura", "Noura Al Falasi", "نورة الفلاسي",
        "noura@protocol.gov.ae", UserRole.SUPER_ADMIN
    );

    public static final List<Persona> ALL = List.of(
        AHMED, FATIMA, MOHAMMED, LAYLA, KHALID, NOURA
    );

    private DemoPersonas() {}
}
