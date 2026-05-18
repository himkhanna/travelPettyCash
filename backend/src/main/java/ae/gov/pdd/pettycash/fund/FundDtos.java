package ae.gov.pdd.pettycash.fund;

import ae.gov.pdd.pettycash.common.MoneyDto;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

public final class FundDtos {

    public record AllocationView(
        UUID id, UUID tripId, UUID fromUserId, UUID toUserId, UUID sourceId,
        MoneyDto amount, AllocationStatus status, String note,
        OffsetDateTime createdAt, OffsetDateTime respondedAt
    ) {
        public static AllocationView from(Allocation a) {
            return new AllocationView(a.getId(), a.getTripId(), a.getFromUserId(), a.getToUserId(),
                a.getSourceId(), MoneyDto.from(a.getAmount()), a.getStatus(), a.getNote(),
                a.getCreatedAt(), a.getRespondedAt());
        }
    }

    public record AllocationDraft(UUID toUserId, UUID sourceId, MoneyDto amount, String note) {}

    public record CreateAllocationsRequest(List<AllocationDraft> allocations) {}

    public record RespondRequest(String action) {} // ACCEPT | DECLINE

    public record CreateTransferRequest(UUID id, UUID toUserId, UUID sourceId, MoneyDto amount, String note) {}

    public record TransferView(
        UUID id, UUID tripId, UUID fromUserId, UUID toUserId, UUID sourceId,
        MoneyDto amount, AllocationStatus status, String note,
        OffsetDateTime createdAt, OffsetDateTime respondedAt
    ) {
        public static TransferView from(Transfer t) {
            return new TransferView(t.getId(), t.getTripId(), t.getFromUserId(), t.getToUserId(),
                t.getSourceId(), MoneyDto.from(t.getAmount()), t.getStatus(), t.getNote(),
                t.getCreatedAt(), t.getRespondedAt());
        }
    }

    public record SourceView(UUID id, String name, String nameAr, boolean isActive) {
        public static SourceView from(Source s) {
            return new SourceView(s.getId(), s.getName(), s.getNameAr(), s.isActive());
        }
    }

    private FundDtos() {}
}
