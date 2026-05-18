package ae.gov.pdd.pettycash.trip.dto;

import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

/**
 * Optional-field patch. Any null field means "leave unchanged"; the
 * {@code memberIds} list is taken as the new full membership (not a delta —
 * passing {@code []} clears every member).
 */
public record PatchTripRequest(
    @Size(max = 128) String name,
    UUID leaderId,
    List<UUID> memberIds
) {}
