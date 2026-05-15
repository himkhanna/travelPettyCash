package ae.gov.pdd.pettycash.fund.dto;

import ae.gov.pdd.pettycash.common.MoneyDto;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

/** Bulk-create: Admin → trip-pool or Leader → members in one transaction. */
public record CreateAllocationsRequest(
    @NotEmpty @Valid @Size(max = 50) List<Row> rows
) {
    public record Row(
        @NotNull UUID toUserId,
        @NotNull UUID sourceId,
        @NotNull @Valid MoneyDto amount,
        String note
    ) {}
}
