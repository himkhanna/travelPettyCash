package ae.gov.pdd.pettycash.trip;

import ae.gov.pdd.pettycash.common.MoneyDto;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Set;
import java.util.UUID;

public final class TripDtos {

    public record TripView(
        UUID id, String name, String countryCode, String countryName, String currency,
        TripStatus status, UUID createdBy, UUID leaderId, Set<UUID> memberIds,
        MoneyDto totalBudget, String imageUrl,
        OffsetDateTime createdAt, OffsetDateTime closedAt
    ) {
        public static TripView from(Trip t) {
            return new TripView(t.getId(), t.getName(), t.getCountryCode(), t.getCountryName(),
                t.getCurrency(), t.getStatus(), t.getCreatedBy(), t.getLeaderId(),
                t.getMemberIds(), MoneyDto.from(t.getTotalBudget()), t.getImageUrl(),
                t.getCreatedAt(), t.getClosedAt());
        }
    }

    public record CreateTripRequest(
        String name,
        String countryCode,
        String countryName,
        String currency,
        UUID leaderId,
        List<UUID> memberIds,
        MoneyDto totalBudget,
        String imageUrl
    ) {}

    public record SourceBalance(
        UUID sourceId, String sourceName, String sourceNameAr,
        MoneyDto received, MoneyDto spent, MoneyDto balance
    ) {}

    public record TripBalances(
        UUID tripId, String scope,
        MoneyDto totalBudget, MoneyDto totalSpent, MoneyDto totalBalance,
        List<SourceBalance> perSource
    ) {}

    private TripDtos() {}
}
