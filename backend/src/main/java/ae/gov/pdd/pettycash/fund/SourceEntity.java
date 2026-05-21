package ae.gov.pdd.pettycash.fund;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "sources")
public class SourceEntity {
    @Id private String id;
    @Column(nullable = false) private String name;
    @Column(name = "name_ar", nullable = false) private String nameAr;
    @Column(name = "is_active", nullable = false) private boolean active;

    protected SourceEntity() {}

    public String getId() { return id; }
    public String getName() { return name; }
    public String getNameAr() { return nameAr; }
    public boolean isActive() { return active; }
}
