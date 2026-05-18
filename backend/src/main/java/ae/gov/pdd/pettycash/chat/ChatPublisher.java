package ae.gov.pdd.pettycash.chat;

import org.springframework.stereotype.Component;
import org.springframework.web.context.request.async.DeferredResult;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * In-memory fan-out for chat message long-poll. Mirror of
 * {@link ae.gov.pdd.pettycash.notification.NotificationPublisher}; same
 * single-instance caveat.
 *
 * <p>Keyed by threadId because chat subscribers care about a single thread
 * at a time (the open conversation in the mobile app).
 */
@Component
public class ChatPublisher {

    private final ConcurrentMap<UUID, List<DeferredResult<List<ChatController.MessageView>>>> waiters =
        new ConcurrentHashMap<>();

    public void subscribe(UUID threadId, DeferredResult<List<ChatController.MessageView>> dr) {
        List<DeferredResult<List<ChatController.MessageView>>> list =
            waiters.computeIfAbsent(threadId, k -> new CopyOnWriteArrayList<>());
        list.add(dr);

        Runnable cleanup = () -> {
            list.remove(dr);
            if (list.isEmpty()) {
                waiters.remove(threadId, list);
            }
        };
        dr.onCompletion(cleanup);
        dr.onTimeout(cleanup);
        dr.onError(t -> cleanup.run());
    }

    public void publish(UUID threadId, ChatController.MessageView view) {
        List<DeferredResult<List<ChatController.MessageView>>> list = waiters.get(threadId);
        if (list == null || list.isEmpty()) return;
        List<DeferredResult<List<ChatController.MessageView>>> snapshot = new ArrayList<>(list);
        for (DeferredResult<List<ChatController.MessageView>> dr : snapshot) {
            if (!dr.isSetOrExpired()) {
                dr.setResult(List.of(view));
            }
        }
    }

    int waiterCount(UUID threadId) {
        List<DeferredResult<List<ChatController.MessageView>>> list = waiters.get(threadId);
        return list == null ? 0 : list.size();
    }
}
