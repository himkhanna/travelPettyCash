package ae.gov.pdd.pettycash.fund.dto;

import ae.gov.pdd.pettycash.common.MoneyDto;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;

import java.util.UUID;

public record CreateTransferRequest(
    @NotNull UUID toUserId,
    @NotNull UUID sourceId,
    @NotNull @Valid MoneyDto amount,
    String note
) {}
