package ae.gov.pdd.pettycash.receipt;

import ae.gov.pdd.pettycash.common.MoneyDto;

import java.time.OffsetDateTime;

/**
 * OCR extraction result. Money is minor units + ISO code (CLAUDE.md §9).
 * Shape is shape-stable: mobile builds against this contract. See ADR-005.
 */
public record ReceiptScanResult(
    String vendor,
    MoneyDto amount,
    int quantity,
    String categoryHint,
    OffsetDateTime occurredAt,
    double confidence,
    String warning
) {}
