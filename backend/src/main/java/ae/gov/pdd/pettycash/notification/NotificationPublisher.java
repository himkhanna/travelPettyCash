package ae.gov.pdd.pettycash.notification;

import org.springframework.stereotype.Component;
import org.springframework.web.context.request.async.DeferredResult;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * In-memory pub/sub fan-out used by the long-poll endpoint. See CLAUDE.md §3 —
 * notifications are "in-app via WebSocket/polling first". Long-poll was chosen
 * over a streaming WebSocket because it fits Spring MVC, doesn't need session
 * affinity, and matches the polling-first stance.
 *
 * <p><b>Single-instance only.</b> If we ever scale the backend horizontally,
 * this must be replaced with a cross-node broadcast (Redis Pub/Sub or
 * Postgres LISTEN/NOTIFY). Out of scope for v1 (no horizontal scaling planned
 * before the Moro Hub deployment review).
 *
 * <p>Concurrency notes:
 * <ul>
 *   <li>The outer map is a {@link ConcurrentHashMap} keyed by recipient userId.</li>
 *   <li>Each waiter list is a {@link CopyOnWriteArrayList} — writes are rare
 *       (one per poll request); iteration on publish is the hot path.</li>
 *   <li>Subscribers are removed on completion/timeout via the DeferredResult
 *       lifecycle callbacks so the map doesn't leak.</li>
 * </ul>
 */
@Component
public class NotificationPublisher {

    private final ConcurrentMap<UUID, List<DeferredResult<List<NotificationController.NotificationView>>>> waiters =
        new ConcurrentHashMap<>();

    /**
     * Subscribe a deferred poll to wait for notifications addressed to {@code userId}.
     * The caller owns the {@link DeferredResult} lifetime; we just register it and
     * deregister on completion / timeout / error.
     */
    public void subscribe(UUID userId, DeferredResult<List<NotificationController.NotificationView>> dr) {
        List<DeferredResult<List<NotificationController.NotificationView>>> list =
            waiters.computeIfAbsent(userId, k -> new CopyOnWriteArrayList<>());
        list.add(dr);

        Runnable cleanup = () -> {
            list.remove(dr);
            // best-effort cleanup of empty bucket; safe even if a concurrent subscribe
            // re-adds, since computeIfAbsent will recreate.
            if (list.isEmpty()) {
                waiters.remove(userId, list);
            }
        };
        dr.onCompletion(cleanup);
        dr.onTimeout(cleanup);
        dr.onError(t -> cleanup.run());
    }

    /**
     * Publish a freshly-created notification. Resolves every DeferredResult
     * currently waiting for {@code userId} with a single-item list. If nothing
     * is waiting the publish is a no-op — the next poll will fetch via the
     * repository {@code since} filter.
     */
    public void publish(UUID userId, NotificationController.NotificationView view) {
        List<DeferredResult<List<NotificationController.NotificationView>>> list = waiters.get(userId);
        if (list == null || list.isEmpty()) return;
        // Snapshot to avoid concurrent-modification during setResult callbacks.
        List<DeferredResult<List<NotificationController.NotificationView>>> snapshot = new ArrayList<>(list);
        for (DeferredResult<List<NotificationController.NotificationView>> dr : snapshot) {
            if (!dr.isSetOrExpired()) {
                dr.setResult(List.of(view));
            }
        }
    }

    /** Test-only hook: number of currently-registered waiters for a user. */
    int waiterCount(UUID userId) {
        List<DeferredResult<List<NotificationController.NotificationView>>> list = waiters.get(userId);
        return list == null ? 0 : list.size();
    }
}
