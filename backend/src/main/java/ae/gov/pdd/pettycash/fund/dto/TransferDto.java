package ae.gov.pdd.pettycash.fund.dto;

import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.fund.FundsStatus;
import ae.gov.pdd.pettycash.fund.Transfer;

import java.time.Instant;
import java.util.UUID;

public record TransferDto(
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
    public static TransferDto from(Transfer t) {
        return new TransferDto(
            t.getId(),
            t.getTripId(),
            t.getFromUserId(),
            t.getToUserId(),
            t.getSourceId(),
            MoneyDto.from(new Money(t.getAmountMinor(), t.getCurrency())),
            t.getStatus(),
            t.getNote(),
            t.getCreatedAt(),
            t.getRespondedAt()
        );
    }
}
