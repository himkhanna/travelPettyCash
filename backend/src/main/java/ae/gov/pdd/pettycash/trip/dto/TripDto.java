package ae.gov.pdd.pettycash.trip.dto;

import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripStatus;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record TripDto(
    UUID id,
    String name,
    String countryCode,
    String countryName,
    String currency,
    TripStatus status,
    UUID createdBy,
    UUID leaderId,
    UUID missionId,
    List<UUID> memberIds,
    MoneyDto totalBudget,
    Instant createdAt,
    Instant closedAt
) {
    public static TripDto from(Trip t) {
        return new TripDto(
            t.getId(),
            t.getName(),
            t.getCountryCode(),
            t.getCountryName(),
            t.getCurrency(),
            t.getStatus(),
            t.getCreatedById(),
            t.getLeaderId(),
            t.getMissionId(),
            t.getMemberIds().stream().sorted().toList(),
            MoneyDto.from(new Money(t.getTotalBudgetMinor(), t.getCurrency())),
            t.getCreatedAt(),
            t.getClosedAt()
        );
    }
}
