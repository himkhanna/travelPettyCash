import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../reports/application/report_providers.dart';
import '../../reports/data/report_repository.dart';
import '../../reports/domain/report.dart';
import '../../trips/domain/trip.dart';

/// Slice 3D — Reports dialog for the CMS / web admin console.
///
/// Per CLAUDE.md §10 the four production report types are server-rendered
/// (Apache POI / iText) and downloaded via signed URL. The dialog asks the
/// backend (`GET /api/v1/reports/trip/{id}?type=...&format=...`), surfaces
/// the returned URL via a DOWNLOAD button, and respects the role-based
/// permissions in §7.
///
/// `url_launcher` is intentionally not on the dep list (see slice 3 rules)
/// so we fall back to clipboard copy + toast — same affordance the
/// Vercel preview already uses for "share this trip".
Future<void> showReportsCatalog(
  BuildContext context, {
  required Trip trip,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext _) => _ReportsDialog(trip: trip),
  );
}

class _ReportsDialog extends ConsumerStatefulWidget {
  const _ReportsDialog({required this.trip});
  final Trip trip;

  @override
  ConsumerState<_ReportsDialog> createState() => _ReportsDialogState();
}

class _ReportsDialogState extends ConsumerState<_ReportsDialog> {
  final Map<ReportType, ReportFormat> _selectedFormat =
      <ReportType, ReportFormat>{};
  final Map<ReportType, ReportRecord?> _generated =
      <ReportType, ReportRecord?>{};
  final Set<ReportType> _generating = <ReportType>{};
  final Map<ReportType, Object> _errors = <ReportType, Object>{};

  @override
  Widget build(BuildContext context) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.description_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Reports — ${widget.trip.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Server-generated via Apache POI (xlsx) and iText / OpenPDF (pdf). '
                'Signing is deferred per ADR-003 — the signed Finance Letter '
                'lands once the HSM custody decision is finalised.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: <Widget>[
                  for (final ReportType type in ReportType.values)
                    SizedBox(
                      width: 320,
                      child: _ReportCard(
                        type: type,
                        allowed: me != null && type.allowedRoles.contains(me.role),
                        selectedFormat: _selectedFormat[type] ??
                            type.supportedFormats.first,
                        onFormatChanged: (ReportFormat f) =>
                            setState(() => _selectedFormat[type] = f),
                        record: _generated[type],
                        generating: _generating.contains(type),
                        error: _errors[type],
                        onGenerate: () => _generate(type),
                        onDownload: () => _download(_generated[type]!),
                        onSign: type == ReportType.finance
                            ? () => _sign(type)
                            : null,
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

  Future<void> _generate(ReportType type) async {
    final ReportFormat format =
        _selectedFormat[type] ?? type.supportedFormats.first;
    setState(() {
      _generating.add(type);
      _errors.remove(type);
    });
    try {
      final ReportRecord r = await ref
          .read(reportRepositoryProvider)
          .generate(
            tripId: widget.trip.id,
            type: type,
            format: format,
          );
      if (!mounted) return;
      setState(() {
        _generated[type] = r;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[type] = e;
      });
    } finally {
      if (mounted) {
        setState(() => _generating.remove(type));
      }
    }
  }

  Future<void> _download(ReportRecord r) async {
    // url_launcher would be the production path; we copy to clipboard so
    // the demo doesn't grow a dep just for one button. The user pastes
    // the data: URL into a new tab and the browser handles the download.
    await Clipboard.setData(ClipboardData(text: r.url));
    if (!mounted) return;
    final AppLocalizations l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.report_copiedLink)),
    );
  }

  Future<void> _sign(ReportType type) async {
    // Always 501 SIGNING_DEFERRED in v1 — the UI shows a tooltip pointing
    // at ADR-003. We keep the network call so the audit log records the
    // attempt.
    final ReportRecord? r = _generated[type];
    if (r == null) return;
    final ReportRecord? signed =
        await ref.read(reportRepositoryProvider).sign(r.sha256);
    if (!mounted) return;
    if (signed == null) {
      final AppLocalizations l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.report_signing_deferred)),
      );
    }
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.type,
    required this.allowed,
    required this.selectedFormat,
    required this.onFormatChanged,
    required this.record,
    required this.generating,
    required this.error,
    required this.onGenerate,
    required this.onDownload,
    this.onSign,
  });

  final ReportType type;
  final bool allowed;
  final ReportFormat selectedFormat;
  final ValueChanged<ReportFormat> onFormatChanged;
  final ReportRecord? record;
  final bool generating;
  final Object? error;
  final VoidCallback onGenerate;
  final VoidCallback onDownload;
  final VoidCallback? onSign;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Set<ReportFormat> formats = type.supportedFormats;
    return Material(
      color: AppColors.cream,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_iconFor(type), color: AppColors.brandBrown, size: 28),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _labelFor(type, l),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _subtitleFor(type),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Format radios — only render when there's more than one
            // choice; otherwise the format is implicit.
            if (formats.length > 1)
              Row(
                children: <Widget>[
                  for (final ReportFormat f in formats)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(_formatLabel(f, l)),
                        selected: selectedFormat == f,
                        onSelected: allowed
                            ? (_) => onFormatChanged(f)
                            : null,
                      ),
                    ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
                child: Text(
                  _formatLabel(formats.single, l),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            if (!allowed)
              Text(
                'Not permitted for your role.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
              )
            else if (record != null) ...<Widget>[
              FilledButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download, size: 18),
                label: Text(l.report_download),
              ),
              if (onSign != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Tooltip(
                  message: l.report_signing_deferred,
                  child: OutlinedButton.icon(
                    onPressed: null, // disabled per ADR-003
                    icon: const Icon(Icons.draw_outlined, size: 18),
                    label: const Text('SIGN AND SEND'),
                  ),
                ),
              ],
            ] else
              FilledButton(
                onPressed: generating ? null : onGenerate,
                child: generating
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.cream,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(l.report_generating),
                        ],
                      )
                    : Text(l.report_generate),
              ),
            if (error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${l.common_error}: $error',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.outflow,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconFor(ReportType t) {
    switch (t) {
      case ReportType.user:
        return Icons.person_outline;
      case ReportType.trip:
        return Icons.flight;
      case ReportType.finance:
        return Icons.draw_outlined;
      case ReportType.dg:
        return Icons.shield_outlined;
    }
  }

  String _labelFor(ReportType t, AppLocalizations l) {
    switch (t) {
      case ReportType.user:
        return l.report_user;
      case ReportType.trip:
        return l.report_trip;
      case ReportType.finance:
        return l.report_finance;
      case ReportType.dg:
        return l.report_dg;
    }
  }

  String _subtitleFor(ReportType t) {
    switch (t) {
      case ReportType.user:
        return "Single user's expenses for finance — grouped by source then category.";
      case ReportType.trip:
        return 'Every expense by every member with receipt thumbnails.';
      case ReportType.finance:
        return 'Letterhead summary of sources used + balance returned. Signed PDF.';
      case ReportType.dg:
        return 'Per-member and per-category totals for the Director General.';
    }
  }

  String _formatLabel(ReportFormat f, AppLocalizations l) {
    switch (f) {
      case ReportFormat.xlsx:
        return l.report_format_xlsx;
      case ReportFormat.pdf:
        return l.report_format_pdf;
    }
  }
}
