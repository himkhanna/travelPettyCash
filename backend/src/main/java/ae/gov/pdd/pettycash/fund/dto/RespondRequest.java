package ae.gov.pdd.pettycash.fund.dto;

import ae.gov.pdd.pettycash.fund.FundsStatus;
import jakarta.validation.constraints.NotNull;

/** Either {@code ACCEPTED} or {@code DECLINED}. {@code PENDING} is rejected. */
public record RespondRequest(@NotNull FundsStatus response) {}
