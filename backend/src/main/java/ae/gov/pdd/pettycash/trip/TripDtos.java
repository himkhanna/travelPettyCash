package ae.gov.pdd.pettycash.trip;

import ae.gov.pdd.pettycash.common.MoneyDto;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;
import java.util.Set;

public final class TripDtos {
    private TripDtos() {}

    public record TripView(
            String id,
            String name,
            String countryCode,
            String countryName,
            String currency,
            TripStatus status,
            String createdBy,
            String leaderId,
            Set<String> memberIds,
            MoneyDto totalBudget,
            OffsetDateTime createdAt,
            OffsetDateTime closedAt
    ) {
        public static TripView of(TripEntity t) {
            return new TripView(
                    t.getId(), t.getName(),
                    t.getCountryCode(), t.getCountryName(),
                    t.getCurrency(), t.getStatus(),
                    t.getCreatedBy(), t.getLeaderId(), t.getMemberIds(),
                    new MoneyDto(t.getTotalBudgetMinor(), t.getCurrency()),
                    t.getCreatedAt(), t.getClosedAt()
            );
        }
    }

    public record CreateTripRequest(
            @NotBlank String name,
            @NotBlank @Size(min = 2, max = 2) String countryCode,
            @NotBlank String countryName,
            @NotBlank @Size(min = 3, max = 3) String currency,
            @NotBlank String leaderId,
            @NotNull Set<String> memberIds,
            @NotNull MoneyDto totalBudget
    ) {}

    public record UpdateTripRequest(
            @NotBlank String name,
            @NotBlank String leaderId,
            @NotNull Set<String> memberIds
    ) {}
}
