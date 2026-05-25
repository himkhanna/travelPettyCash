package ae.gov.pdd.pettycash.mission;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface MissionRepository extends JpaRepository<Mission, UUID> {
    Optional<Mission> findByCode(String code);
    boolean existsByCode(String code);

    /** Count direct children of a mission — used by delete guard. */
    long countByParentMissionId(UUID parentMissionId);

    /** Case-insensitive name/code search for global search. */
    @Query("""
        SELECT m FROM Mission m
         WHERE LOWER(m.name)    LIKE LOWER(CONCAT('%', :q, '%'))
            OR LOWER(m.nameAr)  LIKE LOWER(CONCAT('%', :q, '%'))
            OR LOWER(m.code)    LIKE LOWER(CONCAT('%', :q, '%'))
         ORDER BY m.name
        """)
    List<Mission> searchByText(@Param("q") String q);
}
