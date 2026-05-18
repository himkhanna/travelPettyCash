package ae.gov.pdd.pettycash.fund;

import jakarta.persistence.*;

import java.util.Objects;
import java.util.UUID;

/**
 * Funding source — e.g. Zabeel Office, Ministry of External Affairs. See CLAUDE.md §1, §5.
 * Seeded; Admin-managed only.
 */
@Entity
@Table(name = "fund_source")
public class Source {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "name", nullable = false, length = 128)
    private String name;

    @Column(name = "name_ar", nullable = false, length = 128)
    private String nameAr;

    @Column(name = "is_active", nullable = false)
    private boolean isActive = true;

    public Source() {}

    public Source(UUID id, String name, String nameAr, boolean isActive) {
        this.id = id;
        this.name = name;
        this.nameAr = nameAr;
        this.isActive = isActive;
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getNameAr() { return nameAr; }
    public void setNameAr(String nameAr) { this.nameAr = nameAr; }
    public boolean isActive() { return isActive; }
    public void setActive(boolean active) { isActive = active; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Source s)) return false;
        return Objects.equals(id, s.id);
    }

    @Override
    public int hashCode() { return Objects.hash(id); }
}
