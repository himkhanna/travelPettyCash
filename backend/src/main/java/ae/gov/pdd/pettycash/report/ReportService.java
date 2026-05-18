package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.audit.AuditService;
import ae.gov.pdd.pettycash.auth.CurrentUser;
import ae.gov.pdd.pettycash.common.ApiException;
import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseCategory;
import ae.gov.pdd.pettycash.expense.ExpenseCategoryRepository;
import ae.gov.pdd.pettycash.expense.ExpenseRepository;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.AllocationRepository;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.fund.SourceRepository;
import ae.gov.pdd.pettycash.storage.StorageService;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.user.Role;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.ByteArrayInputStream;
import java.net.URL;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Orchestrates report generation. See CLAUDE.md §10. The service:
 *
 * <ol>
 *   <li>Re-checks permissions per CLAUDE.md §7 (controller has the same guard).</li>
 *   <li>Loads the trip and supporting reference data.</li>
 *   <li>Delegates rendering to a {@link ReportGenerator} via the registry.</li>
 *   <li>Uploads the bytes to MinIO under {@code reports/{tripId}/{type}-{timestamp}.{ext}}.</li>
 *   <li>Writes a {@link ReportRecord} and an audit event with the file's SHA-256.</li>
 *   <li>Returns a 5-minute presigned GET URL.</li>
 * </ol>
 *
 * <p>Signing is deferred — see ADR-003. {@code POST /reports/{id}/sign} still
 * returns 501.
 */
@Service
public class ReportService {

    private static final Duration URL_TTL = Duration.ofMinutes(5);

    private final ReportTemplateRegistry registry;
    private final TripRepository trips;
    private final ExpenseRepository expenses;
    private final UserRepository users;
    private final SourceRepository sources;
    private final ExpenseCategoryRepository categories;
    private final AllocationRepository allocations;
    private final StorageService storage;
    private final ReportRecordRepository records;
    private final AuditService audit;
    private final CurrentUser current;

    public ReportService(ReportTemplateRegistry registry, TripRepository trips,
                         ExpenseRepository expenses, UserRepository users,
                         SourceRepository sources, ExpenseCategoryRepository categories,
                         AllocationRepository allocations, StorageService storage,
                         ReportRecordRepository records, AuditService audit, CurrentUser current) {
        this.registry = registry;
        this.trips = trips;
        this.expenses = expenses;
        this.users = users;
        this.sources = sources;
        this.categories = categories;
        this.allocations = allocations;
        this.storage = storage;
        this.records = records;
        this.audit = audit;
        this.current = current;
    }

    public record GenerateResult(UUID reportId, URL url, OffsetDateTime expiresAt, String sha256) {}

    @Transactional
    public GenerateResult generate(ReportRequest request) {
        Trip trip = trips.findById(request.tripId()).orElseThrow(
            () -> ApiException.notFound("TRIP_NOT_FOUND", "Trip " + request.tripId()));

        // Service-level re-check of CLAUDE.md §7 permissions. Controller has @PreAuthorize
        // but we never trust the client; the role gate runs here too.
        authorize(trip, request);

        // Resolve the effective userId for USER/DG scope filtering.
        UUID scopeUserId = resolveScopeUserId(request);

        ReportGenerator gen = registry.pick(request.type(), request.format());
        ReportContext ctx = loadContext(trip, scopeUserId);
        ReportRequest effective = new ReportRequest(
            request.tripId(), request.type(), request.format(), scopeUserId);
        byte[] bytes = gen.generate(effective, ctx);

        String sha256 = sha256Hex(bytes);
        String stamp = OffsetDateTime.now().toString().replaceAll("[^0-9TZ+\\-]", "_");
        String objectKey = String.format("reports/%s/%s-%s.%s",
            trip.getId(), request.type().name().toLowerCase(), stamp, request.format().extension());
        storage.putObject(objectKey, new ByteArrayInputStream(bytes), bytes.length,
            request.format().contentType());

        ReportRecord record = new ReportRecord();
        record.setId(UUID.randomUUID());
        record.setTripId(trip.getId());
        record.setType(request.type());
        record.setFormat(request.format());
        record.setScopeUserId(scopeUserId);
        record.setObjectKey(objectKey);
        record.setSha256(sha256);
        record.setCreatedBy(current.id());
        record.setCreatedAt(OffsetDateTime.now());
        ReportRecord saved = records.save(record);

        audit.recordEvent("ReportRecord", saved.getId().toString(), current.id(), "GENERATE",
            null,
            Map.of(
                "tripId", trip.getId().toString(),
                "type", request.type().name(),
                "format", request.format().name(),
                "objectKey", objectKey,
                "sha256", sha256
            ));

        URL url = storage.presignGet(objectKey, URL_TTL);
        return new GenerateResult(saved.getId(), url, OffsetDateTime.now().plus(URL_TTL), sha256);
    }

    /** CLAUDE.md §7 permission table — service-side re-check. */
    void authorize(Trip trip, ReportRequest request) {
        Role role = current.role();
        UUID me = current.id();
        switch (request.type()) {
            case USER -> {
                // Own only for MEMBER/LEADER; LEADER may also fetch any team member's;
                // ADMIN/SUPER_ADMIN may fetch any user. Brief: "USER → own".
                if (role == Role.SUPER_ADMIN || role == Role.ADMIN) return;
                UUID requested = request.userId();
                if (requested != null && !requested.equals(me)) {
                    // LEADER of this trip may see any member of the trip.
                    if (role == Role.LEADER && trip.getLeaderId().equals(me)
                        && trip.getMemberIds().contains(requested)) {
                        return;
                    }
                    throw ApiException.forbidden("FORBIDDEN", "USER report scope must be self");
                }
            }
            case TRIP -> {
                boolean isLeader = trip.getLeaderId().equals(me);
                if (!(role == Role.ADMIN || role == Role.SUPER_ADMIN
                    || (role == Role.LEADER && isLeader))) {
                    throw ApiException.forbidden("FORBIDDEN", "TRIP report requires LEADER or ADMIN");
                }
            }
            case FINANCE -> {
                if (role != Role.ADMIN) {
                    throw ApiException.forbidden("FORBIDDEN", "FINANCE letter is ADMIN-only");
                }
            }
            case DG -> {
                if (role != Role.SUPER_ADMIN) {
                    throw ApiException.forbidden("FORBIDDEN", "DG report is SUPER_ADMIN-only");
                }
            }
        }
    }

    private UUID resolveScopeUserId(ReportRequest request) {
        if (request.type() == ReportType.USER) {
            // Default to caller when no explicit user requested; otherwise honour authorize() result.
            return request.userId() != null ? request.userId() : current.id();
        }
        if (request.type() == ReportType.DG) {
            // DG report may optionally filter to a single user.
            return request.userId();
        }
        return null;
    }

    private ReportContext loadContext(Trip trip, UUID scopeUserId) {
        List<Expense> all = expenses.findByTripId(trip.getId());
        List<Expense> filtered = scopeUserId == null
            ? all
            : all.stream().filter(e -> scopeUserId.equals(e.getUserId())).toList();
        Map<UUID, User> usersById = users.findAll().stream()
            .collect(Collectors.toMap(User::getId, Function.identity(), (a, b) -> a, LinkedHashMap::new));
        Map<UUID, Source> sourcesById = sources.findAll().stream()
            .collect(Collectors.toMap(Source::getId, Function.identity(), (a, b) -> a, LinkedHashMap::new));
        Map<String, ExpenseCategory> catByCode = categories.findAll().stream()
            .collect(Collectors.toMap(ExpenseCategory::getCode, Function.identity(), (a, b) -> a, LinkedHashMap::new));
        List<Allocation> allocs = allocations.findByTripId(trip.getId());
        return new ReportContext(trip, filtered, usersById, sourcesById, catByCode, allocs);
    }

    private String sha256Hex(byte[] bytes) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(md.digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }
}
