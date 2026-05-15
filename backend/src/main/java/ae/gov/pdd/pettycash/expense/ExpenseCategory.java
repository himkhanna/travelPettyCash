package ae.gov.pdd.pettycash.expense;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "expense_categories")
public class ExpenseCategory {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "code", nullable = false, unique = true, length = 32)
    private String code;

    @Column(name = "name_en", nullable = false, length = 64)
    private String nameEn;

    @Column(name = "name_ar", nullable = false, length = 64)
    private String nameAr;

    @Column(name = "icon_key", nullable = false, length = 32)
    private String iconKey;

    @Column(name = "is_active", nullable = false)
    private boolean active = true;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "deleted_at")
    private Instant deletedAt;

    protected ExpenseCategory() {
        // JPA
    }

    public ExpenseCategory(
        UUID id, String code, String nameEn, String nameAr, String iconKey
    ) {
        this.id = id;
        this.code = code;
        this.nameEn = nameEn;
        this.nameAr = nameAr;
        this.iconKey = iconKey;
    }

    public UUID getId() { return id; }
    public String getCode() { return code; }
    public String getNameEn() { return nameEn; }
    public String getNameAr() { return nameAr; }
    public String getIconKey() { return iconKey; }
    public boolean isActive() { return active; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getDeletedAt() { return deletedAt; }
}
