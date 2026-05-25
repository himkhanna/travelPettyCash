import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import 'widgets/cms_theme.dart';
import '../../../core/l10n/locale_names.dart';
import '../../../core/money/money.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
import '../../funds/domain/funding.dart';
import '../../reports/application/report_download_providers.dart';
import '../../reports/application/signature_providers.dart';
import '../../reports/data/report_download_repository.dart';
import '../../reports/domain/signed_report.dart';
import '../../reports/presentation/save_to_disk.dart';
import '../../reports/presentation/sign_report_modal.dart';
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
    final AppLocalizations l = AppLocalizations.of(context);
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
                    l.reports_title_for(trip.name),
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
                l.reports_intro,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CmsColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: <Widget>[
                  _ReportCard(
                    title: l.reports_card_user_title,
                    subtitle: l.reports_card_user_subtitle,
                    icon: Icons.person_outline,
                    onTap: () => _showPreview(context, ReportKind.user),
                  ),
                  _ReportCard(
                    title: l.reports_card_trip_title,
                    subtitle: l.reports_card_trip_subtitle,
                    icon: Icons.flight,
                    onTap: () => _showPreview(context, ReportKind.tripFull),
                  ),
                  _ReportCard(
                    title: l.reports_card_finance_title,
                    subtitle: l.reports_card_finance_subtitle,
                    icon: Icons.draw_outlined,
                    onTap: () =>
                        _showPreview(context, ReportKind.financeLetter),
                  ),
                  _ReportCard(
                    title: l.reports_card_dg_title,
                    subtitle: l.reports_card_dg_subtitle,
                    icon: Icons.shield_outlined,
                    onTap: () => _showPreview(
                      context,
                      ReportKind.directorGeneral,
                    ),
                  ),
                  // Daily snapshot — picks a date, then downloads the
                  // trip-full XLSX restricted to that one UTC day.
                  _ReportCard(
                    title: 'DAILY',
                    subtitle:
                        'One day of expenses on this trip, ready to '
                        'send to finance.',
                    icon: Icons.today,
                    onTap: () => _downloadDaily(context, ref),
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

  /// Daily report: prompt for a date, then download the day-scoped XLSX
  /// directly (no preview — the XLSX speaks for itself once it opens).
  Future<void> _downloadDaily(BuildContext context, WidgetRef ref) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now.add(const Duration(days: 1)),
      initialDate: now,
    );
    if (picked == null || !context.mounted) return;
    try {
      final DownloadedReport report = await ref
          .read(reportDownloadRepositoryProvider)
          .download(
            kind: ReportDownloadKind.tripDaily,
            tripId: trip.id,
            date: picked,
            format: ReportFormat.xlsx,
          );
      saveBytesToDisk(
        bytes: report.bytes,
        filename: report.filename,
        contentType: report.contentType,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded ${report.filename}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Daily report download failed: $e'),
          backgroundColor: CmsColors.outflow,
        ),
      );
    }
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
        color: CmsColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: CmsColors.brandBrown, size: 28),
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
                    color: CmsColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Row(
                  children: <Widget>[
                    Text(
                      AppLocalizations.of(context).reports_card_preview,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: CmsColors.brandBrown,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      color: CmsColors.brandBrown,
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

class _ReportPreviewDialog extends ConsumerStatefulWidget {
  const _ReportPreviewDialog({required this.kind, required this.trip});
  final ReportKind kind;
  final Trip trip;

  @override
  ConsumerState<_ReportPreviewDialog> createState() =>
      _ReportPreviewDialogState();
}

class _ReportPreviewDialogState extends ConsumerState<_ReportPreviewDialog> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final DemoStore store = ref.read(demoStoreProvider);
    final AppLocalizations l = AppLocalizations.of(context);
    // Load expenses for this trip from the live provider, then pass the
    // list down to every report-section widget. Previously each section
    // read store.expenses directly which only reflected hydration-time data.
    final AsyncValue<List<Expense>> expensesAsync =
        ref.watch(tripExpensesProvider(widget.trip.id));
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
                  Expanded(
                    child: Text(
                      _title(l, widget.kind),
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ..._downloadButtons(),
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
                child: expensesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (Object e, _) => Text('Could not load expenses: $e'),
                  data: (List<Expense> expenses) => _ReportBody(
                    kind: widget.kind,
                    trip: widget.trip,
                    store: store,
                    expenses: expenses,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// PDF is always offered. XLSX is offered for the two tabular reports
  /// (User and Trip Full). Finance Letter + DG are PDF-only.
  List<Widget> _downloadButtons() {
    final ReportDownloadKind kind = _downloadKind(widget.kind);
    final bool xlsxAvailable = kind == ReportDownloadKind.user ||
        kind == ReportDownloadKind.tripFull;

    final ButtonStyle compact = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      visualDensity: VisualDensity.compact,
    );

    return <Widget>[
      OutlinedButton.icon(
        style: compact,
        icon: _downloading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.picture_as_pdf, size: 18),
        label: const Text('PDF'),
        onPressed: _downloading
            ? null
            : () => _download(kind, ReportFormat.pdf),
      ),
      if (xlsxAvailable) ...<Widget>[
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton.icon(
          style: compact,
          icon: _downloading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.table_chart_outlined, size: 18),
          label: const Text('EXCEL'),
          onPressed: _downloading
              ? null
              : () => _download(kind, ReportFormat.xlsx),
        ),
      ],
      const SizedBox(width: AppSpacing.sm),
    ];
  }

  ReportDownloadKind _downloadKind(ReportKind k) {
    switch (k) {
      case ReportKind.user:
        return ReportDownloadKind.user;
      case ReportKind.tripFull:
        return ReportDownloadKind.tripFull;
      case ReportKind.financeLetter:
        return ReportDownloadKind.financeLetter;
      case ReportKind.directorGeneral:
        return ReportDownloadKind.dg;
    }
  }

  Future<void> _download(ReportDownloadKind kind, ReportFormat format) async {
    setState(() => _downloading = true);
    try {
      final DownloadedReport report = await ref
          .read(reportDownloadRepositoryProvider)
          .download(
            kind: kind,
            tripId: widget.trip.id,
            userId: kind == ReportDownloadKind.user
                ? widget.trip.leaderId
                : null,
            format: format,
          );
      saveBytesToDisk(
        bytes: report.bytes,
        filename: report.filename,
        contentType: report.contentType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded ${report.filename}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String _title(AppLocalizations l, ReportKind k) {
    switch (k) {
      case ReportKind.user:
        return l.reports_preview_user_title;
      case ReportKind.tripFull:
        return l.reports_preview_trip_title;
      case ReportKind.financeLetter:
        return l.reports_preview_finance_title;
      case ReportKind.directorGeneral:
        return l.reports_preview_dg_title;
    }
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.kind,
    required this.trip,
    required this.store,
    required this.expenses,
  });

  final ReportKind kind;
  final Trip trip;
  final DemoStore store;
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case ReportKind.user:
        return _UserReport(trip: trip, store: store, expenses: expenses);
      case ReportKind.tripFull:
        return _TripFullReport(trip: trip, store: store, expenses: expenses);
      case ReportKind.financeLetter:
        return _FinanceLetter(trip: trip, store: store, expenses: expenses);
      case ReportKind.directorGeneral:
        return _DgReport(trip: trip, store: store, expenses: expenses);
    }
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.title, required this.trip});
  final String title;
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: CmsColors.brandBrown,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.flight, color: CmsColors.cream),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.reports_body_letterhead_en,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                Text(
                  l.reports_body_letterhead_ar,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CmsColors.textSecondary,
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
          '${trip.name} · ${trip.countryName} · ${DateFormat.yMMMd(l.localeName).format(trip.createdAt)}'
          '${trip.closedAt != null ? ' → ${DateFormat.yMMMd(l.localeName).format(trip.closedAt!)}' : ''}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: CmsColors.textSecondary,
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
  const _UserReport({
    required this.trip,
    required this.store,
    required this.expenses,
  });
  final Trip trip;
  final DemoStore store;
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final String userId = trip.leaderId;
    final List<Expense> filtered =
        expenses.where((Expense e) => e.userId == userId).toList()
          ..sort((Expense a, Expense b) => a.occurredAt.compareTo(b.occurredAt));

    final Map<String, List<Expense>> bySource = <String, List<Expense>>{};
    for (final Expense e in filtered) {
      bySource.putIfAbsent(e.sourceId, () => <Expense>[]).add(e);
    }

    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ReportHeader(
          title: l.reports_preview_user_title,
          trip: trip,
        ),
        Text(
          l.reports_body_user_prepared_for(store.userById(userId).displayName),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final MapEntry<String, List<Expense>> g in bySource.entries) ...<Widget>[
          Text(
            store.sourceById(g.key).localizedName(context).toUpperCase(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: CmsColors.brandBrown,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ExpenseTable(rows: g.value, store: store),
          const SizedBox(height: AppSpacing.lg),
        ],
        const Divider(),
        _TotalLine(label: l.reports_body_total, amount: _sum(filtered, trip.currency)),
      ],
    );
  }
}

class _TripFullReport extends StatelessWidget {
  const _TripFullReport({
    required this.trip,
    required this.store,
    required this.expenses,
  });
  final Trip trip;
  final DemoStore store;
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final List<Expense> sorted = <Expense>[...expenses]
      ..sort((Expense a, Expense b) => a.occurredAt.compareTo(b.occurredAt));

    final Map<String, List<Expense>> byUser = <String, List<Expense>>{};
    for (final Expense e in sorted) {
      byUser.putIfAbsent(e.userId, () => <Expense>[]).add(e);
    }

    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ReportHeader(
          title: l.reports_preview_trip_title,
          trip: trip,
        ),
        for (final MapEntry<String, List<Expense>> g in byUser.entries) ...<Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 14,
                backgroundColor: CmsColors.brandBrown,
                child: Text(
                  store.userById(g.key).displayName.substring(0, 1),
                  style: const TextStyle(
                    color: CmsColors.cream,
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
        _TotalLine(label: l.reports_body_trip_total, amount: _sum(expenses, trip.currency)),
      ],
    );
  }
}

class _FinanceLetter extends ConsumerWidget {
  const _FinanceLetter({
    required this.trip,
    required this.store,
    required this.expenses,
  });
  final Trip trip;
  final DemoStore store;
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<Source> sources = store.sources;
    final Money totalBudget = trip.totalBudget;
    final Money totalSpent = _sum(expenses, trip.currency);
    final Money returned = totalBudget - totalSpent;

    final AsyncValue<SignedReport?> signedAsync = ref.watch(
      latestSignatureProvider((
        tripId: trip.id,
        reportKind: ReportKind.financeLetter.name,
      )),
    );

    final String startDate = DateFormat.yMMMd(l.localeName).format(trip.createdAt);
    final String endDate = trip.closedAt != null
        ? DateFormat.yMMMd(l.localeName).format(trip.closedAt!)
        : l.reports_body_finance_endate_open;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ReportHeader(title: l.reports_preview_finance_title, trip: trip),
        Text(
          l.reports_body_finance_greeting,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l.reports_body_finance_paragraph(trip.countryName, startDate, endDate),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l.reports_body_sources,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: CmsColors.brandBrown,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final Source s in sources) ...<Widget>[
          _KvRow(
            label: s.localizedName(context),
            valueLabel: l.reports_body_source_advanced_spent(
              _advancedFor(s.id, trip).format(),
              _spentFor(s.id, trip, expenses).format(),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const Divider(),
        _TotalLine(label: l.reports_body_total_advanced, amount: totalBudget),
        _TotalLine(label: l.reports_body_total_spent, amount: totalSpent),
        _TotalLine(
          label: l.reports_body_net_balance_to_return,
          amount: returned,
          highlight: true,
        ),
        const SizedBox(height: AppSpacing.xl),
        const Divider(),
        const SizedBox(height: AppSpacing.lg),
        _SignaturePanel(tripId: trip.id, signedAsync: signedAsync),
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

  Money _spentFor(String sourceId, Trip trip, List<Expense> expenses) {
    Money total = Money.zero(trip.currency);
    for (final Expense e in expenses) {
      if (e.sourceId != sourceId) continue;
      total += e.amount;
    }
    return total;
  }
}

/// Sign-or-signed panel at the foot of the Finance Letter preview.
class _SignaturePanel extends StatelessWidget {
  const _SignaturePanel({required this.tripId, required this.signedAsync});

  final String tripId;
  final AsyncValue<SignedReport?> signedAsync;

  Future<void> _openModal(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) => SignReportModal(
        tripId: tripId,
        reportKind: ReportKind.financeLetter.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return signedAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: LinearProgressIndicator(),
      ),
      error: (Object e, _) => Text(l.reports_signature_lookup_error('$e')),
      data: (SignedReport? signed) {
        final bool isSigned = signed != null;
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: CmsColors.cream,
            borderRadius: const BorderRadius.all(AppRadii.card),
            border: Border.all(color: CmsColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    isSigned
                        ? Icons.verified_outlined
                        : Icons.draw_outlined,
                    color: isSigned
                        ? CmsColors.success
                        : CmsColors.brandBrown,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      isSigned
                          ? l.reports_signed_badge
                          : l.reports_sign_status_unsigned,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: isSigned
                            ? CmsColors.success
                            : CmsColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  // Compact overrides: global theme's
                  // minimumSize=(double.infinity, 48) would push this
                  // button past the Expanded(Text) and overflow the row.
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      isSigned ? Icons.refresh : Icons.draw_outlined,
                      size: 18,
                    ),
                    label: Text(
                      isSigned ? l.reports_signed_resign : l.reports_sign_action,
                    ),
                    onPressed: () => _openModal(context),
                  ),
                ],
              ),
              if (isSigned) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                _KvRow(
                  label: l.reports_signed_by,
                  valueLabel:
                      '${signed.signerDisplayName} · ${signed.signerRoleLabel}',
                ),
                _KvRow(
                  label: l.reports_signed_at,
                  valueLabel: DateFormat('yyyy-MM-dd HH:mm:ss')
                      .format(signed.signedAt.toLocal()),
                ),
                _KvRow(
                  label: l.reports_signed_thumbprint,
                  valueLabel: signed.certThumbprint,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DgReport extends StatelessWidget {
  const _DgReport({
    required this.trip,
    required this.store,
    required this.expenses,
  });
  final Trip trip;
  final DemoStore store;
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {

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

    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ReportHeader(
          title: l.reports_preview_dg_title,
          trip: trip,
        ),
        Text(
          l.reports_body_per_member,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: CmsColors.brandBrown,
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
          l.reports_body_per_category,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: CmsColors.brandBrown,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final MapEntry<String, Money> g in byCat.entries)
          _KvRow(
            label: _safeCategoryName(context, store, g.key),
            valueLabel: g.value.format(),
          ),
        const SizedBox(height: AppSpacing.lg),
        const Divider(),
        _TotalLine(label: l.reports_body_trip_total, amount: _sum(expenses, trip.currency)),
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

  String _safeCategoryName(BuildContext context, DemoStore store, String code) {
    try {
      return store.categoryByCode(code).localizedName(context);
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
    final AppLocalizations l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: CmsColors.divider),
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Column(
        children: <Widget>[
          Container(
            color: CmsColors.cream,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 4,
            ),
            child: Row(
              children: <Widget>[
                Expanded(flex: 2, child: Text(l.reports_table_date)),
                Expanded(flex: 2, child: Text(l.reports_table_category)),
                Expanded(
                  flex: 4,
                  child: Text(l.reports_table_details),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    l.reports_table_amount,
                    textAlign: TextAlign.right,
                  ),
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
                border: Border(top: BorderSide(color: CmsColors.divider)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: Text(
                      DateFormat.yMd(l.localeName).format(e.occurredAt),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(_safeCategoryName(context, store, e.categoryCode)),
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

  String _safeCategoryName(BuildContext context, DemoStore store, String code) {
    try {
      return store.categoryByCode(code).localizedName(context);
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
                    ? CmsColors.brandBrown
                    : CmsColors.textPrimary,
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
                  ? CmsColors.outflow
                  : (highlight
                        ? CmsColors.brandBrown
                        : CmsColors.textPrimary),
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
