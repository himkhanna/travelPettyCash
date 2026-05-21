package ae.gov.pdd.pettycash.category;

import jakarta.persistence.*;

@Entity
@Table(name = "expense_categories")
public class CategoryEntity {
    @Id private String id;
    @Column(unique = true, nullable = false) private String code;
    @Column(name = "name_en", nullable = false) private String nameEn;
    @Column(name = "name_ar", nullable = false) private String nameAr;
    @Column(name = "icon_key", nullable = false) private String iconKey;
    @Column(name = "is_active", nullable = false) private boolean active;

    protected CategoryEntity() {}

    public CategoryEntity(String id, String code, String nameEn, String nameAr,
                          String iconKey, boolean active) {
        this.id = id; this.code = code; this.nameEn = nameEn;
        this.nameAr = nameAr; this.iconKey = iconKey; this.active = active;
    }

    public String getId() { return id; }
    public String getCode() { return code; }
    public String getNameEn() { return nameEn; }
    public String getNameAr() { return nameAr; }
    public String getIconKey() { return iconKey; }
    public boolean isActive() { return active; }
    public void setActive(boolean v) { this.active = v; }
}
