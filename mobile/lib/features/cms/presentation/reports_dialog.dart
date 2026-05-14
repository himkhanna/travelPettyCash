import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../expenses/domain/expense.dart';
import '../../funds/domain/funding.dart';
import '../../trips/domain/trip.dart';

/// Per CLAUDE.md §10 the four production report types are server-rendered
/// (Apache POI / iText) and downloaded via signed URL. For the demo we show
/// a printable preview here — the user can use the browser's "Save as PDF"
/// to export a real file.
enum ReportKind { user, tripFull, financeLetter, directorGeneral }

Future<void> showReportsCatalog(
  BuildContext context, {
  required Trip trip,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext _) => _ReportsCatalog(trip: trip),
  );
}

class _ReportsCatalog extends ConsumerWidget {
  const _ReportsCatalog({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.description_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Reports — ${trip.name}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Production reports are server-generated (Apache POI for xlsx, '
                'iText/OpenPDF for pdf), then digitally signed with PAdES per '
                'CLAUDE.md §10. The demo previews show the same data the '
                'server template will format — use browser Save As PDF.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: <Widget>[
                  _ReportCard(
                    title: 'USER REPORT',
                    subtitle: 'Single user expenses for finance.\nXLSX + PDF.',
                    icon: Icons.person_outline,
                    onTap: () => _showPreview(context, ReportKind.user),
                  ),
                  _ReportCard(
                    title: 'TRIP FULL',
                    subtitle: 'Every expense by every member with receipts.\nXLSX.',
                    icon: Icons.flight,
                    onTap: () => _showPreview(context, ReportKind.tripFull),
                  ),
                  _ReportCard(
                    title: 'FINANCE LETTER',
                    subtitle: 'Letterhead summary of sources used + balance returned.\nSigned PDF.',
                    icon: Icons.draw_outlined,
                    onTap: () =>
                        _showPreview(context, ReportKind.financeLetter),
                  ),
                  _ReportCard(
                    title: 'DG REPORT',
                    subtitle: 'Per-user / per-category roll-up.\nRead-only PDF.',
                    icon: Icons.shield_outlined,
                    onTap: () => _showPreview(
                      context,
                      ReportKind.directorGeneral,
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

  void _showPreview(BuildContext context, ReportKind kind) {
    showDialog<void>(
      context: context,
      builder: (BuildContext _) => _ReportPreviewDialog(kind: kind, trip: trip),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 160,
      child: Material(
        color: AppColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: AppColors.brandBrown, size: 28),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Row(
                  children: <Widget>[
                    Text(
                      'PREVIEW',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.brandBrown,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.brandBrown,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportPreviewDialog extends ConsumerWidget {
  const _ReportPreviewDialog({required this.kind, required this.trip});
  final ReportKind kind;
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DemoStore store = ref.read(demoStoreProvider);
    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 900),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Text(
                    _title(kind),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('PRINT / SAVE AS PDF'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Open browser print (Ctrl/⌘+P) to save this preview as PDF.',
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: _ReportBody(kind: kind, trip: trip, store: store),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _title(ReportKind k) {
    switch (k) {
      case ReportKind.user:
        return 'User Report';
      case ReportKind.tripFull:
        return 'Trip Full Report';
      case ReportKind.financeLetter:
        return 'Finance Department Letter';
      case ReportKind.directorGeneral:
        return 'DG Report';
    }
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.kind,
    required this.trip,
    required this.store,
  });

  final ReportKind kind;
  final Trip trip;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case ReportKind.user:
        return _UserReport(trip: trip, store: store);
      case ReportKind.tripFull:
        return _TripFullReport(trip: trip, store: store);
      case ReportKind.financeLetter:
        return _FinanceLetter(trip: trip, store: store);
      case ReportKind.directorGeneral:
        return _DgReport(trip: trip, store: store);
    }
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.title, required this.trip});
  final String title;
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.brandBrown,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.flight, color: AppColors.cream),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'PROTOCOL DEPARTMENT, GOVERNMENT OF DUBAI',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                Text(
                  'دائرة التشريفات والضيافة — دبي',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${trip.name} · ${trip.countryName} · ${DateFormat.yMMMd().format(trip.createdAt)}'
          '${trip.closedAt != null ? ' → ${DateFormat.yMMMd().format(trip.closedAt!)}' : ''}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Divider(),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _UserReport extends StatelessWidget {
  const _UserReport({required this.trip, required this.store});
  final Trip trip;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    final String userId = trip.leaderId;
    final List<Expense> expenses =
        store.expenses
            .where((Expense e) => e.tripId == trip.id && e.userId == userId)
            .toList()
          ..sort((Expense a, Expense b) => a.occurredAt.compareTo(b.occurredAt));

    final Map<String, List<Expense>> bySource = <String, List<Expense>>{};
    for (final Expense e in expenses) {
      bySource.putIfAbsent(e.sourceId, () => <Expense>[]).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ReportHeader(title: 'User Report', trip: trip),
        Text(
          'PREPARED FOR FINANCE — ${store.userById(userId).displayName}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final MapEntry<String, List<Expense>> g in bySource.entries) ...<Widget>[
          Text(
            store.sourceById(g.key).name.toUpperCase(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.brandBrown,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ExpenseTable(rows: g.value, store: store),
          const SizedBox(height: AppSpacing.lg),
        ],
        const Divider(),
        _TotalLine(label: 'TOTAL', amount: _sum(expenses, trip.currency)),
      ],
    );
  }
}

class _TripFullReport extends StatelessWidget {
  const _TripFullReport({required this.trip, required this.store});
  final Trip trip;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    final List<Expense> expenses =
        store.expenses.where((Expense e) => e.tripId == trip.id).toList()
          ..sort((Expense a, Expense b) => a.occurredAt.compareTo(b.occurredAt));

    final Map<String, List<Expense>> byUser = <String, List<Expense>>{};
    for (final Expense e in expenses) {
      byUser.putIfAbsent(e.userId, () => <Expense>[]).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ReportHeader(title: 'Trip Full Report', trip: trip),
        for (final MapEntry<String, List<Expense>> g in byUser.entries) ...<Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.brandBrown,
                child: Text(
                  store.userById(g.key).displayName.substring(0, 1),
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                store.userById(g.key).displayName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(_sum(g.value, trip.currency).format()),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ExpenseTable(rows: g.value, store: store),
          const SizedBox(height: AppSpacing.lg),
        ],
        const Divider(),
        _TotalLine(label: 'TRIP TOTAL', amount: _sum(expenses, trip.currency)),
      ],
    );
  }
}

class _FinanceLetter extends StatelessWidget {
  const _FinanceLetter({required this.trip, required this.store});
  final Trip trip;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    final List<Source> sources = store.sources;
    final Money totalBudget = trip.totalBudget;
    final List<Expense> expenses = store.expenses
        .where((Expense e) => e.tripId == trip.id)
        .toList();
    final Money totalSpent = _sum(expenses, trip.currency);
    final Money returned = totalBudget - totalSpent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ReportHeader(title: 'Finance Department Letter', trip: trip),
        Text(
          'To the Finance Department,',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Please find below the reconciliation for the delegation to '
          '${trip.countryName} held between ${DateFormat.yMMMd().format(trip.createdAt)} and '
          '${trip.closedAt != null ? DateFormat.yMMMd().format(trip.closedAt!) : 'present'}. '
          'The funds advanced from each source are listed against the total '
          'expense incurred. Any positive remainder will be returned to '
          'the appropriate pool.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'SOURCES',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.brandBrown,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final Source s in sources) ...<Widget>[
          _KvRow(
            label: s.name,
            valueLabel:
                'Advanced ${_advancedFor(s.id, trip).format()} / Spent ${_spentFor(s.id, trip, store).format()}',
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const Divider(),
        _TotalLine(label: 'TOTAL ADVANCED', amount: totalBudget),
        _TotalLine(label: 'TOTAL SPENT', amount: totalSpent),
        _TotalLine(
          label: 'NET BALANCE TO RETURN',
          amount: returned,
          highlight: true,
        ),
        const SizedBox(height: AppSpacing.xl),
        const Divider(),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: const BorderRadius.all(AppRadii.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.gpp_good_outlined, color: AppColors.success),
              const SizedBox(height: 4),
              Text(
                'DIGITALLY SIGNED (PAdES) — preview only',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Signed by Admin via HSM/PKCS#11 in production (CLAUDE.md §10). '
                'In this demo the signature is illustrative only.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Money _advancedFor(String sourceId, Trip trip) {
    Money total = Money.zero(trip.currency);
    for (final dynamic a in store.allocations) {
      if (a.tripId != trip.id || a.sourceId != sourceId) continue;
      if (a.fromUserId != null) continue;
      if (a.status.toString().contains('accepted')) {
        total += a.amount as Money;
      }
    }
    return total;
  }

  Money _spentFor(String sourceId, Trip trip, DemoStore store) {
    Money total = Money.zero(trip.currency);
    for (final Expense e in store.expenses) {
      if (e.tripId != trip.id || e.sourceId != sourceId) continue;
      total += e.amount;
    }
    return total;
  }
}

class _DgReport extends StatelessWidget {
  const _DgReport({required this.trip, required this.store});
  final Trip trip;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    final List<Expense> expenses = store.expenses
        .where((Expense e) => e.tripId == trip.id)
        .toList();

    // Per-user
    final Map<String, Money> byUser = <String, Money>{};
    for (final Expense e in expenses) {
      byUser.update(
        e.userId,
        (Money v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
    }
    // Per-category
    final Map<String, Money> byCat = <String, Money>{};
    for (final Expense e in expenses) {
      byCat.update(
        e.categoryCode,
        (Money v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ReportHeader(title: 'Director General Report', trip: trip),
        Text(
          'PER MEMBER',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.brandBrown,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final MapEntry<String, Money> g in byUser.entries)
          _KvRow(
            label: _safeUserName(store, g.key),
            valueLabel: g.value.format(),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'PER CATEGORY',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.brandBrown,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final MapEntry<String, Money> g in byCat.entries)
          _KvRow(
            label: _safeCategoryName(store, g.key),
            valueLabel: g.value.format(),
          ),
        const SizedBox(height: AppSpacing.lg),
        const Divider(),
        _TotalLine(label: 'TRIP TOTAL', amount: _sum(expenses, trip.currency)),
      ],
    );
  }

  String _safeUserName(DemoStore store, String id) {
    try {
      return store.userById(id).displayName;
    } catch (_) {
      return id;
    }
  }

  String _safeCategoryName(DemoStore store, String code) {
    try {
      return store.categoryByCode(code).nameEn;
    } catch (_) {
      return code;
    }
  }
}

class _ExpenseTable extends StatelessWidget {
  const _ExpenseTable({required this.rows, required this.store});
  final List<Expense> rows;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Column(
        children: <Widget>[
          Container(
            color: AppColors.cream,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 4,
            ),
            child: Row(
              children: const <Widget>[
                Expanded(flex: 2, child: Text('DATE')),
                Expanded(flex: 2, child: Text('CATEGORY')),
                Expanded(
                  flex: 4,
                  child: Text('DETAILS'),
                ),
                Expanded(
                  flex: 2,
                  child: Text('AMOUNT', textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
          for (final Expense e in rows)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: Text(DateFormat.yMd().format(e.occurredAt)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(_safeCategoryName(store, e.categoryCode)),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      e.details.isEmpty ? '—' : e.details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      e.amount.format(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _safeCategoryName(DemoStore store, String code) {
    try {
      return store.categoryByCode(code).nameEn;
    } catch (_) {
      return code;
    }
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.valueLabel});
  final String label;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Text(
            valueLabel,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({
    required this.label,
    required this.amount,
    this.highlight = false,
  });
  final String label;
  final Money amount;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: highlight
                    ? AppColors.brandBrown
                    : AppColors.textPrimary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Text(
            amount.format(),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: highlight ? 18 : 14,
              color: amount.isNegative
                  ? AppColors.outflow
                  : (highlight
                        ? AppColors.brandBrown
                        : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

Money _sum(List<Expense> list, String currency) {
  Money total = Money.zero(currency);
  for (final Expense e in list) {
    total += e.amount;
  }
  return total;
}
