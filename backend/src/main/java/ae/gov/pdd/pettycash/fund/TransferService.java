package ae.gov.pdd.pettycash.fund;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.fund.dto.CreateTransferRequest;
import ae.gov.pdd.pettycash.fund.dto.TransferDto;
import ae.gov.pdd.pettycash.notification.NotificationRefType;
import ae.gov.pdd.pettycash.notification.NotificationService;
import ae.gov.pdd.pettycash.notification.NotificationType;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.trip.TripStatus;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class TransferService {

    private final TransferRepository transfers;
    private final TripRepository trips;
    private final SourceRepository sources;
    private final UserRepository users;
    private final NotificationService notifications;
    private final Clock clock;

    @Autowired
    public TransferService(
        TransferRepository transfers,
        TripRepository trips,
        SourceRepository sources,
        UserRepository users,
        NotificationService notifications
    ) {
        this(transfers, trips, sources, users, notifications, Clock.systemUTC());
    }

    TransferService(
        TransferRepository transfers,
        TripRepository trips,
        SourceRepository sources,
        UserRepository users,
        NotificationService notifications,
        Clock clock
    ) {
        this.transfers = transfers;
        this.trips = trips;
        this.sources = sources;
        this.users = users;
        this.notifications = notifications;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public List<TransferDto> list(UUID tripId, AuthenticatedUser caller) {
        Trip trip = loadAccessibleTrip(tripId, caller);
        return transfers.findByTripIdOrderByCreatedAtAsc(trip.getId())
            .stream().map(TransferDto::from).toList();
    }

    @Transactional
    public TransferDto create(
        UUID tripId,
        CreateTransferRequest req,
        AuthenticatedUser caller
    ) {
        Trip trip = trips.findById(tripId)
            .orElseThrow(() -> notFound(tripId));
        if (trip.getStatus() == TripStatus.CLOSED) {
            throw badRequest("trips/closed", "Trip is closed; transfers are not allowed.");
        }
        // Only trip participants can transfer. Admins can't initiate transfers —
        // that's a peer flow per CLAUDE.md §7.
        if (caller.role() == UserRole.ADMIN || caller.role() == UserRole.SUPER_ADMIN) {
            throw forbidden("Admins cannot initiate peer transfers.");
        }
        boolean isParticipant = trip.getLeaderId().equals(caller.userId())
            || trip.getMemberIds().contains(caller.userId());
        if (!isParticipant) {
            throw notFound(tripId);
        }
        if (req.toUserId().equals(caller.userId())) {
            throw badRequest("transfers/self-recipient", "Cannot transfer to yourself.");
        }
        // Recipient must be a participant of the same trip.
        boolean toIsParticipant = trip.getLeaderId().equals(req.toUserId())
            || trip.getMemberIds().contains(req.toUserId());
        if (!toIsParticipant) {
            throw badRequest(
                "transfers/non-participant-recipient",
                "Recipient is not a participant of this trip."
            );
        }
        if (!req.amount().currency().equals(trip.getCurrency())) {
            throw badRequest(
                "transfers/currency-mismatch",
                "Transfer currency must equal trip currency (" + trip.getCurrency() + ")"
            );
        }
        if (req.amount().amount() <= 0) {
            throw badRequest("transfers/non-positive-amount", "amount must be > 0");
        }
        if (!sources.existsById(req.sourceId())) {
            throw badRequest("transfers/unknown-source", "Source not found: " + req.sourceId());
        }
        if (!users.existsById(req.toUserId())) {
            throw badRequest("transfers/unknown-recipient", "Recipient not found: " + req.toUserId());
        }

        Transfer t = new Transfer(
            UUID.randomUUID(),
            trip.getId(),
            caller.userId(),
            req.toUserId(),
            req.sourceId(),
            req.amount().amount(),
            req.amount().currency(),
            FundsStatus.PENDING,
            req.note()
        );
        transfers.save(t);

        // TRANSFER_RECEIVED on the recipient.
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("transferId", t.getId().toString());
        payload.put("tripId", t.getTripId().toString());
        payload.put("sourceId", t.getSourceId().toString());
        payload.put("amountMinor", t.getAmountMinor());
        payload.put("currency", t.getCurrency());
        payload.put("fromUserId", t.getFromUserId().toString());
        if (t.getNote() != null) payload.put("note", t.getNote());
        notifications.fanOut(
            NotificationType.TRANSFER_RECEIVED,
            true,
            NotificationRefType.TRANSFER,
            t.getId(),
            payload,
            List.of(t.getToUserId())
        );

        return TransferDto.from(t);
    }

    @Transactional
    public TransferDto respond(UUID id, FundsStatus response, AuthenticatedUser caller) {
        Transfer row = transfers.findById(id)
            .orElseThrow(() -> new ApiException(
                HttpStatus.NOT_FOUND,
                "transfers/not-found",
                "Transfer not found",
                "No transfer with id " + id
            ));
        if (!row.getToUserId().equals(caller.userId())) {
            throw forbidden("Only the recipient may respond.");
        }
        try {
            row.respond(response, clock.instant());
        } catch (IllegalStateException e) {
            throw badRequest("transfers/already-responded", e.getMessage());
        } catch (IllegalArgumentException e) {
            throw badRequest("transfers/invalid-response", e.getMessage());
        }
        // Flip the recipient's inbox notification to ACTED.
        notifications.markActedByRef(NotificationRefType.TRANSFER, row.getId());
        // Tell the sender what happened — TRANSFER_ACCEPTED on accept; the
        // declined path is a passive non-actionable note.
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("transferId", row.getId().toString());
        payload.put("tripId", row.getTripId().toString());
        payload.put("byUserId", row.getToUserId().toString());
        payload.put("amountMinor", row.getAmountMinor());
        payload.put("currency", row.getCurrency());
        payload.put("response", response.name());
        notifications.fanOut(
            NotificationType.TRANSFER_ACCEPTED,
            false,
            NotificationRefType.TRANSFER,
            row.getId(),
            payload,
            List.of(row.getFromUserId())
        );
        return TransferDto.from(row);
    }

    private Trip loadAccessibleTrip(UUID tripId, AuthenticatedUser caller) {
        Trip t = trips.findById(tripId).orElseThrow(() -> notFound(tripId));
        boolean isAdmin = caller.role() == UserRole.ADMIN
            || caller.role() == UserRole.SUPER_ADMIN;
        boolean isParticipant = t.getLeaderId().equals(caller.userId())
            || t.getMemberIds().contains(caller.userId());
        if (!isAdmin && !isParticipant) {
            throw notFound(tripId);
        }
        return t;
    }

    private static ApiException notFound(UUID tripId) {
        return new ApiException(
            HttpStatus.NOT_FOUND,
            "trips/not-found",
            "Trip not found",
            "No trip with id " + tripId + " is accessible to this user."
        );
    }

    private static ApiException badRequest(String code, String detail) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, "Bad request", detail);
    }

    private static ApiException forbidden(String detail) {
        return new ApiException(
            HttpStatus.FORBIDDEN,
            "auth/forbidden",
            "Forbidden",
            detail
        );
    }
}
