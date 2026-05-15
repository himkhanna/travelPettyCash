package ae.gov.pdd.pettycash.fund;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.util.UUID;

@Entity
@Table(name = "sources")
public class Source {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "name", nullable = false, unique = true, length = 128)
    private String name;

    @Column(name = "name_ar", nullable = false, length = 128)
    private String nameAr;

    @Column(name = "is_active", nullable = false)
    private boolean active = true;

    protected Source() {
        // JPA
    }

    public Source(UUID id, String name, String nameAr) {
        this.id = id;
        this.name = name;
        this.nameAr = nameAr;
    }

    public UUID getId() { return id; }
    public String getName() { return name; }
    public String getNameAr() { return nameAr; }
    public boolean isActive() { return active; }
}
