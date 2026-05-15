package ae.gov.pdd.pettycash.expense.dto;

import jakarta.validation.constraints.NotNull;

import java.util.UUID;

public record ReassignSourceRequest(@NotNull UUID sourceId) {}
