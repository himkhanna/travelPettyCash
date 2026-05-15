package ae.gov.pdd.pettycash.fund;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class SourceController {

    private final SourceRepository sources;

    public SourceController(SourceRepository sources) {
        this.sources = sources;
    }

    @GetMapping("/sources")
    public List<SourceDto> list() {
        return sources.findByActiveTrueOrderByName().stream()
            .map(SourceDto::from)
            .toList();
    }

    public record SourceDto(UUID id, String name, String nameAr, boolean active) {
        static SourceDto from(Source s) {
            return new SourceDto(s.getId(), s.getName(), s.getNameAr(), s.isActive());
        }
    }
}
