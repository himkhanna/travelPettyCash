package ae.gov.pdd.pettycash.expense.dto;

import ae.gov.pdd.pettycash.common.MoneyDto;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.UUID;

/**
 * Mobile supplies the client-generated {@code id} per CLAUDE.md §11 so that
 * an offline-queued row keeps its identity once it lands. A replay with the
 * same id is idempotent.
 */
public record CreateExpenseRequest(
    @NotNull UUID id,
    @NotNull UUID sourceId,
    @NotBlank @Pattern(regexp = "[A-Z][A-Z0-9_]{1,31}") String categoryCode,
    @NotNull @Valid MoneyDto amount,
    @Min(1) int quantity,
    @Size(max = 500) String details,
    @NotNull Instant occurredAt,
    @Size(max = 256) String receiptObjectKey
) {}
