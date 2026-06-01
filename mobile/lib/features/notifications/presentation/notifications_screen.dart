import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/pdd_primitives.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../application/notifications_providers.dart';
import '../domain/notification.dart';

/// Screen-inventory #16 — Notifications list with ACCEPT / DECLINE on
/// actionable items, swipe-to-delete, and DELETE ALL.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AppNotification>> async = ref.watch(
      myNotificationsProvider,
    );

    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final int pending = async.maybeWhen(
      data: (List<AppNotification> list) => list
          .where((AppNotification n) =>
              n.actionable && n.state != NotificationState.acted)
          .length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            PddTopBar(
              user: me,
              leadingBack: true,
              onBack: () => Navigator.of(context).canPop()
                  ? Navigator.of(context).pop()
                  : context.go('/m/trips'),
              title: 'Inbox',
              subtitle: pending > 0
                  ? '$pending pending'
                  : 'All caught up',
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Center(child: Text('Error: $e')),
                data: (List<AppNotification> list) {
                  if (list.isEmpty) {
                    return const PddEmptyState(
                      icon: Icons.notifications_none_outlined,
                      title: 'All caught up',
                      body: 'You have no new notifications.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: list.length,
                    itemBuilder: (BuildContext context, int i) {
                      final AppNotification n = list[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Dismissible(
                          key: ValueKey<String>(n.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: AlignmentDirectional.centerEnd,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.red,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.delete,
                                color: Colors.white),
                          ),
                          onDismissed: (_) => ref
                              .read(notificationsRepositoryProvider)
                              .delete(n.id),
                          child: _NotificationCard(notification: n),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  const _NotificationCard({required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DemoStore store = ref.read(demoStoreProvider);
    final bool unread = notification.state == NotificationState.unread;
    final bool pendingAction =
        notification.actionable &&
        notification.state != NotificationState.acted;

    return Material(
      color: unread ? AppColors.cream : AppColors.surfaceCard,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: InkWell(
        onTap: () => _handleTap(context, ref),
        borderRadius: const BorderRadius.all(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _TypeBadge(type: notification.type),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _timeLabel(notification.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  if (unread)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.outflow,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _body(store, notification),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (pendingAction) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                // Notifications are display-only. Accept / Decline lives on
                // the trip dashboard's pending-funds banner — single source
                // of truth, no chance of a stale Accept button.
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: AppColors.brand,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _ctaHint(notification),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.brand,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Tap routes the user to wherever they can actually do something:
  ///  - EXPENSE_QUERY → the expense detail (reply in the thread)
  ///  - Anything carrying a tripId → that trip's dashboard, where the
  ///    PendingAllocationsBanner is the single owner of accept/decline.
  /// Marking-read happens regardless so the inbox count goes down.
  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    final bool wasUnread = notification.state == NotificationState.unread;
    if (wasUnread) {
      await ref
          .read(notificationsRepositoryProvider)
          .markRead(notification.id);
      // Refresh the inbox so the unread dot disappears immediately rather
      // than waiting on the next 5s poll.
      ref.invalidate(myNotificationsProvider);
    }
    if (!context.mounted) return;

    if (notification.type == NotificationType.expenseQuery) {
      final String? tripId = notification.payload['tripId'] as String?;
      final String? expenseId = notification.payload['expenseId'] as String?;
      if (tripId != null && expenseId != null) {
        context.go('/m/trips/$tripId/expenses/$expenseId');
        return;
      }
    }

    if (notification.type == NotificationType.chatMessage) {
      final String? tripId = notification.payload['tripId'] as String?;
      final String? threadId = notification.payload['threadId'] as String?;
      if (tripId != null && threadId != null) {
        context.go('/m/trips/$tripId/chat/$threadId');
        return;
      }
    }

    final String? tripId = notification.payload['tripId'] as String?;
    if (tripId != null) {
      context.go('/m/trips/$tripId/dashboard');
    }
  }

  /// Inline hint shown beneath the body for notifications that still need
  /// the user to do something. Keeps the card display-only while pointing
  /// them at the right surface to act.
  String _ctaHint(AppNotification n) {
    switch (n.type) {
      case NotificationType.allocationReceived:
      case NotificationType.transferReceived:
        return 'Open trip to accept';
      case NotificationType.expenseQuery:
        return 'Open expense to reply';
      case NotificationType.chatMessage:
        return 'Open chat to reply';
      default:
        return 'Open trip';
    }
  }

  String _body(DemoStore store, AppNotification n) {
    switch (n.type) {
      case NotificationType.allocationReceived:
        final String fromName = _userName(
          store,
          n.payload['fromUserId'] as String?,
        );
        final Money amt = _money(n);
        return '$fromName has allocated ${amt.format()} to you for ${_sourceName(store, n)}.';
      case NotificationType.transferReceived:
        final String fromName = _userName(
          store,
          n.payload['fromUserId'] as String?,
        );
        final Money amt = _money(n);
        return '$fromName has transferred ${amt.format()} to you${n.payload['note'] != null ? '. "${n.payload['note']}"' : '.'}';
      case NotificationType.transferAccepted:
        final String byName = _userName(
          store,
          n.payload['byUserId'] as String?,
        );
        final Money amt = _money(n);
        return '$byName has ${n.payload['response'] == 'declined' ? 'declined' : 'accepted'} your transfer of ${amt.format()}.';
      case NotificationType.tripAssigned:
        return 'You have been added to a new trip.';
      case NotificationType.tripClosed:
        return 'A trip you participated in has been closed.';
      case NotificationType.expenseQuery:
        // Server writes the comment text into `snippet` (truncated to
        // 140 chars). `question` was the older field name; kept as a
        // fallback for any rows still in flight.
        final String byName = _userName(
          store,
          n.payload['authorId'] as String?,
        );
        final String text = (n.payload['snippet'] as String?) ??
            (n.payload['question'] as String?) ??
            '';
        final String tripName = (n.payload['tripName'] as String?) ?? 'a trip';
        return '$byName mentioned you on an expense in $tripName: '
            '"$text"';
      case NotificationType.reportReady:
        final String tripName =
            (n.payload['tripName'] as String?) ?? 'a trip';
        final String reason =
            (n.payload['reason'] as String?) ?? 'manual';
        if (reason == 'trip-closed') {
          return 'Trip closed — $tripName · open the trip to generate '
              'and sign the finance letter.';
        }
        return 'Report ready for $tripName · open the trip to download.';
      case NotificationType.chatMessage:
        final String byName = _userName(
          store,
          n.payload['senderId'] as String?,
        );
        final String tripName =
            (n.payload['tripName'] as String?) ?? 'a trip';
        final String snip = (n.payload['snippet'] as String?) ?? '';
        return snip.isEmpty
            ? '$byName sent a message in $tripName.'
            : '$byName in $tripName: "$snip"';
    }
  }

  String _userName(DemoStore store, String? id) {
    if (id == null) return 'Someone';
    try {
      return store.userById(id).displayName;
    } catch (_) {
      return 'Someone';
    }
  }

  String _sourceName(DemoStore store, AppNotification n) {
    final String? sid = n.payload['sourceId'] as String?;
    if (sid == null) return 'the source';
    try {
      return store.sourceById(sid).name;
    } catch (_) {
      return 'the source';
    }
  }

  Money _money(AppNotification n) {
    final int minor = (n.payload['amountMinor'] as int?) ?? 0;
    final String code = (n.payload['currency'] as String?) ?? 'SAR';
    return Money(minor, code);
  }

  String _timeLabel(DateTime t) {
    final DateTime now = DateTime.now();
    final Duration d = now.difference(t);
    if (d.inMinutes < 1) return 'JUST NOW';
    if (d.inHours < 1) return '${d.inMinutes}M AGO';
    if (d.inDays < 1) return '${d.inHours}H AGO';
    if (d.inDays < 7) return '${d.inDays}D AGO';
    return DateFormat('d MMM').format(t).toUpperCase();
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final NotificationType type;

  @override
  Widget build(BuildContext context) {
    final ({Color color, IconData icon, String label}) cfg = switch (type) {
      NotificationType.allocationReceived => (
        color: AppColors.goldOlive,
        icon: Icons.account_balance_wallet_outlined,
        label: 'ALLOCATION',
      ),
      NotificationType.transferReceived => (
        color: AppColors.brandBrown,
        icon: Icons.swap_horiz,
        label: 'TRANSFER',
      ),
      NotificationType.transferAccepted => (
        color: AppColors.success,
        icon: Icons.check_circle_outline,
        label: 'ACCEPTED',
      ),
      NotificationType.tripAssigned => (
        color: AppColors.brandBrown,
        icon: Icons.flight,
        label: 'TRIP',
      ),
      NotificationType.tripClosed => (
        color: AppColors.textSecondary,
        icon: Icons.lock_outline,
        label: 'CLOSED',
      ),
      NotificationType.expenseQuery => (
        color: AppColors.warning,
        icon: Icons.help_outline,
        label: 'QUERY',
      ),
      NotificationType.reportReady => (
        color: AppColors.brand,
        icon: Icons.description_outlined,
        label: 'REPORT',
      ),
      NotificationType.chatMessage => (
        color: AppColors.brandBrown,
        icon: Icons.chat_bubble_outline,
        label: 'CHAT',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cfg.color.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(cfg.icon, size: 12, color: cfg.color),
          const SizedBox(width: 4),
          Text(
            cfg.label,
            style: TextStyle(
              color: cfg.color,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

