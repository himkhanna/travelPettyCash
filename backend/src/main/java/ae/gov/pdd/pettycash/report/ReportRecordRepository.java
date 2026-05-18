package ae.gov.pdd.pettycash.report;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface ReportRecordRepository extends JpaRepository<ReportRecord, UUID> {
}
