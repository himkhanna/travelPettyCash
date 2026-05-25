import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart' show AppRadii, AppSpacing;
import '../../../core/api/hydration_service.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/domain/expense.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../../missions/application/mission_providers.dart';
import '../../missions/domain/mission.dart';
import '../../reports/data/report_schedule_repository.dart';
import '../../reports/presentation/save_to_disk.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import 'cms_dashboard.dart' show DashboardData, adminAllTripsProvider, dashboardDataProvider;
import 'widgets/cms_layout.dart';
import 'widgets/cms_theme.dart';

/// Admin Reports module. Two tabs:
///   1. **Dashboard** — configurable pie chart of spend by Category /
///      Source / Mission / Trip / Top user, with date-range + currency
///      filters. Backed by the existing dashboardDataProvider so it
///      shares the same cached fetch as the home screen.
///   2. **Schedules** — CRUD for daily-delivery schedules. Same table
///      that used to live at this URL.
class CmsReportsScreen extends ConsumerStatefulWidget {
  const CmsReportsScreen({super.key});

  @override
  ConsumerState<CmsReportsScreen> createState() => _CmsReportsScreenState();
}

class _CmsReportsScreenState extends ConsumerState<CmsReportsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null ||
        (me.role != UserRole.admin && me.role != UserRole.superAdmin)) {
      return const CmsLayout(
        active: CmsNavItem.reports,
        title: 'Reports',
        child: Center(child: Text('Admin only.')),
      );
    }
    return CmsLayout(
      active: CmsNavItem.reports,
      title: 'Reports',
      titleSubtitle: _tab == 0
          ? 'Pick a dimension to slice spend. Filter by date and currency.'
          : 'Schedule daily report deliveries. Recipients get a '
              'Report ready notification at the configured UTC hour.',
      trailing: <Widget>[
        if (_tab == 1)
          ElevatedButton.icon(
            onPressed: () => _openCreateSchedule(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New schedule'),
            style: ElevatedButton.styleFrom(
              backgroundColor: CmsColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TabBar(
            current: _tab,
            onChange: (int v) => setState(() => _tab = v),
          ),
          Expanded(
            child: _tab == 0
                ? const _DashboardTab()
                : const _SchedulesTab(),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateSchedule() async {
    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) => const _CreateScheduleDialog(),
    );
    if (created == true) {
      ref.invalidate(reportSchedulesProvider);
    }
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onChange});
  final int current;
  final ValueChanged<int> onChange;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: CmsColors.surfaceCard,
        border: Border(bottom: BorderSide(color: CmsColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: <Widget>[
          _TabBtn(
            label: 'Dashboard',
            icon: Icons.pie_chart_outline,
            selected: current == 0,
            onTap: () => onChange(0),
          ),
          _TabBtn(
            label: 'Schedules',
            icon: Icons.schedule,
            selected: current == 1,
            onTap: () => onChange(1),
          ),
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? CmsColors.brand : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 15,
              color: selected ? CmsColors.brand : CmsColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? CmsColors.textPrimary
                    : CmsColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Dashboard tab — configurable pie chart
// ============================================================================

enum _Dimension { category, source, mission, trip, user }

extension on _Dimension {
  String get label => switch (this) {
        _Dimension.category => 'Category',
        _Dimension.source => 'Source',
        _Dimension.mission => 'Mission',
        _Dimension.trip => 'Trip',
        _Dimension.user => 'Top user',
      };
  IconData get icon => switch (this) {
        _Dimension.category => Icons.local_offer_outlined,
        _Dimension.source => Icons.account_balance_outlined,
        _Dimension.mission => Icons.flag_outlined,
        _Dimension.trip => Icons.flight_takeoff_outlined,
        _Dimension.user => Icons.person_outline,
      };
}

enum _RangePreset { last30, last90, thisYear, all }

extension on _RangePreset {
  String get label => switch (this) {
        _RangePreset.last30 => 'Last 30 days',
        _RangePreset.last90 => 'Last 90 days',
        _RangePreset.thisYear => 'This year',
        _RangePreset.all => 'All time',
      };
  DateTime? get from {
    final DateTime now = DateTime.now();
    return switch (this) {
      _RangePreset.last30 => now.subtract(const Duration(days: 30)),
      _RangePreset.last90 => now.subtract(const Duration(days: 90)),
      _RangePreset.thisYear => DateTime(now.year, 1, 1),
      _RangePreset.all => null,
    };
  }
}

class _DashboardTab extends ConsumerStatefulWidget {
  const _DashboardTab();
  @override
  ConsumerState<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends ConsumerState<_DashboardTab> {
  _Dimension _dimension = _Dimension.category;
  _RangePreset _range = _RangePreset.last30;
  String? _currency;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> hydration =
        ref.watch(authenticatedHydrationProvider);
    final AsyncValue<DashboardData> dataAsync =
        ref.watch(dashboardDataProvider);
    return hydration.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => Center(child: Text('Error: $e')),
      data: (bool _) => dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (DashboardData d) => _renderBody(d),
      ),
    );
  }

  Widget _renderBody(DashboardData d) {
    // Currency set: union of trip currencies. Default to the most common.
    final Map<String, int> ccyTally = <String, int>{};
    for (final Trip t in d.trips) {
      ccyTally.update(t.currency, (int v) => v + 1, ifAbsent: () => 1);
    }
    final List<String> currencies = ccyTally.keys.toList()..sort();
    if (currencies.isEmpty) currencies.add('AED');
    final String selectedCurrency = _currency ??
        (currencies.isEmpty
            ? 'AED'
            : ccyTally.entries
                .reduce((MapEntry<String, int> a, MapEntry<String, int> b) =>
                    a.value >= b.value ? a : b)
                .key);

    // Filter expenses by selected currency + date range.
    final DateTime? from = _range.from;
    final Map<String, Trip> tripById = <String, Trip>{
      for (final Trip t in d.trips) t.id: t,
    };
    final List<Expense> filtered = d.expenses.where((Expense e) {
      final Trip? trip = tripById[e.tripId];
      if (trip == null) return false;
      if (trip.currency != selectedCurrency) return false;
      if (from != null && e.occurredAt.isBefore(from)) return false;
      return true;
    }).toList();

    // Bucket by selected dimension.
    final List<_Slice> slices =
        _bucket(filtered, _dimension, d, ref.read(demoStoreProvider));
    final int total =
        slices.fold<int>(0, (int a, _Slice s) => a + s.amountMinor);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ConfigBar(
            dimension: _dimension,
            range: _range,
            currency: selectedCurrency,
            currencies: currencies,
            onDimension: (_Dimension v) => setState(() => _dimension = v),
            onRange: (_RangePreset v) => setState(() => _range = v),
            onCurrency: (String v) => setState(() => _currency = v),
          ),
          const SizedBox(height: 14),
          _ChartCard(
            dimensionLabel: _dimension.label,
            currency: selectedCurrency,
            totalMinor: total,
            slices: slices,
          ),
        ],
      ),
    );
  }

  List<_Slice> _bucket(
    List<Expense> expenses,
    _Dimension dim,
    DashboardData d,
    DemoStore store,
  ) {
    final Map<String, int> sums = <String, int>{};
    final Map<String, String> labels = <String, String>{};
    String keyFor(Expense e) {
      switch (dim) {
        case _Dimension.category:
          return 'cat:${e.categoryCode}';
        case _Dimension.source:
          return 'src:${e.sourceId}';
        case _Dimension.mission:
          final String? m = d.trips
              .where((Trip t) => t.id == e.tripId)
              .firstOrNull
              ?.missionId;
          return m == null ? 'mission:__none__' : 'mission:$m';
        case _Dimension.trip:
          return 'trip:${e.tripId}';
        case _Dimension.user:
          return 'user:${e.userId}';
      }
    }

    for (final Expense e in expenses) {
      final String k = keyFor(e);
      sums.update(k, (int v) => v + e.amount.amountMinor,
          ifAbsent: () => e.amount.amountMinor);
      if (!labels.containsKey(k)) {
        labels[k] = _labelFor(dim, e, d, store);
      }
    }

    final List<_Slice> list = sums.entries
        .map((MapEntry<String, int> en) => _Slice(
              key: en.key,
              label: labels[en.key] ?? en.key,
              amountMinor: en.value,
            ))
        .toList();
    list.sort((_Slice a, _Slice b) => b.amountMinor - a.amountMinor);
    // Top 8 + "Other" rollup so the pie stays readable.
    if (list.length > 8) {
      final int otherSum = list
          .skip(8)
          .fold<int>(0, (int acc, _Slice s) => acc + s.amountMinor);
      final List<_Slice> head = list.take(8).toList();
      head.add(_Slice(
        key: '__other__', label: 'Other', amountMinor: otherSum,
      ));
      return head;
    }
    return list;
  }

  String _labelFor(
    _Dimension dim, Expense e, DashboardData d, DemoStore store,
  ) {
    switch (dim) {
      case _Dimension.category:
        try {
          return store.categoryByCode(e.categoryCode).nameEn;
        } catch (_) {
          return e.categoryCode;
        }
      case _Dimension.source:
        try {
          return store.sourceById(e.sourceId).name;
        } catch (_) {
          return 'Source';
        }
      case _Dimension.mission:
        final Trip? t = d.trips
            .where((Trip t) => t.id == e.tripId)
            .firstOrNull;
        if (t?.missionId == null) return 'Unassigned';
        final Mission? m = d.missions
            .where((Mission m) => m.id == t!.missionId)
            .firstOrNull;
        return m?.name ?? 'Mission';
      case _Dimension.trip:
        final Trip? t = d.trips
            .where((Trip t) => t.id == e.tripId)
            .firstOrNull;
        return t?.name ?? e.tripId;
      case _Dimension.user:
        try {
          return store.userById(e.userId).displayName;
        } catch (_) {
          return 'User';
        }
    }
  }
}

class _Slice {
  const _Slice({
    required this.key, required this.label, required this.amountMinor,
  });
  final String key;
  final String label;
  final int amountMinor;
}

class _ConfigBar extends StatelessWidget {
  const _ConfigBar({
    required this.dimension,
    required this.range,
    required this.currency,
    required this.currencies,
    required this.onDimension,
    required this.onRange,
    required this.onCurrency,
  });
  final _Dimension dimension;
  final _RangePreset range;
  final String currency;
  final List<String> currencies;
  final ValueChanged<_Dimension> onDimension;
  final ValueChanged<_RangePreset> onRange;
  final ValueChanged<String> onCurrency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'SLICE BY',
            style: TextStyle(
              color: CmsColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final _Dimension d in _Dimension.values)
                _Chip(
                  label: d.label,
                  icon: d.icon,
                  selected: dimension == d,
                  onTap: () => onDimension(d),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final _RangePreset r in _RangePreset.values)
                _Chip(
                  label: r.label,
                  selected: range == r,
                  onTap: () => onRange(r),
                ),
              const SizedBox(width: 14),
              Container(
                height: 30,
                decoration: BoxDecoration(
                  color: CmsColors.surfaceCard,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: CmsColors.divider),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currency,
                    isDense: true,
                    icon: const Icon(
                      Icons.expand_more,
                      size: 14, color: CmsColors.textSecondary,
                    ),
                    style: const TextStyle(
                      color: CmsColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final String c in currencies)
                        DropdownMenuItem<String>(
                          value: c, child: Text('Currency · $c'),
                        ),
                    ],
                    onChanged: (String? v) {
                      if (v != null) onCurrency(v);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CmsColors.brand : CmsColors.surfaceCard,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? CmsColors.brand : CmsColors.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: 12,
                  color: selected
                      ? CmsColors.surfaceCard
                      : CmsColors.textSecondary,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? CmsColors.surfaceCard
                      : CmsColors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.dimensionLabel,
    required this.currency,
    required this.totalMinor,
    required this.slices,
  });
  final String dimensionLabel;
  final String currency;
  final int totalMinor;
  final List<_Slice> slices;

  /// Builds an RFC-4180-ish CSV from the current slices. Excel and any
  /// spreadsheet app opens this natively — no XLSX library needed on the
  /// client. Header row + one row per slice + a TOTAL row at the bottom.
  String _buildCsv() {
    String esc(String s) => s.contains(',') || s.contains('"') || s.contains('\n')
        ? '"${s.replaceAll('"', '""')}"'
        : s;
    final StringBuffer b = StringBuffer();
    b.writeln('${esc(dimensionLabel)},Amount ($currency),% of total');
    final NumberFormat fmt = NumberFormat.decimalPattern('en_US');
    for (final _Slice s in slices) {
      final double pct =
          totalMinor == 0 ? 0 : (s.amountMinor / totalMinor) * 100;
      b.writeln(
        '${esc(s.label)},${fmt.format(s.amountMinor / 100.0)},'
        '${pct.toStringAsFixed(1)}',
      );
    }
    b.writeln('Total,${fmt.format(totalMinor / 100.0)},100.0');
    return b.toString();
  }

  void _exportCsv(BuildContext context) {
    final String slug = dimensionLabel
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final Uint8List bytes = Uint8List.fromList(utf8.encode(_buildCsv()));
    saveBytesToDisk(
      bytes: bytes,
      filename: 'reports-spend-by-$slug.csv',
      contentType: 'text/csv;charset=utf-8',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV downloaded — open it in Excel.')),
    );
  }

  void _exportPdf(BuildContext context) {
    // Browser print dialog → user picks "Save as PDF". The print
    // stylesheet for the CMS isn't tuned for chart-only output yet;
    // the user can pick a single page range in the print preview.
    browserPrint();
  }

  static const List<Color> _palette = <Color>[
    Color(0xFF6B8A3F), // olive
    Color(0xFFD08A2A), // amber
    Color(0xFFA85C2A), // terracotta
    Color(0xFF6A6E9F), // dusty indigo
    Color(0xFFB14D6E), // muted plum
    Color(0xFF3E8068), // teal
    Color(0xFF8D7331), // gold-deep
    Color(0xFF4B6F9B), // slate
    Color(0xFF9CA0A8), // muted (for "Other")
  ];

  @override
  Widget build(BuildContext context) {
    final NumberFormat fmt = NumberFormat.decimalPattern('en_US');
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Spend by $dimensionLabel'.toLowerCase(),
                      style: const TextStyle(
                        color: CmsColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$currency ${fmt.format(totalMinor / 100.0)} '
                      'total across ${slices.length} '
                      'bucket${slices.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: CmsColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (slices.isNotEmpty && totalMinor > 0) ...<Widget>[
                _ExportBtn(
                  icon: Icons.table_chart_outlined,
                  label: 'Excel',
                  onTap: () => _exportCsv(context),
                ),
                const SizedBox(width: 6),
                _ExportBtn(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  onTap: () => _exportPdf(context),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          if (slices.isEmpty || totalMinor == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No spend in this view.',
                  style: const TextStyle(color: CmsColors.textSecondary),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (BuildContext _, BoxConstraints c) {
                final bool wide = c.maxWidth >= 720;
                final Widget pie = SizedBox(
                  width: 260,
                  height: 260,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 60,
                      sections: <PieChartSectionData>[
                        for (int i = 0; i < slices.length; i++)
                          PieChartSectionData(
                            value: slices[i].amountMinor.toDouble(),
                            color: _palette[i % _palette.length],
                            radius: 48,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                );
                final Widget legend = _Legend(
                  slices: slices,
                  totalMinor: totalMinor,
                  currency: currency,
                  palette: _palette,
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      pie,
                      const SizedBox(width: 24),
                      Expanded(child: legend),
                    ],
                  );
                }
                return Column(
                  children: <Widget>[
                    Center(child: pie),
                    const SizedBox(height: 14),
                    legend,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Small outlined button used in the chart card's top-right corner for
/// the Excel + PDF export actions.
class _ExportBtn extends StatelessWidget {
  const _ExportBtn({
    required this.icon, required this.label, required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: CmsColors.divider),
        foregroundColor: CmsColors.textPrimary,
        backgroundColor: CmsColors.surfaceCard,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.slices,
    required this.totalMinor,
    required this.currency,
    required this.palette,
  });
  final List<_Slice> slices;
  final int totalMinor;
  final String currency;
  final List<Color> palette;
  @override
  Widget build(BuildContext context) {
    final NumberFormat fmt = NumberFormat.decimalPattern('en_US');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < slices.length; i++) ...<Widget>[
          if (i > 0)
            const Divider(height: 1, color: CmsColors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: palette[i % palette.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    slices[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CmsColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$currency ${fmt.format(slices[i].amountMinor / 100.0)}',
                  style: const TextStyle(
                    color: CmsColors.textBody,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${((slices[i].amountMinor / totalMinor) * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: CmsColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// Schedules tab — same CRUD that previously lived at /cms/reports
// ============================================================================

class _SchedulesTab extends ConsumerWidget {
  const _SchedulesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ReportScheduleRow>> async =
        ref.watch(reportSchedulesProvider);
    final AsyncValue<List<Trip>> tripsAsync = ref.watch(adminAllTripsProvider);
    final AsyncValue<List<Mission>> missionsAsync = ref.watch(missionsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => Center(child: Text('Error: $e')),
      data: (List<ReportScheduleRow> rows) {
        final Map<String, String> tripNames = <String, String>{
          for (final Trip t in tripsAsync.valueOrNull ?? const <Trip>[])
            t.id: t.name,
        };
        final Map<String, String> missionNames = <String, String>{
          for (final Mission m in missionsAsync.valueOrNull ?? const <Mission>[])
            m.id: m.name,
        };
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
          child: Container(
            decoration: BoxDecoration(
              color: CmsColors.surfaceCard,
              borderRadius: const BorderRadius.all(AppRadii.card),
              border: Border.all(color: CmsColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                _SchedHeader(),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'No scheduled reports yet. Use "New schedule" '
                        'in the top-right to add one.',
                        style: TextStyle(color: CmsColors.textSecondary),
                      ),
                    ),
                  )
                else
                  for (int i = 0; i < rows.length; i++) ...<Widget>[
                    if (i > 0)
                      const Divider(height: 1, color: CmsColors.divider),
                    _SchedRow(
                      row: rows[i],
                      tripNames: tripNames,
                      missionNames: missionNames,
                    ),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SchedHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    TextStyle h() => const TextStyle(
          color: CmsColors.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: const BoxDecoration(
        color: CmsColors.bgElev,
        border: Border(bottom: BorderSide(color: CmsColors.divider)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 70, child: Text('SCOPE', style: h())),
          Expanded(flex: 3, child: Text('TARGET', style: h())),
          SizedBox(width: 80, child: Text('CADENCE', style: h())),
          SizedBox(width: 90, child: Text('UTC HOUR', style: h())),
          SizedBox(width: 130, child: Text('NEXT RUN', style: h())),
          SizedBox(width: 80, child: Text('STATUS', style: h())),
          const SizedBox(width: 110),
        ],
      ),
    );
  }
}

class _SchedRow extends ConsumerWidget {
  const _SchedRow({
    required this.row,
    required this.tripNames,
    required this.missionNames,
  });
  final ReportScheduleRow row;
  final Map<String, String> tripNames;
  final Map<String, String> missionNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String scopeLabel = row.scope == ScheduleScope.trip
        ? 'Trip'
        : 'Mission';
    final String target = row.scope == ScheduleScope.trip
        ? (tripNames[row.scopeId] ?? row.scopeId)
        : (missionNames[row.scopeId] ?? row.scopeId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 70,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: row.scope == ScheduleScope.trip
                    ? CmsColors.brandTint
                    : CmsColors.goldSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(
                scopeLabel.toUpperCase(),
                style: TextStyle(
                  color: row.scope == ScheduleScope.trip
                      ? CmsColors.brand
                      : CmsColors.goldDeep,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                target,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CmsColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              row.kind == ScheduleKind.daily ? 'Daily' : row.kind.name,
              style: const TextStyle(
                color: CmsColors.textBody, fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              '${row.utcHour.toString().padLeft(2, '0')}:00 UTC',
              style: const TextStyle(
                color: CmsColors.textBody,
                fontSize: 12, fontFamily: 'monospace',
              ),
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              DateFormat('MMM d · HH:mm').format(row.nextRunAt.toLocal()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CmsColors.textBody, fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: row.active ? CmsColors.accentSoft : CmsColors.bgElev,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                row.active ? 'ACTIVE' : 'PAUSED',
                style: TextStyle(
                  color: row.active
                      ? CmsColors.accentDeep
                      : CmsColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => _toggleActive(context, ref),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(row.active ? 'Pause' : 'Resume'),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 16, color: CmsColors.outflow,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Delete schedule',
                  onPressed: () => _delete(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(reportScheduleRepositoryProvider)
          .update(id: row.id, active: !row.active);
      ref.invalidate(reportSchedulesProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update schedule: $e'),
          backgroundColor: CmsColors.outflow,
        ),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext _) => AlertDialog(
        title: const Text('Delete schedule?'),
        content: const Text(
          'No more notifications will fire for this schedule. '
          'You can recreate it any time.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CmsColors.outflow,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(reportScheduleRepositoryProvider).delete(row.id);
      ref.invalidate(reportSchedulesProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: CmsColors.outflow,
        ),
      );
    }
  }
}

// ============================================================================
// Create schedule dialog — same as before
// ============================================================================

/// Simple two-state pill button used inside the create-schedule dialog
/// for picking Trip vs Mission. Avoids SegmentedButton, which crashed in
/// Flutter Web for at least one user on the current channel.
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? CmsColors.brand : CmsColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? CmsColors.brand : CmsColors.divider,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? CmsColors.surfaceCard
                    : CmsColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateScheduleDialog extends ConsumerStatefulWidget {
  const _CreateScheduleDialog();
  @override
  ConsumerState<_CreateScheduleDialog> createState() =>
      _CreateScheduleDialogState();
}

class _CreateScheduleDialogState
    extends ConsumerState<_CreateScheduleDialog> {
  ScheduleScope _scope = ScheduleScope.trip;
  String? _scopeId;
  int _utcHour = 17;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Trip>> tripsAsync = ref.watch(adminAllTripsProvider);
    final AsyncValue<List<Mission>> missionsAsync =
        ref.watch(missionsProvider);
    // Build the options list defensively. Dedupe by id (paranoid — JPA
    // shouldn't return dupes but a malformed payload once was enough for
    // DropdownButton to throw and crash the dialog).
    final Map<String, String> optionsById = <String, String>{};
    if (_scope == ScheduleScope.trip) {
      for (final Trip t in tripsAsync.valueOrNull ?? const <Trip>[]) {
        optionsById.putIfAbsent(t.id, () => t.name);
      }
    } else {
      for (final Mission m in missionsAsync.valueOrNull ?? const <Mission>[]) {
        optionsById.putIfAbsent(m.id, () => m.name);
      }
    }
    final List<MapEntry<String, String>> options = optionsById.entries.toList()
      ..sort((MapEntry<String, String> a, MapEntry<String, String> b) =>
          a.value.compareTo(b.value));
    final bool optionsLoading =
        (_scope == ScheduleScope.trip ? tripsAsync : missionsAsync)
            .isLoading;
    // Defensive: if _scopeId points at something no longer in the list
    // (scope flipped, target deleted), drop it so the dropdown doesn't
    // assert on "value not in items."
    final String? safeScopeId =
        (_scopeId != null && optionsById.containsKey(_scopeId))
            ? _scopeId
            : null;
    if (safeScopeId != _scopeId) {
      // Schedule a state cleanup after this build so we don't setState
      // inside build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _scopeId = safeScopeId);
      });
    }

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.schedule, color: CmsColors.brand),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'New report schedule',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'SCOPE',
                style: TextStyle(
                  color: CmsColors.textTertiary, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              // Plain ChoiceChip pair — SegmentedButton crashed on web in
              // this Flutter version for at least one user, so we keep
              // primitive widgets here.
              Row(
                children: <Widget>[
                  _ScopeChip(
                    label: 'Trip',
                    selected: _scope == ScheduleScope.trip,
                    onTap: _saving
                        ? null
                        : () => setState(() {
                              _scope = ScheduleScope.trip;
                              _scopeId = null;
                            }),
                  ),
                  const SizedBox(width: 8),
                  _ScopeChip(
                    label: 'Mission',
                    selected: _scope == ScheduleScope.mission,
                    onTap: _saving
                        ? null
                        : () => setState(() {
                              _scope = ScheduleScope.mission;
                              _scopeId = null;
                            }),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'TARGET',
                style: TextStyle(
                  color: CmsColors.textTertiary, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              // Inline radio list — DropdownButton's hover-driven menu
              // animation triggers a mouse_tracker assertion on Flutter
              // Web in some Chrome versions. An inline list avoids the
              // popup entirely and is the most reliable picker.
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: CmsColors.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CmsColors.divider),
                ),
                child: optionsLoading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'Loading…',
                          style: TextStyle(
                            color: CmsColors.textSecondary, fontSize: 12,
                          ),
                        ),
                      )
                    : options.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              'No '
                              '${_scope == ScheduleScope.trip ? 'trips' : 'missions'} '
                              'available.',
                              style: const TextStyle(
                                color: CmsColors.textSecondary, fontSize: 12,
                              ),
                            ),
                          )
                        : Scrollbar(
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: options.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1, color: CmsColors.divider,
                              ),
                              itemBuilder:
                                  (BuildContext context, int i) {
                                final MapEntry<String, String> o =
                                    options[i];
                                final bool sel = o.key == safeScopeId;
                                return InkWell(
                                  onTap: _saving
                                      ? null
                                      : () => setState(
                                          () => _scopeId = o.key),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10,
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          sel
                                              ? Icons.radio_button_checked
                                              : Icons
                                                  .radio_button_unchecked,
                                          size: 16,
                                          color: sel
                                              ? CmsColors.brand
                                              : CmsColors.textSecondary,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            o.value,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: sel
                                                  ? CmsColors.textPrimary
                                                  : CmsColors.textBody,
                                              fontSize: 13,
                                              fontWeight: sel
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'UTC HOUR',
                style: TextStyle(
                  color: CmsColors.textTertiary, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Slider(
                      value: _utcHour.toDouble(),
                      min: 0, max: 23, divisions: 23,
                      label: '${_utcHour.toString().padLeft(2, '0')}:00 UTC',
                      onChanged: _saving
                          ? null
                          : (double v) =>
                              setState(() => _utcHour = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      '${_utcHour.toString().padLeft(2, '0')}:00 UTC',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Fires daily at the configured UTC hour. '
                '(GST = UTC + 4, so ${_utcHour.toString().padLeft(2, '0')}:00 UTC = '
                '${((_utcHour + 4) % 24).toString().padLeft(2, '0')}:00 GST.)',
                style: const TextStyle(
                  color: CmsColors.textSecondary, fontSize: 11,
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: const TextStyle(color: CmsColors.outflow)),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: CmsColors.accent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white,
                            ),
                          )
                        : const Text('CREATE'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_scopeId == null) {
      setState(() => _error = 'Pick a trip or mission first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(reportScheduleRepositoryProvider).create(
            scope: _scope, scopeId: _scopeId!, utcHour: _utcHour,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Could not create schedule: $e';
        _saving = false;
      });
    }
  }
}
