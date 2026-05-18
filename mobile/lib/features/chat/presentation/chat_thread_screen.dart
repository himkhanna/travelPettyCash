import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
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

  /// Optional expense pinned to the next outgoing message. Cleared after send.
  /// Encoded on the wire as a `[exp:<uuid>]` token prepended to the body —
  /// the message bubble parses it back out on the way in.
  Expense? _attached;

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
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    // Pull the thread metadata (title, isGroup) from the live trip-threads
    // provider rather than the DemoStore cache — the title can change if
    // somebody renames a group, and the cache would miss that.
    final ChatThread? thread = ref
        .watch(tripThreadsProvider(widget.tripId))
        .valueOrNull
        ?.where((ChatThread t) => t.id == widget.threadId)
        .firstOrNull;
    // DemoStore here is only used for the sender display-name lookup below
    // (`store.userById(...)`) — that's denormalised reference data populated
    // by hydration and stable for the session.
    final DemoStore store = ref.read(demoStoreProvider);

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
            attached: _attached,
            onAttach: _pickExpenseToAttach,
            onClearAttached: () => setState(() => _attached = null),
            onSend: _send,
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _send() async {
    String body = _composerCtrl.text.trim();
    // Allow attachment-only messages: if a pinned expense exists, an empty
    // text body is fine — the card itself carries the question.
    if (body.isEmpty && _attached == null) return;
    final User? me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    if (_attached != null) {
      // Wire-format token. Senders never see this; the bubble parses and
      // strips it before rendering. The token sits at the start of the body
      // so any plain-text consumer (notifications, exports) still gets the
      // question text after it.
      body = '[exp:${_attached!.id}] $body'.trim();
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .send(threadId: widget.threadId, senderId: me.id, body: body);
      _composerCtrl.clear();
      setState(() => _attached = null);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Open a bottom sheet listing this trip's expenses; tapping one pins it
  /// to the composer. The list is the same `tripExpensesProvider` used by
  /// the admin trip detail, so it stays current.
  Future<void> _pickExpenseToAttach() async {
    final Expense? picked = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext _) =>
          _ExpensePicker(tripId: widget.tripId),
    );
    if (picked != null && mounted) {
      setState(() => _attached = picked);
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

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.senderName,
  });

  final ChatMessage message;
  final bool mine;
  final String senderName;

  /// Matches the leading `[exp:<uuid>] ` token the composer writes when the
  /// sender attached an expense. Group 1 is the expense id; everything after
  /// the space is the plain-text portion of the message.
  static final RegExp _expToken =
      RegExp(r'^\[exp:([0-9a-fA-F\-]+)\]\s?');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RegExpMatch? m = _expToken.firstMatch(message.body);
    final String? attachedExpenseId = m?.group(1);
    final String text = attachedExpenseId == null
        ? message.body
        : message.body.substring(m!.end);

    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
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
                if (attachedExpenseId != null) ...<Widget>[
                  _AttachedExpenseCard(expenseId: attachedExpenseId),
                  if (text.isNotEmpty) const SizedBox(height: 6),
                ],
                if (text.isNotEmpty) Text(text),
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

/// Inline card rendered inside a chat bubble when the sender attached an
/// expense. Looks the expense up via the trip-scoped provider; if it can't
/// find one (stale chat history, expense deleted) we render a graceful
/// "expense unavailable" stub rather than crashing the row.
class _AttachedExpenseCard extends ConsumerWidget {
  const _AttachedExpenseCard({required this.expenseId});
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We don't know the tripId at the card scope, so we resolve via the
    // DemoStore reference cache (always populated by hydration). Falls back
    // to a stub if the expense isn't found locally.
    final DemoStore store = ref.read(demoStoreProvider);
    final Expense? e = store.expenses
        .where((Expense x) => x.id == expenseId)
        .firstOrNull;

    final BorderRadius radius = const BorderRadius.all(Radius.circular(10));
    if (e == null) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.divider.withValues(alpha: 0.3),
          borderRadius: radius,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.receipt_long_outlined,
                size: 16, color: AppColors.textSecondary),
            SizedBox(width: 6),
            Text(
              'Expense unavailable',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    String catName;
    try {
      catName = store.categoryByCode(e.categoryCode).nameEn;
    } catch (_) {
      catName = e.categoryCode;
    }
    String sourceName;
    try {
      sourceName = store.sourceById(e.sourceId).name;
    } catch (_) {
      sourceName = '—';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: radius,
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.forCategory(e.categoryCode),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.receipt_long_outlined,
                  size: 13,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  catName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                e.amount.format(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBrown,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$sourceName · ${DateFormat.yMMMd().format(e.occurredAt)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          if (e.details.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              e.details,
              style: const TextStyle(fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _Composer extends ConsumerWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.attached,
    required this.onAttach,
    required this.onClearAttached,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final Expense? attached;
  final VoidCallback onAttach;
  final VoidCallback onClearAttached;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (attached != null) ...<Widget>[
              _AttachedExpenseChip(
                expense: attached!,
                onClear: onClearAttached,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Row(
              children: <Widget>[
                // Attach-expense button. Disabled while sending so the picker
                // doesn't open mid-flight.
                IconButton(
                  icon: const Icon(
                    Icons.attach_file,
                    color: AppColors.brandBrown,
                  ),
                  tooltip: 'Attach expense',
                  onPressed: sending ? null : onAttach,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: attached != null
                          ? 'Add a note (optional)…'
                          : 'Type a message…',
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
          ],
        ),
      ),
    );
  }
}

class _AttachedExpenseChip extends ConsumerWidget {
  const _AttachedExpenseChip({required this.expense, required this.onClear});
  final Expense expense;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DemoStore store = ref.read(demoStoreProvider);
    String catName;
    try {
      catName = store.categoryByCode(expense.categoryCode).nameEn;
    } catch (_) {
      catName = expense.categoryCode;
    }
    String sourceName;
    try {
      sourceName = store.sourceById(expense.sourceId).name;
    } catch (_) {
      sourceName = '—';
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.receipt_long_outlined,
            size: 16,
            color: AppColors.brandBrown,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$catName · ${expense.amount.format()} · $sourceName',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.brandBrownDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: onClear,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpensePicker extends ConsumerWidget {
  const _ExpensePicker({required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Expense>> async =
        ref.watch(tripExpensesProvider(tripId));
    final DemoStore store = ref.read(demoStoreProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Attach an expense',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (Object e, _) => Text('Error: $e'),
                  data: (List<Expense> list) {
                    if (list.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            'No expenses on this trip yet.',
                            style:
                                TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      );
                    }
                    final List<Expense> sorted = <Expense>[...list]
                      ..sort((Expense a, Expense b) =>
                          b.occurredAt.compareTo(a.occurredAt));
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppColors.divider),
                      itemBuilder: (BuildContext context, int i) {
                        final Expense e = sorted[i];
                        String userName;
                        try {
                          userName = store.userById(e.userId).displayName;
                        } catch (_) {
                          userName = 'Unknown';
                        }
                        String catName;
                        try {
                          catName =
                              store.categoryByCode(e.categoryCode).nameEn;
                        } catch (_) {
                          catName = e.categoryCode;
                        }
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.forCategory(e.categoryCode),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.receipt_long_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            '$catName · ${e.amount.format()}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '$userName · ${DateFormat.yMMMd().format(e.occurredAt)}',
                          ),
                          onTap: () => Navigator.of(context).pop(e),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
