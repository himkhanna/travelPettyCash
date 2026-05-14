import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../application/chat_providers.dart';
import '../domain/chat.dart';

/// Screen-inventory #15 — Single chat thread.
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.tripId,
    required this.threadId,
  });
  final String tripId;
  final String threadId;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final TextEditingController _composerCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final User? me = ref.read(currentUserProvider).valueOrNull;
      if (me != null) {
        ref
            .read(chatRepositoryProvider)
            .markRead(threadId: widget.threadId, userId: me.id);
      }
    });
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ChatMessage>> async = ref.watch(
      threadMessagesProvider(widget.threadId),
    );
    final DemoStore store = ref.read(demoStoreProvider);
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final ChatThread? thread = store.chatThreads
        .where((ChatThread t) => t.id == widget.threadId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/m/trips/${widget.tripId}/chat'),
        ),
        title: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.brandBrown,
              child: Icon(
                thread?.isGroup == true ? Icons.groups : Icons.person,
                color: AppColors.cream,
                size: 16,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(thread?.title ?? 'Chat'),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('Error: $e')),
              data: (List<ChatMessage> messages) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollCtrl.hasClients) {
                    _scrollCtrl.animateTo(
                      _scrollCtrl.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  }
                });
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: messages.length,
                  itemBuilder: (BuildContext context, int i) {
                    final ChatMessage m = messages[i];
                    final bool mine = m.senderId == me?.id;
                    final bool showDateBreak =
                        i == 0 ||
                        !_sameDay(messages[i - 1].sentAt, m.sentAt);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (showDateBreak) _DateChip(at: m.sentAt),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _MessageBubble(
                            message: m,
                            mine: mine,
                            senderName: store.userById(m.senderId).displayName,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _Composer(
            controller: _composerCtrl,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _send() async {
    final String body = _composerCtrl.text.trim();
    if (body.isEmpty) return;
    final User? me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .send(threadId: widget.threadId, senderId: me.id, body: body);
      _composerCtrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.at});
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Text(
          DateFormat('EEE d MMM yyyy').format(at).toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.senderName,
  });

  final ChatMessage message;
  final bool mine;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: mine ? AppColors.cream : AppColors.surfaceCard,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!mine)
                  Text(
                    senderName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.brandBrown,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(message.body),
                const SizedBox(height: 2),
                Text(
                  DateFormat.Hm().format(message.sentAt),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceCard,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm + MediaQuery.of(context).viewInsets.bottom * 0,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Material(
              color: AppColors.brandBrown,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.send, color: AppColors.cream, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
