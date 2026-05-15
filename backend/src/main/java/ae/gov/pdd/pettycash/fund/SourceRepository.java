package ae.gov.pdd.pettycash.fund;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface SourceRepository extends JpaRepository<Source, UUID> {
    List<Source> findByActiveTrueOrderByName();
    boolean existsByName(String name);
}
