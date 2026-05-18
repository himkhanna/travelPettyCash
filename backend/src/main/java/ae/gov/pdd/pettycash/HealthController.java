package ae.gov.pdd.pettycash;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Public /health endpoint per CLAUDE.md §9 (in addition to /actuator/health, which may be
 * non-public in tighter prod configs).
 */
@RestController
public class HealthController {
    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }
}
