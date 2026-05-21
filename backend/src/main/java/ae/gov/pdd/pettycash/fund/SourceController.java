package ae.gov.pdd.pettycash.fund;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

interface SourceRepository extends JpaRepository<SourceEntity, String> {}

@RestController
@RequestMapping("/api/v1/sources")
class SourceController {
    private final SourceRepository sources;

    SourceController(SourceRepository sources) { this.sources = sources; }

    public record SourceView(String id, String name, String nameAr, boolean active) {
        static SourceView of(SourceEntity s) {
            return new SourceView(s.getId(), s.getName(), s.getNameAr(), s.isActive());
        }
    }

    @GetMapping
    public List<SourceView> list() {
        return sources.findAll().stream().map(SourceView::of).toList();
    }
}
