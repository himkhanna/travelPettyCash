package ae.gov.pdd.pettycash.trip.dto;

import ae.gov.pdd.pettycash.common.MoneyDto;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

public record CreateTripRequest(
    @NotBlank @Size(max = 128) String name,
    @NotBlank @Pattern(regexp = "[A-Z]{2}") String countryCode,
    @NotBlank @Size(max = 128) String countryName,
    @NotBlank @Pattern(regexp = "[A-Z]{3}") String currency,
    @NotNull UUID leaderId,
    @NotNull List<UUID> memberIds,
    @NotNull MoneyDto totalBudget,
    /** Optional mission grouping — required by the CMS UI but server-side
     * nullable for backwards-compat with API clients that predate V007. */
    UUID missionId
) {}
