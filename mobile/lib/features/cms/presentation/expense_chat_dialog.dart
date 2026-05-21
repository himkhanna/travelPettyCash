import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../chat/application/chat_providers.dart';
import '../../chat/domain/chat.dart';
import '../../expenses/domain/expense.dart';
import '../../notifications/domain/notification.dart';

/// Admin → expense-owner Q&A inline in the CMS. Opens (or resumes) the
/// dedicated chat thread for an expense and emits an EXPENSE_QUERY
/// notification the first time the admin sends a question.
class ExpenseChatDialog extends ConsumerStatefulWidget {
  const ExpenseChatDialog({super.key, required this.expense});
  final Expense expense;

  @override
  ConsumerState<ExpenseChatDialog> createState() => _ExpenseChatDialogState();
}

class _ExpenseChatDialogState extends ConsumerState<ExpenseChatDialog> {
  final TextEditingController _composerCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  ChatThread? _thread;
  bool _sending = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureThread());
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureThread() async {
    final DemoStore store = ref.read(demoStoreProvider);
    final User? me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) {
      setState(() => _initError = 'You are not signed in.');
      return;
    }
    try {
      final ExpenseCategory cat = store.categoryByCode(
        widget.expense.categoryCode,
      );
      final String label =
          '${cat.nameEn} · ${widget.expense.amount.format()} · '
          '${DateFormat.yMMMd().format(widget.expense.occurredAt)}';
      final String labelAr =
          '${cat.nameAr} · ${widget.expense.amount.format()} · '
          '${DateFormat.yMMMd().format(widget.expense.occurredAt)}';
      final ChatThread thread = await ref
          .read(chatRepositoryProvider)
          .getOrCreateExpenseThread(
            expenseId: widget.expense.id,
            tripId: widget.expense.tripId,
            adminUserId: me.id,
            ownerUserId: widget.expense.userId,
            expenseLabel: label,
            expenseLabelAr: labelAr,
          );
      if (!mounted) return;
      setState(() => _thread = thread);
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = 'Could not open thread: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final DemoStore store = ref.read(demoStoreProvider);
    final User owner = store.userById(widget.expense.userId);
    final ExpenseCategory cat = store.categoryByCode(
      widget.expense.categoryCode,
    );

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Header(
              owner: owner,
              expense: widget.expense,
              categoryName: cat.nameEn,
              onClose: () => Navigator.of(context).pop(),
            ),
            const Divider(height: 1),
            Expanded(
              child: _initError != null
                  ? Center(
                      child: Text(
                        _initError!,
                        style: const TextStyle(color: AppColors.outflow),
                      ),
                    )
                  : _thread == null
                  ? const Center(child: CircularProgressIndicator())
                  : _MessagesPane(
                      threadId: _thread!.id,
                      scrollCtrl: _scrollCtrl,
                    ),
            ),
            const Divider(height: 1),
            _Composer(
              controller: _composerCtrl,
              sending: _sending,
              enabled: _thread != null && _initError == null,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final String body = _composerCtrl.text.trim();
    if (body.isEmpty || _thread == null) return;
    final User? me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    setState(() => _sending = true);
    try {
      final DemoStore store = ref.read(demoStoreProvider);
      final bool firstFromAdmin = !store.chatMessages.any(
        (ChatMessage m) =>
            m.threadId == _thread!.id && m.senderId == me.id,
      );

      await ref.read(chatRepositoryProvider).send(
        threadId: _thread!.id,
        senderId: me.id,
        body: body,
      );

      if (firstFromAdmin) {
        final DateTime now = DateTime.now();
        store.notifications.add(
          AppNotification(
            id: 'notif-eq-${_thread!.id}-${now.microsecondsSinceEpoch}',
            userId: widget.expense.userId,
            type: NotificationType.expenseQuery,
            payload: <String, Object?>{
              'tripId': widget.expense.tripId,
              'expenseId': widget.expense.id,
              'threadId': _thread!.id,
              'fromUserId': me.id,
              'question': body,
            },
            actionable: false,
            state: NotificationState.unread,
            createdAt: now,
          ),
        );
        store.emit(DemoStoreEvent.notificationsChanged);
      }

      _composerCtrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.owner,
    required this.expense,
    required this.categoryName,
    required this.onClose,
  });
  final User owner;
  final Expense expense;
  final String categoryName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.question_answer_outlined,
              color: AppColors.brandBrown),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Ask ${owner.displayName}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '$categoryName · ${expense.amount.format()} · '
                  '${DateFormat.yMMMd().format(expense.occurredAt)}'
                  '${expense.details.isEmpty ? '' : ' · "${expense.details}"'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
    );
  }
}

class _MessagesPane extends ConsumerWidget {
  const _MessagesPane({required this.threadId, required this.scrollCtrl});
  final String threadId;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ChatMessage>> async = ref.watch(
      threadMessagesProvider(threadId),
    );
    final DemoStore store = ref.read(demoStoreProvider);
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => Center(child: Text('Error: $e')),
      data: (List<ChatMessage> messages) {
        if (messages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'No messages yet — type your question below.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollCtrl.hasClients) {
            scrollCtrl.animateTo(
              scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
        return ListView.builder(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: messages.length,
          itemBuilder: (BuildContext context, int i) {
            final ChatMessage m = messages[i];
            final bool mine = m.senderId == me?.id;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _Bubble(
                message: m,
                mine: mine,
                senderName: store.userById(m.senderId).displayName,
              ),
            );
          },
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
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
          constraints: const BoxConstraints(maxWidth: 360),
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
                  DateFormat('d MMM HH:mm').format(message.sentAt),
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
    required this.enabled,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Ask about this line item…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.cream,
                    ),
                  )
                : const Icon(Icons.send, size: 18),
            label: const Text('SEND'),
            onPressed: enabled && !sending ? onSend : null,
          ),
        ],
      ),
    );
  }
}
