package ae.gov.pdd.pettycash.expense.dto;

import ae.gov.pdd.pettycash.common.MoneyDto;

import java.util.List;

public record ExpenseSummaryDto(
    String groupBy,
    String scope,
    List<Row> rows
) {
    public record Row(
        String key,
        String labelEn,
        String labelAr,
        MoneyDto amount
    ) {}
}
