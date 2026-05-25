package ae.gov.pdd.pettycash.report.schedule;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public interface ReportScheduleRepository
    extends JpaRepository<ReportSchedule, UUID> {

    /** Schedules due to fire at or before {@code cutoff} — runner polls this. */
    List<ReportSchedule> findByActiveTrueAndNextRunAtLessThanEqual(Instant cutoff);

    /** Admin's "list all schedules" call. */
    List<ReportSchedule> findAllByOrderByCreatedAtDesc();
}
