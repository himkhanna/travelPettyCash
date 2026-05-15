package ae.gov.pdd.pettycash.fund.dto;

import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.FundsStatus;

import java.time.Instant;
import java.util.UUID;

public record AllocationDto(
    UUID id,
    UUID tripId,
    UUID fromUserId,
    UUID toUserId,
    UUID sourceId,
    MoneyDto amount,
    FundsStatus status,
    String note,
    Instant createdAt,
    Instant respondedAt
) {
    public static AllocationDto from(Allocation a) {
        return new AllocationDto(
            a.getId(),
            a.getTripId(),
            a.getFromUserId(),
            a.getToUserId(),
            a.getSourceId(),
            MoneyDto.from(new Money(a.getAmountMinor(), a.getCurrency())),
            a.getStatus(),
            a.getNote(),
            a.getCreatedAt(),
            a.getRespondedAt()
        );
    }
}
