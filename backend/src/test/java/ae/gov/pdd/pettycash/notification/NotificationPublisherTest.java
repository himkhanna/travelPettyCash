package ae.gov.pdd.pettycash.notification;

import org.junit.jupiter.api.Test;
import org.springframework.web.context.request.async.DeferredResult;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Pure unit test for NotificationPublisher fan-out. No Spring context.
 */
class NotificationPublisherTest {

    @Test
    void publishOnlyResolvesMatchingSubscriber() {
        NotificationPublisher pub = new NotificationPublisher();
        UUID alice = UUID.randomUUID();
        UUID bob = UUID.randomUUID();

        DeferredResult<List<NotificationController.NotificationView>> aliceDr = new DeferredResult<>(10_000L);
        DeferredResult<List<NotificationController.NotificationView>> bobDr = new DeferredResult<>(10_000L);
        pub.subscribe(alice, aliceDr);
        pub.subscribe(bob, bobDr);

        assertThat(pub.waiterCount(alice)).isEqualTo(1);
        assertThat(pub.waiterCount(bob)).isEqualTo(1);

        NotificationController.NotificationView v = new NotificationController.NotificationView(
            UUID.randomUUID(), alice, NotificationType.TRANSFER_RECEIVED, Map.of("k", "v"),
            true, NotificationState.UNREAD, OffsetDateTime.now());

        pub.publish(alice, v);

        // Alice resolved; Bob still pending.
        assertThat(aliceDr.hasResult()).isTrue();
        assertThat((List<?>) aliceDr.getResult()).hasSize(1);
        assertThat(bobDr.hasResult()).isFalse();
    }

    @Test
    void publishWithNoSubscribersIsNoop() {
        NotificationPublisher pub = new NotificationPublisher();
        UUID nobody = UUID.randomUUID();
        // Should not throw.
        pub.publish(nobody, new NotificationController.NotificationView(
            UUID.randomUUID(), nobody, NotificationType.TRIP_ASSIGNED, Map.of(),
            false, NotificationState.UNREAD, OffsetDateTime.now()));
        assertThat(pub.waiterCount(nobody)).isZero();
    }

    @Test
    void publishToSameUserResolvesAllWaiters() {
        // Two pollers for the same user (e.g. mobile app open on two devices) should
        // both fire on a single publish.
        NotificationPublisher pub = new NotificationPublisher();
        UUID u = UUID.randomUUID();
        DeferredResult<List<NotificationController.NotificationView>> a = new DeferredResult<>(10_000L);
        DeferredResult<List<NotificationController.NotificationView>> b = new DeferredResult<>(10_000L);
        pub.subscribe(u, a);
        pub.subscribe(u, b);
        assertThat(pub.waiterCount(u)).isEqualTo(2);

        pub.publish(u, new NotificationController.NotificationView(
            UUID.randomUUID(), u, NotificationType.EXPENSE_QUERY, Map.of(),
            false, NotificationState.UNREAD, OffsetDateTime.now()));

        assertThat(a.hasResult()).isTrue();
        assertThat(b.hasResult()).isTrue();
    }
}
