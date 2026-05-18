import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../shared/widgets/pdd_primitives.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expenses_providers.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';
import '../domain/expense_comment.dart';

/// Expense detail per the handoff (`screens-trip.jsx → ExpenseDetailScreen`).
///
/// Layout: header card (category tile + big amount + vendor + pills),
/// then optional [ReceiptPhoto], then a key-value detail card, then an
/// optional note card.
class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.tripId,
    required this.expenseId,
  });
  final String tripId;
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExpenseRepository repo = ref.watch(expenseRepositoryProvider);
    final AsyncValue<Trip> tripAsync = ref.watch(tripDetailProvider(tripId));
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final DemoStore store = ref.read(demoStoreProvider);

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      bottomNavigationBar: TripBottomNav(
        tripId: tripId,
        currentLocation: '/m/trips/$tripId/expenses/$expenseId',
      ),
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<Expense>(
          future: repo.byId(expenseId),
          builder: (BuildContext context, AsyncSnapshot<Expense> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            final Expense e = snap.data!;
            final bool canEdit = me?.id == e.userId &&
                tripAsync.maybeWhen(
                  data: (Trip t) => t.status != TripStatus.closed,
                  orElse: () => false,
                );
            final String sourceName = _safeSource(store, e.sourceId);
            final String categoryName = _safeCategory(store, e.categoryCode);
            final String authorName = _safeUser(store, e.userId);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  PddTopBar(
                    user: me,
                    leadingBack: true,
                    onBack: () => context.go('/m/trips/$tripId/expenses/mine'),
                    title: 'Expense',
                    subtitle: DateFormat('d MMM yyyy · HH:mm').format(e.occurredAt),
                    actions: <Widget>[
                      PddTopBarIconButton(
                        icon: Icons.chat_bubble_outline,
                        tooltip: 'Discuss in chat',
                        // Opens the trip chat. Once inside a thread, tap
                        // the 📎 attach button to pin this expense to the
                        // question before sending.
                        onTap: () => context.go('/m/trips/$tripId/chat'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _HeaderCard(
                      categoryCode: e.categoryCode,
                      categoryName: categoryName,
                      amountText: _amountOnly(e),
                      currency: e.amount.currencyCode,
                      vendor: e.details.isEmpty ? categoryName : e.details,
                      sourceName: sourceName,
                      onEdit: canEdit
                          ? () => showPddToast(
                                context,
                                'Inline editing lands in Milestone A slice 4.',
                                info: true,
                              )
                          : null,
                    ),
                  ),
                  if (e.receiptObjectKey != null)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: _ReceiptViewer(objectKey: e.receiptObjectKey!),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _DetailCard(
                      rows: <_DetailKV>[
                        _DetailKV(
                          k: 'Quantity',
                          v: '${e.quantity} unit${e.quantity > 1 ? "s" : ""}',
                        ),
                        _DetailKV(
                          k: 'Cost per unit',
                          v: '${_amountForOne(e)} ${e.amount.currencyCode}',
                          mono: true,
                        ),
                        _DetailKV(
                          k: 'Total',
                          v: '${_amountOnly(e)} ${e.amount.currencyCode}',
                          mono: true,
                          emphasis: true,
                        ),
                        _DetailKV(k: 'Source', v: sourceName),
                        _DetailKV(k: 'Added by', v: authorName),
                        _DetailKV(
                          k: 'Date · time',
                          v: DateFormat('d MMM yyyy, HH:mm')
                              .format(e.occurredAt),
                        ),
                      ],
                    ),
                  ),
                  if (e.details.isNotEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: _NoteCard(text: e.details),
                    ),
                  if (e.pendingSync)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: _PendingSyncBanner(),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _CommentsThread(
                      expense: e,
                      currentUserId: me?.id,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.categoryCode,
    required this.categoryName,
    required this.amountText,
    required this.currency,
    required this.vendor,
    required this.sourceName,
    required this.onEdit,
  });

  final String categoryCode;
  final String categoryName;
  final String amountText;
  final String currency;
  final String vendor;
  final String sourceName;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.forCategoryBg(categoryCode),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(
              _iconForCategory(categoryCode),
              size: 28,
              color: AppColors.forCategory(categoryCode),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                RichText(
                  text: TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: amountText,
                        style: AppTypography.geistMono(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink1,
                          letterSpacing: -0.02 * 28,
                        ),
                      ),
                      TextSpan(
                        text: '  $currency',
                        style: AppTypography.geist(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  vendor,
                  style: AppTypography.geist(
                    fontSize: 14,
                    color: AppColors.ink2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _Pill(
                      label: categoryName,
                      color: AppColors.forCategory(categoryCode),
                      bg: AppColors.forCategoryBg(categoryCode),
                    ),
                    _Pill(
                      label: sourceName,
                      color: AppColors.brand,
                      bg: AppColors.brandTint,
                      dot: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.ink3),
              tooltip: 'Edit',
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.bg,
    this.dot = false,
  });
  final String label;
  final Color color;
  final Color bg;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (dot) ...<Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppTypography.geist(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.02,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailKV {
  const _DetailKV({
    required this.k,
    required this.v,
    this.mono = false,
    this.emphasis = false,
  });
  final String k;
  final String v;
  final bool mono;
  final bool emphasis;
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.rows});
  final List<_DetailKV> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0)
              const Divider(height: 1, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      rows[i].k.toUpperCase(),
                      style: AppTypography.geist(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.04 * 12,
                        color: AppColors.ink3,
                      ),
                    ),
                  ),
                  Text(
                    rows[i].v,
                    style: rows[i].mono
                        ? AppTypography.geistMono(
                            fontSize: 14,
                            fontWeight:
                                rows[i].emphasis ? FontWeight.w700 : FontWeight.w500,
                            color: AppColors.ink1,
                          )
                        : AppTypography.geist(
                            fontSize: 14,
                            fontWeight:
                                rows[i].emphasis ? FontWeight.w700 : FontWeight.w500,
                            color: AppColors.ink1,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('NOTE', style: AppTypography.microLabel()),
          const SizedBox(height: 4),
          Text(
            text,
            style: AppTypography.geist(
              fontSize: 14,
              color: AppColors.ink1,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingSyncBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off, color: AppColors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This expense is queued. It will sync when you return online.',
              style: AppTypography.geist(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.goldDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptViewer extends ConsumerStatefulWidget {
  const _ReceiptViewer({required this.objectKey});
  final String objectKey;

  @override
  ConsumerState<_ReceiptViewer> createState() => _ReceiptViewerState();
}

class _ReceiptViewerState extends ConsumerState<_ReceiptViewer> {
  String? _signedUrl;
  String? _expenseId;

  @override
  Widget build(BuildContext context) {
    // The object-key field on the row holds the MinIO key. We don't render
    // it directly; we ask the API for a fresh presigned URL.
    final ExpenseDetailScreen? parent =
        context.findAncestorWidgetOfExactType<ExpenseDetailScreen>();
    final String? newExpenseId = parent?.expenseId;
    if (newExpenseId != null && newExpenseId != _expenseId) {
      _expenseId = newExpenseId;
      _signedUrl = null;
      _fetchUrl();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('RECEIPT', style: AppTypography.microLabel()),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: _signedUrl != null
              ? GestureDetector(
                  onTap: () => _showFullscreen(context, _signedUrl!),
                  child: Image.network(
                    _signedUrl!,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  ),
                )
              : _placeholder(),
        ),
      ],
    );
  }

  Future<void> _fetchUrl() async {
    final String? id = _expenseId;
    if (id == null) return;
    try {
      final String url =
          await ref.read(expenseRepositoryProvider).receiptUrl(id);
      if (!mounted) return;
      setState(() => _signedUrl = url);
    } catch (_) {
      // Stay on placeholder.
    }
  }

  Widget _placeholder() => Container(
        height: 220,
        decoration: const BoxDecoration(
          color: AppColors.bgInset,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.image_outlined,
                size: 32,
                color: AppColors.ink3,
              ),
              const SizedBox(height: 6),
              Text(
                'Loading receipt…',
                style: AppTypography.geist(fontSize: 13, color: AppColors.ink3),
              ),
            ],
          ),
        ),
      );

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
              top: 8,
              right: 8,
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

// ────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────

String _amountOnly(Expense e) =>
    NumberFormat.decimalPattern('en_US').format(e.amount.amountMinor / 100.0);

String _amountForOne(Expense e) {
  final int unitMinor = (e.amount.amountMinor / e.quantity).round();
  return NumberFormat.decimalPattern('en_US').format(unitMinor / 100.0);
}

String _safeSource(DemoStore store, String id) {
  try {
    return store.sourceById(id).name;
  } catch (_) {
    return 'Source';
  }
}

String _safeCategory(DemoStore store, String code) {
  try {
    return store.categoryByCode(code).nameEn;
  } catch (_) {
    return code;
  }
}

String _safeUser(DemoStore store, String id) {
  try {
    return store.userById(id).displayName;
  } catch (_) {
    return 'Unknown';
  }
}

IconData _iconForCategory(String code) {
  switch (code.toUpperCase()) {
    case 'FOOD':
      return Icons.local_cafe_outlined;
    case 'TRANSPORT':
      return Icons.directions_car_outlined;
    case 'HOTEL':
      return Icons.bed_outlined;
    case 'PHONE':
      return Icons.phone_outlined;
    case 'ENTERTAINMENT':
      return Icons.celebration_outlined;
    case 'TIPS':
      return Icons.card_giftcard_outlined;
    case 'TRAVEL':
      return Icons.flight_takeoff_outlined;
    case 'OTHERS':
    default:
      return Icons.more_horiz_outlined;
  }
}

// ────────────────────────────────────────────────────────────────────
// Comments thread + reply composer
// ────────────────────────────────────────────────────────────────────

/// Shows the comment thread for an expense and lets the viewer reply.
/// Lives at the bottom of the expense detail page. Replies use the same
/// /expenses/{id}/comments endpoint as the admin's question — no separate
/// "reply" affordance, every comment is just a comment in the same thread.
class _CommentsThread extends ConsumerStatefulWidget {
  const _CommentsThread({required this.expense, required this.currentUserId});
  final Expense expense;
  final String? currentUserId;

  @override
  ConsumerState<_CommentsThread> createState() => _CommentsThreadState();
}

class _CommentsThreadState extends ConsumerState<_CommentsThread> {
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

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Comments',
                style: AppTypography.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              async.maybeWhen(
                data: (List<ExpenseComment> list) => Text(
                  '${list.length}',
                  style: AppTypography.geist(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (Object e, _) => Text(
              'Could not load comments: $e',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.outflow,
              ),
            ),
            data: (List<ExpenseComment> list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'No comments yet. Be the first to ask or reply.',
                    style: AppTypography.geist(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                );
              }
              return Column(
                children: <Widget>[
                  for (final ExpenseComment c in list)
                    _CommentBubble(
                      comment: c,
                      store: store,
                      mine: widget.currentUserId != null &&
                          widget.currentUserId == c.authorId,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Write a reply…',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  visualDensity: VisualDensity.compact,
                ),
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 18),
              ),
            ],
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.outflow,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
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
      // No @mentions on member replies in v1 — admin sees the comment in
      // their CMS view of the expense anyway. Adding a mention picker for
      // members is a follow-up.
      await ref.read(expenseCommentRepositoryProvider).post(
            expenseId: widget.expense.id,
            body: body,
          );
      _ctrl.clear();
      ref.invalidate(expenseCommentsProvider(widget.expense.id));
    } catch (e) {
      setState(() => _error = 'Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.comment,
    required this.store,
    required this.mine,
  });
  final ExpenseComment comment;
  final DemoStore store;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    String authorName;
    try {
      authorName = store.userById(comment.authorId).displayName;
    } catch (_) {
      authorName = 'Someone';
    }
    final String time = DateFormat('d MMM · HH:mm').format(
      comment.createdAt.toLocal(),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: <Widget>[
          if (!mine)
            _AuthorAvatar(name: authorName, color: AppColors.brandBrown),
          if (!mine) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: mine ? AppColors.brandTint : AppColors.cream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    mine ? 'You · $time' : '$authorName · $time',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comment.body,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (mine) const SizedBox(width: 8),
          if (mine)
            _AuthorAvatar(name: authorName, color: AppColors.brand),
        ],
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final List<String> parts = name.split(' ')
        .where((String p) => p.isNotEmpty)
        .toList();
    String initials;
    if (parts.isEmpty) {
      initials = '?';
    } else if (parts.length == 1) {
      initials = parts.first.substring(0, 1).toUpperCase();
    } else {
      initials = (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}
