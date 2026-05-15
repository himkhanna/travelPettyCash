package ae.gov.pdd.pettycash.trip.dto;

import ae.gov.pdd.pettycash.common.MoneyDto;

import java.util.List;
import java.util.UUID;

public record TripBalancesDto(
    UUID tripId,
    String scope,
    MoneyDto totalBudget,
    MoneyDto totalSpent,
    MoneyDto totalBalance,
    List<SourceBalanceDto> perSource
) {
    public record SourceBalanceDto(
        UUID sourceId,
        String sourceName,
        String sourceNameAr,
        MoneyDto received,
        MoneyDto spent,
        MoneyDto balance
    ) {}
}
