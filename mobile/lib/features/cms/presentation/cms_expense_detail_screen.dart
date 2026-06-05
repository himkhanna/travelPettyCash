import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart' show AppRadii, AppSpacing;
import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/data/expense_repository.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/domain/expense_comment.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import 'admin_expense_comment_dialog.dart';
import 'widgets/cms_layout.dart';
import 'widgets/cms_theme.dart';

/// CMS expense detail page (admin / super-admin only). Shows the header,
/// invoice photo (with click-to-fullscreen), key/value breakdown, the
/// linked trip, and the comments thread + composer. Reachable from
/// /cms/expenses row tap and EXPENSE_QUERY notification routing.
class CmsExpenseDetailScreen extends ConsumerWidget {
  const CmsExpenseDetailScreen({super.key, required this.expenseId});
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null ||
        (me.role != UserRole.admin && me.role != UserRole.superAdmin)) {
      return const CmsLayout(
        active: CmsNavItem.expenses,
        title: 'Expense',
        child: Center(child: Text('Admin only.')),
      );
    }

    final ExpenseRepository repo = ref.watch(expenseRepositoryProvider);
    return CmsLayout(
      active: CmsNavItem.expenses,
      breadcrumb: const <String>['Home', 'Expenses', 'Detail'],
      title: 'Expense detail',
      titleSubtitle: 'Inspect the invoice, breakdown, and conversation.',
      child: FutureBuilder<Expense>(
        future: repo.byId(expenseId),
        builder: (BuildContext context, AsyncSnapshot<Expense> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load expense.\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CmsColors.outflow),
                ),
              ),
            );
          }
          return _Body(expense: snap.data!, currentUserId: me.id);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.expense, required this.currentUserId});
  final Expense expense;
  final String currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DemoStore store = ref.read(demoStoreProvider);
    final AsyncValue<Trip> tripAsync =
        ref.watch(tripDetailProvider(expense.tripId));
    final String catName = _safe(() =>
        store.categoryByCode(expense.categoryCode).nameEn, expense.categoryCode);
    final String authorName =
        _safe(() => store.userById(expense.userId).displayName, 'Member');
    final String sourceName =
        _safe(() => store.sourceById(expense.sourceId).name, 'Source');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Left column: receipt + comments.
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _ReceiptCard(
                    expenseId: expense.id,
                    objectKey: expense.receiptObjectKey,
                  ),
                  const SizedBox(height: 14),
                  _CommentsCard(
                    expense: expense,
                    currentUserId: currentUserId,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            // Right column: meta cards.
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _HeaderCard(
                    expense: expense,
                    catName: catName,
                  ),
                  const SizedBox(height: 14),
                  _DetailsCard(
                    expense: expense,
                    sourceName: sourceName,
                    authorName: authorName,
                  ),
                  const SizedBox(height: 14),
                  _TripCard(tripId: expense.tripId, tripAsync: tripAsync),
                  if (expense.details.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    _NoteCard(text: expense.details),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _safe(String Function() fn, String fallback) {
    try {
      return fn();
    } catch (_) {
      return fallback;
    }
  }
}

// =========================================================================
// Header / amount / category card
// =========================================================================

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.expense, required this.catName});
  final Expense expense;
  final String catName;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CmsColors.forCategory(expense.categoryCode),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.receipt_long_outlined,
                  size: 18, color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      catName,
                      style: const TextStyle(
                        color: CmsColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      DateFormat('d MMM yyyy · HH:mm')
                          .format(expense.occurredAt.toLocal()),
                      style: const TextStyle(
                        color: CmsColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                missingReceipt: expense.receiptObjectKey == null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            expense.amount.format(),
            style: const TextStyle(
              color: CmsColors.textPrimary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              fontSize: 28,
              letterSpacing: -0.4,
            ),
          ),
          // ADR-003: foreign original + manual rate, when present.
          if (expense.originalAmount != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              expense.exchangeRate == null
                  ? expense.originalAmount!.format()
                  : '${expense.originalAmount!.format()} '
                      '@ ${expense.exchangeRate}',
              style: const TextStyle(
                color: CmsColors.textSecondary,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.missingReceipt});
  final bool missingReceipt;
  @override
  Widget build(BuildContext context) {
    if (missingReceipt) {
      return _Pill(
        text: 'NO RECEIPT',
        color: CmsColors.outflow,
        bg: CmsColors.redSoft,
        icon: Icons.report_problem_outlined,
      );
    }
    return _Pill(
      text: 'RECEIPT ATTACHED',
      color: CmsColors.accentDeep,
      bg: CmsColors.accentSoft,
      icon: Icons.check_circle_outline,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.color,
    required this.bg,
    required this.icon,
  });
  final String text;
  final Color color;
  final Color bg;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// Details card (qty / unit / total / source / added-by / occurred-at)
// =========================================================================

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.expense,
    required this.sourceName,
    required this.authorName,
  });
  final Expense expense;
  final String sourceName;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'BREAKDOWN',
      child: Column(
        children: <Widget>[
          _KV(label: 'Quantity', value: '${expense.quantity}'),
          _KV(
            label: 'Per unit',
            value:
                '${_majorOnly(expense.amount.amountMinor ~/ expense.quantity)} '
                '${expense.amount.currencyCode}',
            mono: true,
          ),
          _KV(
            label: 'Total',
            value:
                '${_majorOnly(expense.amount.amountMinor)} '
                '${expense.amount.currencyCode}',
            mono: true,
            emphasis: true,
          ),
          _KV(label: 'Source', value: sourceName),
          _KV(label: 'Added by', value: authorName),
          _KV(
            label: 'Occurred',
            value: DateFormat('d MMM yyyy, HH:mm')
                .format(expense.occurredAt.toLocal()),
          ),
        ],
      ),
    );
  }

  String _majorOnly(int minor) =>
      NumberFormat.decimalPattern('en_US').format(minor / 100.0);
}

class _KV extends StatelessWidget {
  const _KV({
    required this.label,
    required this.value,
    this.mono = false,
    this.emphasis = false,
  });
  final String label;
  final String value;
  final bool mono;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: CmsColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: CmsColors.textPrimary,
                fontSize: emphasis ? 14 : 12.5,
                fontWeight:
                    emphasis ? FontWeight.w800 : FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// Trip link card
// =========================================================================

class _TripCard extends StatelessWidget {
  const _TripCard({required this.tripId, required this.tripAsync});
  final String tripId;
  final AsyncValue<Trip> tripAsync;
  @override
  Widget build(BuildContext context) {
    final String? name = tripAsync.maybeWhen(
      data: (Trip t) => t.name,
      orElse: () => null,
    );
    final String? country = tripAsync.maybeWhen(
      data: (Trip t) => t.countryCode.toUpperCase(),
      orElse: () => null,
    );
    return _Card(
      title: 'TRIP',
      child: InkWell(
        onTap: () => GoRouter.of(context).go('/cms/trips/$tripId'),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.flight_takeoff_outlined,
                size: 16, color: CmsColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name ?? 'Open trip',
                      style: const TextStyle(
                        color: CmsColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    if (country != null && country.isNotEmpty)
                      Text(
                        country,
                        style: const TextStyle(
                          color: CmsColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward,
                size: 14, color: CmsColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// Note card (echoes the details string when present)
// =========================================================================

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'NOTE',
      child: Text(
        text,
        style: const TextStyle(
          color: CmsColors.textPrimary, fontSize: 13, height: 1.4,
        ),
      ),
    );
  }
}

// =========================================================================
// Receipt viewer card
// =========================================================================

class _ReceiptCard extends ConsumerStatefulWidget {
  const _ReceiptCard({required this.expenseId, required this.objectKey});
  final String expenseId;
  final String? objectKey;
  @override
  ConsumerState<_ReceiptCard> createState() => _ReceiptCardState();
}

class _ReceiptCardState extends ConsumerState<_ReceiptCard> {
  String? _url;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.objectKey != null) {
      _fetch();
    } else {
      _loaded = true;
    }
  }

  Future<void> _fetch() async {
    try {
      final String url = await ref
          .read(expenseRepositoryProvider)
          .receiptUrl(widget.expenseId);
      if (!mounted) return;
      setState(() {
        _url = url;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'INVOICE',
      // Card already has 14 padding; pull it tighter around the image.
      contentPadding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 4 / 3,
            child: _buildImage(context),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    if (widget.objectKey == null) {
      return _placeholder(
        icon: Icons.report_problem_outlined,
        color: CmsColors.outflow,
        text: 'No invoice attached',
        sub: 'Member submitted this expense without a receipt.',
      );
    }
    if (!_loaded) {
      return _placeholder(
        icon: Icons.image_outlined,
        color: CmsColors.textTertiary,
        text: 'Loading invoice…',
      );
    }
    if (_url == null) {
      return _placeholder(
        icon: Icons.broken_image_outlined,
        color: CmsColors.textTertiary,
        text: 'Could not load invoice.',
        sub: 'Try refreshing the page.',
      );
    }
    return InkWell(
      onTap: () => _showFullscreen(context, _url!),
      child: Container(
        color: CmsColors.bgInset,
        child: Image.network(
          _url!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _placeholder(
            icon: Icons.broken_image_outlined,
            color: CmsColors.textTertiary,
            text: 'Could not display invoice.',
          ),
        ),
      ),
    );
  }

  Widget _placeholder({
    required IconData icon,
    required Color color,
    required String text,
    String? sub,
  }) {
    return Container(
      color: CmsColors.bgInset,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 38, color: color),
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w700,
              ),
            ),
            if (sub != null) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CmsColors.textSecondary, fontSize: 11.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFullscreen(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: <Widget>[
            InteractiveViewer(child: Image.network(url)),
            Positioned(
              top: 8, right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Comments thread + composer
// =========================================================================

class _CommentsCard extends ConsumerStatefulWidget {
  const _CommentsCard({required this.expense, required this.currentUserId});
  final Expense expense;
  final String currentUserId;
  @override
  ConsumerState<_CommentsCard> createState() => _CommentsCardState();
}

class _CommentsCardState extends ConsumerState<_CommentsCard> {
  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ExpenseComment>> async =
        ref.watch(expenseCommentsProvider(widget.expense.id));
    final DemoStore store = ref.read(demoStoreProvider);
    return _Card(
      title: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.chat_bubble_outline,
                size: 14, color: CmsColors.textSecondary,
              ),
              const SizedBox(width: 6),
              const Text(
                'Conversation',
                style: TextStyle(
                  color: CmsColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              async.maybeWhen(
                data: (List<ExpenseComment> list) => Text(
                  '${list.length} message${list.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: CmsColors.textSecondary, fontSize: 11.5,
                  ),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      AdminExpenseCommentDialog(expense: widget.expense),
                ).then((_) => ref.invalidate(
                    expenseCommentsProvider(widget.expense.id))),
                icon: const Icon(Icons.alternate_email, size: 13),
                label: const Text('@-mention'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CmsColors.brand,
                  side: BorderSide(
                    color: CmsColors.brand.withValues(alpha: 0.4),
                  ),
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (Object e, _) => Text(
              'Could not load comments.\n$e',
              style: const TextStyle(
                color: CmsColors.outflow, fontSize: 12,
              ),
            ),
            data: (List<ExpenseComment> list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'No conversation yet. Start one to ask the submitter '
                    'a question.',
                    style: TextStyle(
                      color: CmsColors.textSecondary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }
              return Column(
                children: <Widget>[
                  for (final ExpenseComment c in list)
                    _Bubble(
                      comment: c,
                      mine: c.authorId == widget.currentUserId,
                      authorName: _name(store, c.authorId),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: CmsColors.divider),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Reply to this thread…',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: CmsColors.brand,
                  foregroundColor: CmsColors.surfaceCard,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 16),
              ),
            ],
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: const TextStyle(
                color: CmsColors.outflow, fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _name(DemoStore store, String userId) {
    try {
      return store.userById(userId).displayName;
    } catch (_) {
      return 'Someone';
    }
  }

  Future<void> _send() async {
    final String body = _ctrl.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Type a reply first.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(expenseCommentRepositoryProvider)
          .post(expenseId: widget.expense.id, body: body);
      _ctrl.clear();
      ref.invalidate(expenseCommentsProvider(widget.expense.id));
    } catch (e) {
      setState(() => _error = 'Could not post: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.comment,
    required this.mine,
    required this.authorName,
  });
  final ExpenseComment comment;
  final bool mine;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final String time = DateFormat('d MMM · HH:mm')
        .format(comment.createdAt.toLocal());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: <Widget>[
          if (!mine) _Avatar(name: authorName, color: CmsColors.brand),
          if (!mine) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8,
              ),
              decoration: BoxDecoration(
                color: mine ? CmsColors.brandTint : CmsColors.bgElev,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: CmsColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    mine ? 'You · $time' : '$authorName · $time',
                    style: const TextStyle(
                      color: CmsColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comment.body,
                    style: const TextStyle(
                      color: CmsColors.textPrimary,
                      fontSize: 13, height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (mine) const SizedBox(width: 8),
          if (mine) _Avatar(name: authorName, color: CmsColors.gold),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.color});
  final String name;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final List<String> parts =
        name.split(' ').where((String p) => p.isNotEmpty).toList();
    String initials;
    if (parts.isEmpty) {
      initials = '?';
    } else if (parts.length == 1) {
      initials = parts.first[0].toUpperCase();
    } else {
      initials = (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// =========================================================================
// Card chrome
// =========================================================================

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.title,
    this.contentPadding = const EdgeInsets.all(14),
  });
  final Widget child;
  final String? title;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                14, 12, 14, 6,
              ),
              child: Text(
                title!,
                style: const TextStyle(
                  color: CmsColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          Padding(
            padding: title != null
                ? const EdgeInsets.fromLTRB(
                    AppSpacing.md, 0, AppSpacing.md, AppSpacing.md,
                  )
                : contentPadding,
            child: child,
          ),
        ],
      ),
    );
  }
}
