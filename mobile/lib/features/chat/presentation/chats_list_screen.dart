import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../auth/application/auth_providers.dart';
import '../application/chat_providers.dart';
import '../domain/chat.dart';

/// Screen-inventory #14 — Chats list.
///
/// When [tripId] is non-null the screen is scoped to that trip (reached via
/// the trip bottom-nav). When [tripId] is null the screen is global and
/// shows every thread the user participates in across all trips — this is
/// the entry point from the Profile menu.
class ChatsListScreen extends ConsumerWidget {
  const ChatsListScreen({super.key, this.tripId});
  final String? tripId;

  bool get _isGlobal => tripId == null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ChatThread>> async = _isGlobal
        ? ref.watch(allChatsProvider)
        : ref.watch(tripThreadsProvider(tripId!));
    final DemoStore store = ref.read(demoStoreProvider);
    final String? meId = ref.watch(currentUserProvider).valueOrNull?.id;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _isGlobal
              ? context.go('/m/trips')
              : context.go('/m/trips/$tripId/dashboard'),
        ),
        title: Text(_isGlobal ? 'CHATS' : 'CHATS'),
      ),
      bottomNavigationBar: _isGlobal
          ? null
          : TripBottomNav(
              tripId: tripId!,
              currentLocation: '/m/trips/$tripId/chat',
            ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (List<ChatThread> threads) => threads.isEmpty
            ? _EmptyState(global: _isGlobal)
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: threads.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (BuildContext context, int i) {
                  final ChatThread t = threads[i];
                  return _ThreadCard(
                    thread: t,
                    store: store,
                    meId: meId,
                    onTap: () =>
                        context.go('/m/trips/${t.tripId}/chat/${t.id}'),
                  );
                },
              ),
      ),
    );
  }
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({
    required this.thread,
    required this.store,
    required this.meId,
    required this.onTap,
  });

  final ChatThread thread;
  final DemoStore store;
  final String? meId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isGroup = thread.isGroup;
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.brandBrown,
                child: Icon(
                  isGroup ? Icons.groups : Icons.person,
                  color: AppColors.cream,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      thread.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: thread.unreadCount > 0
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      thread.lastMessagePreview ?? '(no messages yet)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (thread.lastMessageAt != null)
                    Text(
                      DateFormat.Hm().format(thread.lastMessageAt!),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (thread.unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.outflow,
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      child: Text(
                        '${thread.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.global});
  final bool global;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.chat_outlined, size: 48, color: AppColors.goldOlive),
          const SizedBox(height: AppSpacing.md),
          Text(
            global
                ? 'No chat threads yet.'
                : 'No chat threads in this trip yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
