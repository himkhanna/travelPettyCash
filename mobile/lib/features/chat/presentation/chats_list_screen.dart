import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../application/chat_providers.dart';
import '../domain/chat.dart';

/// Screen-inventory #14 — Chats list for the trip.
class ChatsListScreen extends ConsumerWidget {
  const ChatsListScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ChatThread>> async = ref.watch(
      tripThreadsProvider(tripId),
    );
    final DemoStore store = ref.read(demoStoreProvider);
    final String? meId = ref.watch(currentUserProvider).valueOrNull?.id;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/m/trips/$tripId/dashboard'),
        ),
        title: const Text('CHATS'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (List<ChatThread> threads) => threads.isEmpty
            ? const _EmptyState()
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
                        context.go('/m/trips/$tripId/chat/${t.id}'),
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
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.chat_outlined, size: 48, color: AppColors.goldOlive),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No chat threads in this trip yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
