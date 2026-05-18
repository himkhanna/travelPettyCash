package ae.gov.pdd.pettycash.expense;

import jakarta.persistence.*;

import java.util.Objects;
import java.util.UUID;

/**
 * Expense category. See CLAUDE.md §5. Admin can add new ones; soft-deletable via isActive.
 */
@Entity
@Table(name = "expense_category", indexes = {
    @Index(name = "idx_category_code", columnList = "code", unique = true)
})
public class ExpenseCategory {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "code", nullable = false, unique = true, length = 32)
    private String code;

    @Column(name = "name_en", nullable = false, length = 128)
    private String nameEn;

    @Column(name = "name_ar", nullable = false, length = 128)
    private String nameAr;

    @Column(name = "icon_key", nullable = false, length = 64)
    private String iconKey;

    @Column(name = "is_active", nullable = false)
    private boolean isActive = true;

    public ExpenseCategory() {}

    public ExpenseCategory(UUID id, String code, String nameEn, String nameAr, String iconKey, boolean isActive) {
        this.id = id;
        this.code = code;
        this.nameEn = nameEn;
        this.nameAr = nameAr;
        this.iconKey = iconKey;
        this.isActive = isActive;
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }
    public String getNameEn() { return nameEn; }
    public void setNameEn(String nameEn) { this.nameEn = nameEn; }
    public String getNameAr() { return nameAr; }
    public void setNameAr(String nameAr) { this.nameAr = nameAr; }
    public String getIconKey() { return iconKey; }
    public void setIconKey(String iconKey) { this.iconKey = iconKey; }
    public boolean isActive() { return isActive; }
    public void setActive(boolean active) { isActive = active; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof ExpenseCategory c)) return false;
        return Objects.equals(id, c.id);
    }

    @Override
    public int hashCode() { return Objects.hash(id); }
}
