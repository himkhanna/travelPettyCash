package ae.gov.pdd.pettycash.expense.dto;

import ae.gov.pdd.pettycash.common.MoneyDto;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.Instant;

/** Every field is optional — only the set ones are applied. */
public record PatchExpenseRequest(
    @Pattern(regexp = "[A-Z][A-Z0-9_]{1,31}") String categoryCode,
    @Valid MoneyDto amount,
    @Min(1) Integer quantity,
    @Size(max = 500) String details,
    Instant occurredAt
) {}
