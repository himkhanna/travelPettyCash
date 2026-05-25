import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import 'widgets/cms_theme.dart' show CmsColors;
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';

/// Inline comment dialog for admins on the CMS expense list. Posts a
/// comment scoped to the expense, with optional @mentions that fan out a
/// targeted notification (type {@code EXPENSE_QUERY}) to each mentioned
/// trip participant.
///
/// Why expense-scoped (not trip chat): a trip-wide chat thread had to
/// already exist before anyone could post into it, which broke the admin's
/// "ask a question on this expense" path for brand-new trips with no
/// member activity yet. Expense comments live with the event, so they
/// always have a home.
class AdminExpenseCommentDialog extends ConsumerStatefulWidget {
  const AdminExpenseCommentDialog({super.key, required this.expense});
  final Expense expense;

  @override
  ConsumerState<AdminExpenseCommentDialog> createState() =>
      _AdminExpenseCommentDialogState();
}

class _AdminExpenseCommentDialogState
    extends ConsumerState<AdminExpenseCommentDialog> {
  final TextEditingController _ctrl = TextEditingController();
  final Set<String> _selectedMentions = <String>{};
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DemoStore store = ref.read(demoStoreProvider);
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final AsyncValue<Trip> tripAsync =
        ref.watch(tripDetailProvider(widget.expense.tripId));

    String catLabel;
    try {
      catLabel = store.categoryByCode(widget.expense.categoryCode).nameEn;
    } catch (_) {
      catLabel = widget.expense.categoryCode;
    }
    String authorName;
    try {
      authorName = store.userById(widget.expense.userId).displayName;
    } catch (_) {
      authorName = 'Member';
    }

    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      title: const Row(
        children: <Widget>[
          Icon(
            Icons.chat_bubble_outline,
            color: CmsColors.brandBrown,
            size: 20,
          ),
          SizedBox(width: AppSpacing.sm),
          Text('Comment on expense'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ExpenseContextCard(
                catLabel: catLabel,
                authorName: authorName,
                amountText: widget.expense.amount.format(),
                categoryCode: widget.expense.categoryCode,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _ctrl,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Your message',
                  hintText: 'Is this incl. tax?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Notify (@mention)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CmsColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              tripAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (Object e, _) => Text(
                  'Could not load trip participants',
                  style: const TextStyle(
                    fontSize: 11,
                    color: CmsColors.outflow,
                  ),
                ),
                data: (Trip trip) => _MentionPicker(
                  participantIds: _participantIds(trip),
                  store: store,
                  excludeUserId: me?.id,
                  selected: _selectedMentions,
                  onToggle: (String userId) {
                    setState(() {
                      if (_selectedMentions.contains(userId)) {
                        _selectedMentions.remove(userId);
                      } else {
                        _selectedMentions.add(userId);
                      }
                    });
                  },
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: CmsColors.outflow,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Mentioned users get a notification with this expense '
                'attached. The comment is also visible to anyone who can '
                'see the expense.',
                style: TextStyle(
                  fontSize: 11,
                  color: CmsColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('CANCEL'),
        ),
        FilledButton.icon(
          onPressed: _sending || me == null ? null : () => _send(me),
          style: FilledButton.styleFrom(
            backgroundColor: CmsColors.brandBrown,
            foregroundColor: CmsColors.cream,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            visualDensity: VisualDensity.compact,
          ),
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CmsColors.cream,
                  ),
                )
              : const Icon(Icons.send, size: 16),
          label: const Text(
            'POST',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _send(User me) async {
    final String body = _ctrl.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Type a message first.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(expenseCommentRepositoryProvider).post(
            expenseId: widget.expense.id,
            body: body,
            mentionedUserIds: _selectedMentions.toList(growable: false),
          );
      // Invalidate so any open detail page picks up the new comment.
      ref.invalidate(expenseCommentsProvider(widget.expense.id));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedMentions.isEmpty
                ? 'Comment posted.'
                : '${_selectedMentions.length} '
                    '${_selectedMentions.length == 1 ? "person" : "people"} '
                    'notified.',
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Could not post: $e';
        _sending = false;
      });
    }
  }

  List<String> _participantIds(Trip trip) {
    final Set<String> ids = <String>{trip.leaderId, ...trip.memberIds};
    // Show the expense author too, in case they're not in members list
    // (e.g. an old data state).
    ids.add(widget.expense.userId);
    return ids.toList(growable: false);
  }
}

class _ExpenseContextCard extends StatelessWidget {
  const _ExpenseContextCard({
    required this.catLabel,
    required this.authorName,
    required this.amountText,
    required this.categoryCode,
  });
  final String catLabel;
  final String authorName;
  final String amountText;
  final String categoryCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: CmsColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.chip),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CmsColors.forCategory(categoryCode),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$catLabel · $amountText',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'logged by $authorName',
                  style: const TextStyle(
                    fontSize: 11,
                    color: CmsColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MentionPicker extends StatelessWidget {
  const _MentionPicker({
    required this.participantIds,
    required this.store,
    required this.excludeUserId,
    required this.selected,
    required this.onToggle,
  });

  final List<String> participantIds;
  final DemoStore store;
  final String? excludeUserId;
  final Set<String> selected;
  final void Function(String userId) onToggle;

  @override
  Widget build(BuildContext context) {
    final List<String> candidates = participantIds
        .where((String id) => id != excludeUserId)
        .toSet()
        .toList(growable: false);
    if (candidates.isEmpty) {
      return const Text(
        'No other participants on this trip.',
        style: TextStyle(fontSize: 12, color: CmsColors.textSecondary),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final String id in candidates)
          _MentionChip(
            label: _displayName(id),
            selected: selected.contains(id),
            onTap: () => onToggle(id),
          ),
      ],
    );
  }

  String _displayName(String userId) {
    try {
      return store.userById(userId).displayName;
    } catch (_) {
      return userId.substring(0, userId.length.clamp(0, 6));
    }
  }
}

class _MentionChip extends StatelessWidget {
  const _MentionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CmsColors.brandBrown : CmsColors.cream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? CmsColors.brandBrown : CmsColors.divider,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected ? Icons.check : Icons.alternate_email,
                size: 14,
                color: selected ? CmsColors.cream : CmsColors.brandBrown,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? CmsColors.cream : CmsColors.brandBrown,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
