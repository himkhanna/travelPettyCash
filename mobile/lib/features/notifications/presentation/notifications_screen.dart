import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../trips/application/trips_providers.dart';
import '../application/notifications_providers.dart';
import '../data/notifications_repository.dart';
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).canPop()
              ? Navigator.of(context).pop()
              : context.go('/m/trips'),
        ),
        title: const Text('NOTIFICATIONS'),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              final bool? confirm = await showDialog<bool>(
                context: context,
                builder: (BuildContext ctx) => AlertDialog(
                  title: const Text('Delete all notifications?'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('CANCEL'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('DELETE ALL'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(notificationsRepositoryProvider).deleteAll();
              }
            },
            child: const Text(
              'DELETE ALL',
              style: TextStyle(color: AppColors.outflow),
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (List<AppNotification> list) => list.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (BuildContext context, int i) {
                  final AppNotification n = list[i];
                  return Dismissible(
                    key: ValueKey<String>(n.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: AlignmentDirectional.centerEnd,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.outflow,
                        borderRadius: const BorderRadius.all(AppRadii.card),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => ref
                        .read(notificationsRepositoryProvider)
                        .delete(n.id),
                    child: _NotificationCard(notification: n),
                  );
                },
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
    final bool actionable =
        notification.actionable &&
        notification.state != NotificationState.acted;

    return Material(
      color: unread ? AppColors.cream : AppColors.surfaceCard,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: InkWell(
        onTap: () async {
          if (unread) {
            await ref
                .read(notificationsRepositoryProvider)
                .markRead(notification.id);
          }
        },
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
              if (actionable) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: () => _respond(
                        context,
                        ref,
                        NotificationAction.decline,
                      ),
                      child: const Text('DECLINE'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: () =>
                          _respond(context, ref, NotificationAction.accept),
                      child: const Text('ACCEPT'),
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

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    NotificationAction action,
  ) async {
    try {
      await ref
          .read(notificationsRepositoryProvider)
          .act(notificationId: notification.id, action: action);
      // Balance changes for accepted transfers — invalidate the relevant
      // dashboard scope so it picks up the move.
      final String? tripId = notification.payload['tripId'] as String?;
      if (tripId != null) {
        ref.invalidate(tripBalancesProvider);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
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
        return 'An admin has a question on one of your expenses: "${n.payload['question'] ?? ''}"';
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.notifications_none_outlined,
              size: 48,
              color: AppColors.goldOlive,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'You\'re all caught up.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
