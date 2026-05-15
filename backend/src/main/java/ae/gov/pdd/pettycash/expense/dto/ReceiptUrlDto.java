package ae.gov.pdd.pettycash.expense.dto;

import java.time.Instant;

/** Presigned URL the client can hit directly to render the receipt image. */
public record ReceiptUrlDto(String url, Instant expiresAt) {}
