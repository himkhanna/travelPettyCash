package ae.gov.pdd.pettycash.search;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.mission.Mission;
import ae.gov.pdd.pettycash.mission.MissionRepository;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.List;

/**
 * Backs the admin top-bar search box (⌘K). Returns a flat, typed list of
 * hits across trips + users + missions. Admin / super-admin only — leaders
 * and members don't need to search the whole org.
 *
 * <p>Implementation is intentionally a plain ILIKE across three tables —
 * Postgres handles this comfortably at the scale a single Protocol
 * department operates at. Trigram or full-text indexing can be layered
 * later without changing the API shape.
 */
@RestController
@RequestMapping("/api/v1/search")
class SearchController {

    private final TripRepository trips;
    private final UserRepository users;
    private final MissionRepository missions;

    SearchController(
        TripRepository trips,
        UserRepository users,
        MissionRepository missions
    ) {
        this.trips = trips;
        this.users = users;
        this.missions = missions;
    }

    @GetMapping
    public SearchResponse search(
        @RequestParam("q") String q,
        @RequestParam(name = "limit", defaultValue = "8") int limit,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        if (caller.role() != UserRole.ADMIN
            && caller.role() != UserRole.SUPER_ADMIN) {
            throw new ApiException(
                HttpStatus.FORBIDDEN, "auth/forbidden", "Forbidden",
                "Global search is admin-only."
            );
        }
        final String query = q == null ? "" : q.trim();
        if (query.length() < 2) {
            return new SearchResponse(query, List.of());
        }
        final int perBucket = Math.max(1, Math.min(limit, 20));

        final List<SearchHit> hits = new ArrayList<>();
        for (Trip t : trips.searchByText(query).stream().limit(perBucket).toList()) {
            hits.add(new SearchHit(
                "trip",
                t.getId().toString(),
                t.getName(),
                t.getCountryName() + " · " + t.getCurrency(),
                "/cms/trips/" + t.getId()
            ));
        }
        for (Mission m : missions.searchByText(query).stream().limit(perBucket).toList()) {
            hits.add(new SearchHit(
                "mission",
                m.getId().toString(),
                m.getName(),
                m.getCode(),
                "/cms/missions"
            ));
        }
        for (User u : users.searchByText(query).stream().limit(perBucket).toList()) {
            hits.add(new SearchHit(
                "user",
                u.getId().toString(),
                u.getDisplayName(),
                "@" + u.getUsername() + " · " + u.getRole(),
                // Carry the user id so the Users screen can open the
                // edit dialog directly for that row.
                "/cms/users?focus=" + u.getId()
            ));
        }
        return new SearchResponse(query, hits);
    }

    public record SearchResponse(String query, List<SearchHit> hits) {}

    public record SearchHit(
        String type,
        String id,
        String label,
        String subtitle,
        String link
    ) {}
}
