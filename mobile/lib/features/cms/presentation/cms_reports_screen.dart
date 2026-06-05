import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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
import '../../missions/application/mission_providers.dart';
import '../../missions/domain/mission.dart';
import '../../reports/data/report_schedule_repository.dart';
import '../../reports/data/saved_report_repository.dart';
import '../../reports/presentation/save_to_disk.dart';
import '../../trips/domain/trip.dart';
import 'cms_dashboard.dart' show DashboardData, adminAllTripsProvider, dashboardDataProvider;
import 'widgets/cms_layout.dart';
import 'widgets/cms_theme.dart';

// =========================================================================
// Public screen
// =========================================================================

/// Admin Reports module. Three tabs:
///   1. **Builder** — pick a dimension, chart type, date range, currency,
///      and optionally narrow to one trip / one mission. Preview renders
///      live; Save view stashes the config to shared_preferences.
///   2. **My reports** — library of saved configs. Click to load back
///      into the Builder, or delete.
///   3. **Schedules** — daily-delivery CRUD. Rebuilt with bounded width
///      and horizontal scroll so the row no longer collapses on narrow
///      viewports.
class CmsReportsScreen extends ConsumerStatefulWidget {
  const CmsReportsScreen({super.key});

  @override
  ConsumerState<CmsReportsScreen> createState() => _CmsReportsScreenState();
}

class _CmsReportsScreenState extends ConsumerState<CmsReportsScreen> {
  int _tab = 0;
  _BuilderConfig _builder = _BuilderConfig.initial();

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
      titleSubtitle: switch (_tab) {
        0 => 'Build the view you want, save it, or export to Excel/PDF.',
        1 => 'Your saved reports. Click to reload into the builder.',
        _ => 'Schedule a daily delivery. Recipients get a notification.',
      },
      trailing: <Widget>[
        if (_tab == 2)
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
            child: switch (_tab) {
              0 => _BuilderTab(
                  config: _builder,
                  onConfigChange: (_BuilderConfig c) =>
                      setState(() => _builder = c),
                ),
              1 => _SavedReportsTab(
                  onLoad: (SavedReport r) {
                    setState(() {
                      _builder = _BuilderConfig.fromSaved(r);
                      _tab = 0;
                    });
                  },
                ),
              _ => const _SchedulesTab(),
            },
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
            label: 'Builder',
            icon: Icons.tune,
            selected: current == 0,
            onTap: () => onChange(0),
          ),
          _TabBtn(
            label: 'My reports',
            icon: Icons.bookmark_outline,
            selected: current == 1,
            onTap: () => onChange(1),
          ),
          _TabBtn(
            label: 'Schedules',
            icon: Icons.schedule,
            selected: current == 2,
            onTap: () => onChange(2),
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

// =========================================================================
// Builder configuration model — also used as the schema for SavedReport
// =========================================================================

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
  String get wire => name;
}

enum _ChartType { pie, donut, bar, table }

extension on _ChartType {
  String get label => switch (this) {
        _ChartType.pie => 'Pie',
        _ChartType.donut => 'Donut',
        _ChartType.bar => 'Bar',
        _ChartType.table => 'Table',
      };
  IconData get icon => switch (this) {
        _ChartType.pie => Icons.pie_chart_outline,
        _ChartType.donut => Icons.donut_large_outlined,
        _ChartType.bar => Icons.bar_chart_outlined,
        _ChartType.table => Icons.table_chart_outlined,
      };
  String get wire => name;
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
  String get wire => name;
}

class _BuilderConfig {
  const _BuilderConfig({
    required this.dimension,
    required this.chartType,
    required this.range,
    required this.currency,
    required this.tripFilter,
    required this.missionFilter,
    this.loadedFromId,
  });

  factory _BuilderConfig.initial() => const _BuilderConfig(
        dimension: _Dimension.category,
        chartType: _ChartType.pie,
        range: _RangePreset.last30,
        currency: null,
        tripFilter: null,
        missionFilter: null,
      );

  factory _BuilderConfig.fromSaved(SavedReport r) => _BuilderConfig(
        dimension: _DimensionExt.fromWire(r.dimension),
        chartType: _ChartTypeExt.fromWire(r.chartType),
        range: _RangePresetExt.fromWire(r.range),
        currency: r.currency,
        tripFilter: r.tripFilter.isEmpty ? null : r.tripFilter,
        missionFilter: r.missionFilter.isEmpty ? null : r.missionFilter,
        loadedFromId: r.id,
      );

  final _Dimension dimension;
  final _ChartType chartType;
  final _RangePreset range;
  /// `null` → use the most common currency in the dataset.
  final String? currency;
  final String? tripFilter;
  final String? missionFilter;
  /// When the config was loaded from a SavedReport, keep its id so the
  /// Save dialog can default to "update this one" instead of duplicating.
  final String? loadedFromId;

  _BuilderConfig copyWith({
    _Dimension? dimension,
    _ChartType? chartType,
    _RangePreset? range,
    Object? currency = _sentinel,
    Object? tripFilter = _sentinel,
    Object? missionFilter = _sentinel,
    Object? loadedFromId = _sentinel,
  }) =>
      _BuilderConfig(
        dimension: dimension ?? this.dimension,
        chartType: chartType ?? this.chartType,
        range: range ?? this.range,
        currency:
            identical(currency, _sentinel) ? this.currency : currency as String?,
        tripFilter: identical(tripFilter, _sentinel)
            ? this.tripFilter
            : tripFilter as String?,
        missionFilter: identical(missionFilter, _sentinel)
            ? this.missionFilter
            : missionFilter as String?,
        loadedFromId: identical(loadedFromId, _sentinel)
            ? this.loadedFromId
            : loadedFromId as String?,
      );
}

const Object _sentinel = Object();

// Re-export the enum extensions under aliased classes so the SavedReport
// constructor can call them by name from outside the file.
class _DimensionExt {
  static _Dimension fromWire(String s) => switch (s) {
        'category' => _Dimension.category,
        'source' => _Dimension.source,
        'mission' => _Dimension.mission,
        'trip' => _Dimension.trip,
        'user' => _Dimension.user,
        _ => _Dimension.category,
      };
}

class _ChartTypeExt {
  static _ChartType fromWire(String s) => switch (s) {
        'pie' => _ChartType.pie,
        'donut' => _ChartType.donut,
        'bar' => _ChartType.bar,
        'table' => _ChartType.table,
        _ => _ChartType.pie,
      };
}

class _RangePresetExt {
  static _RangePreset fromWire(String s) => switch (s) {
        'last30' => _RangePreset.last30,
        'last90' => _RangePreset.last90,
        'thisYear' => _RangePreset.thisYear,
        'all' => _RangePreset.all,
        _ => _RangePreset.last30,
      };
}

// =========================================================================
// Builder tab
// =========================================================================

class _BuilderTab extends ConsumerWidget {
  const _BuilderTab({required this.config, required this.onConfigChange});
  final _BuilderConfig config;
  final ValueChanged<_BuilderConfig> onConfigChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        data: (DashboardData d) => _renderBody(context, ref, d),
      ),
    );
  }

  Widget _renderBody(BuildContext context, WidgetRef ref, DashboardData d) {
    // Pick a currency to default to: the most common across trips.
    final Map<String, int> ccyTally = <String, int>{};
    for (final Trip t in d.trips) {
      ccyTally.update(t.currency, (int v) => v + 1, ifAbsent: () => 1);
    }
    final List<String> currencies = ccyTally.keys.toList()..sort();
    if (currencies.isEmpty) currencies.add('AED');
    final String selectedCurrency = config.currency ??
        (ccyTally.isEmpty
            ? currencies.first
            : ccyTally.entries
                .reduce((MapEntry<String, int> a, MapEntry<String, int> b) =>
                    a.value >= b.value ? a : b)
                .key);

    final DateTime? from = config.range.from;
    final Map<String, Trip> tripById = <String, Trip>{
      for (final Trip t in d.trips) t.id: t,
    };
    final List<Expense> filtered = d.expenses.where((Expense e) {
      final Trip? trip = tripById[e.tripId];
      if (trip == null) return false;
      if (trip.currency != selectedCurrency) return false;
      if (from != null && e.occurredAt.isBefore(from)) return false;
      if (config.tripFilter != null && e.tripId != config.tripFilter) {
        return false;
      }
      if (config.missionFilter != null && trip.missionId != config.missionFilter) {
        return false;
      }
      return true;
    }).toList();

    final List<_Slice> slices = _bucket(
      filtered, config.dimension, d, ref.read(demoStoreProvider),
    );
    final int total =
        slices.fold<int>(0, (int a, _Slice s) => a + s.amountMinor);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ConfigBar(
            config: config,
            currencies: currencies,
            selectedCurrency: selectedCurrency,
            trips: d.trips,
            missions: d.missions,
            onChange: onConfigChange,
            onSave: () => _openSaveDialog(context, ref),
          ),
          const SizedBox(height: 14),
          _ChartCard(
            dimensionLabel: config.dimension.label,
            chartType: config.chartType,
            currency: selectedCurrency,
            totalMinor: total,
            slices: slices,
          ),
        ],
      ),
    );
  }

  Future<void> _openSaveDialog(BuildContext context, WidgetRef ref) async {
    final List<SavedReport> existing =
        ref.read(savedReportsProvider).valueOrNull ?? const <SavedReport>[];
    final SavedReport? existingHit = config.loadedFromId == null
        ? null
        : existing
            .where((SavedReport r) => r.id == config.loadedFromId)
            .firstOrNull;
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => _SaveReportDialog(
        defaultName: existingHit?.name ?? _suggestName(),
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final SavedReport row = SavedReport(
      id: existingHit?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      dimension: config.dimension.wire,
      chartType: config.chartType.wire,
      range: config.range.wire,
      currency: config.currency ?? '',
      tripFilter: config.tripFilter ?? '',
      missionFilter: config.missionFilter ?? '',
      createdAt: existingHit?.createdAt ?? DateTime.now(),
    );
    await ref.read(savedReportRepositoryProvider).save(row);
    ref.invalidate(savedReportsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existingHit == null
              ? 'Saved as "${row.name}". Find it under My reports.'
              : 'Updated "${row.name}".',
        ),
      ),
    );
    // Tag the config with the id so subsequent saves overwrite.
    onConfigChange(config.copyWith(loadedFromId: row.id));
  }

  String _suggestName() {
    final String dim = config.dimension.label;
    final String range = config.range.label.toLowerCase();
    return 'Spend by $dim · $range';
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

// =========================================================================
// Config bar
// =========================================================================

class _ConfigBar extends StatelessWidget {
  const _ConfigBar({
    required this.config,
    required this.currencies,
    required this.selectedCurrency,
    required this.trips,
    required this.missions,
    required this.onChange,
    required this.onSave,
  });
  final _BuilderConfig config;
  final List<String> currencies;
  final String selectedCurrency;
  final List<Trip> trips;
  final List<Mission> missions;
  final ValueChanged<_BuilderConfig> onChange;
  final VoidCallback onSave;

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
          // Row 1: slice + chart
          _Section(
            label: 'SLICE BY',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final _Dimension d in _Dimension.values)
                  _Chip(
                    label: d.label,
                    icon: d.icon,
                    selected: config.dimension == d,
                    onTap: () => onChange(config.copyWith(dimension: d)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            label: 'CHART TYPE',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final _ChartType c in _ChartType.values)
                  _Chip(
                    label: c.label,
                    icon: c.icon,
                    selected: config.chartType == c,
                    onTap: () => onChange(config.copyWith(chartType: c)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            label: 'RANGE & CURRENCY',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                for (final _RangePreset r in _RangePreset.values)
                  _Chip(
                    label: r.label,
                    selected: config.range == r,
                    onTap: () => onChange(config.copyWith(range: r)),
                  ),
                const SizedBox(width: 6),
                _CurrencyPicker(
                  currencies: currencies,
                  value: selectedCurrency,
                  onChange: (String v) =>
                      onChange(config.copyWith(currency: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            label: 'NARROW TO',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _Picker(
                  hint: 'All trips',
                  selectedLabel: config.tripFilter == null
                      ? null
                      : trips
                          .where((Trip t) => t.id == config.tripFilter)
                          .map((Trip t) => t.name)
                          .firstOrNull,
                  onClear: config.tripFilter == null
                      ? null
                      : () => onChange(config.copyWith(tripFilter: null)),
                  onTap: () async {
                    final String? picked = await _pick(
                      context,
                      'Pick a trip',
                      trips.map((Trip t) => (t.id, t.name)).toList(),
                    );
                    if (picked != null) {
                      onChange(config.copyWith(tripFilter: picked));
                    }
                  },
                ),
                _Picker(
                  hint: 'All missions',
                  selectedLabel: config.missionFilter == null
                      ? null
                      : missions
                          .where((Mission m) => m.id == config.missionFilter)
                          .map((Mission m) => m.name)
                          .firstOrNull,
                  onClear: config.missionFilter == null
                      ? null
                      : () => onChange(config.copyWith(missionFilter: null)),
                  onTap: () async {
                    final String? picked = await _pick(
                      context,
                      'Pick a mission',
                      missions.map((Mission m) => (m.id, m.name)).toList(),
                    );
                    if (picked != null) {
                      onChange(config.copyWith(missionFilter: picked));
                    }
                  },
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: Text(
                    config.loadedFromId == null ? 'Save view' : 'Update view',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: CmsColors.brand,
                    foregroundColor: CmsColors.surfaceCard,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pick(
    BuildContext context,
    String title,
    List<(String, String)> options,
  ) async {
    final List<(String, String)> sorted = <(String, String)>[...options]
      ..sort(((String, String) a, (String, String) b) => a.$2.compareTo(b.$2));
    return showDialog<String>(
      context: context,
      builder: (BuildContext _) => Dialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(AppRadii.card),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: CmsColors.textPrimary,
                    ),
                  ),
                ),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: CmsColors.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: CmsColors.divider),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1, color: CmsColors.divider,
                      ),
                      itemBuilder: (BuildContext _, int i) => InkWell(
                        onTap: () => Navigator.of(context).pop(sorted[i].$1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12,
                          ),
                          child: Text(
                            sorted[i].$2,
                            style: const TextStyle(
                              color: CmsColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('CANCEL'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: CmsColors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
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

class _CurrencyPicker extends StatelessWidget {
  const _CurrencyPicker({
    required this.currencies,
    required this.value,
    required this.onChange,
  });
  final List<String> currencies;
  final String value;
  final ValueChanged<String> onChange;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: CmsColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
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
            if (v != null) onChange(v);
          },
        ),
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.hint,
    required this.selectedLabel,
    required this.onTap,
    required this.onClear,
  });
  final String hint;
  final String? selectedLabel;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) {
    final bool active = selectedLabel != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 30,
        padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 6, 0),
        decoration: BoxDecoration(
          color: active ? CmsColors.brandTint : CmsColors.surfaceCard,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: CmsColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              selectedLabel ?? hint,
              style: TextStyle(
                color: active ? CmsColors.brand : CmsColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            if (active && onClear != null)
              IconButton(
                icon: const Icon(Icons.close, size: 12),
                onPressed: onClear,
                color: CmsColors.brand,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 20, minHeight: 20),
              )
            else
              const Icon(
                Icons.expand_more,
                size: 14, color: CmsColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Chart card
// =========================================================================

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.dimensionLabel,
    required this.chartType,
    required this.currency,
    required this.totalMinor,
    required this.slices,
  });
  final String dimensionLabel;
  final _ChartType chartType;
  final String currency;
  final int totalMinor;
  final List<_Slice> slices;

  /// CSV — header + slices + total. Used by the Excel export button.
  String _buildCsv() {
    String esc(String s) =>
        s.contains(',') || s.contains('"') || s.contains('\n')
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

  String get _slug => dimensionLabel
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  void _exportCsv(BuildContext context) {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(_buildCsv()));
    saveBytesToDisk(
      bytes: bytes,
      filename: 'reports-spend-by-$_slug.csv',
      contentType: 'text/csv;charset=utf-8',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV downloaded — open it in Excel.')),
    );
  }

  void _exportPdf(BuildContext _) => browserPrint();

  /// Open the native share sheet with the CSV file (→ WhatsApp on a phone,
  /// BRD §2.6). Falls back to a plain download when Web Share with files is
  /// unsupported (desktop browsers).
  Future<void> _shareReport(BuildContext context) async {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(_buildCsv()));
    final String filename = 'reports-spend-by-$_slug.csv';
    final bool shared = await shareBytes(
      bytes: bytes,
      filename: filename,
      contentType: 'text/csv;charset=utf-8',
      title: 'PDD report',
      text: 'PDD Delegation Expenses report',
    );
    if (!context.mounted) return;
    if (shared) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opened share sheet.')),
      );
    } else {
      saveBytesToDisk(
        bytes: bytes,
        filename: filename,
        contentType: 'text/csv;charset=utf-8',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Sharing isn't supported here — downloaded instead; "
            'attach it in WhatsApp.',
          ),
        ),
      );
    }
  }

  static const List<Color> _palette = <Color>[
    Color(0xFF6B8A3F), Color(0xFFD08A2A), Color(0xFFA85C2A),
    Color(0xFF6A6E9F), Color(0xFFB14D6E), Color(0xFF3E8068),
    Color(0xFF8D7331), Color(0xFF4B6F9B), Color(0xFF9CA0A8),
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
                        color: CmsColors.textSecondary, fontSize: 12,
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
                const SizedBox(width: 6),
                _ExportBtn(
                  icon: Icons.ios_share,
                  label: 'Share',
                  onTap: () => _shareReport(context),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          if (slices.isEmpty || totalMinor == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No spend in this view.',
                  style: TextStyle(color: CmsColors.textSecondary),
                ),
              ),
            )
          else
            _renderChart(context),
        ],
      ),
    );
  }

  Widget _renderChart(BuildContext context) {
    switch (chartType) {
      case _ChartType.pie:
      case _ChartType.donut:
        return LayoutBuilder(
          builder: (BuildContext _, BoxConstraints c) {
            final bool wide = c.maxWidth >= 720;
            final double centerRadius =
                chartType == _ChartType.donut ? 60 : 0;
            final Widget pie = SizedBox(
              width: 260,
              height: 260,
              child: PieChart(
                PieChartData(
                  sectionsSpace: chartType == _ChartType.donut ? 2 : 1,
                  centerSpaceRadius: centerRadius,
                  sections: <PieChartSectionData>[
                    for (int i = 0; i < slices.length; i++)
                      PieChartSectionData(
                        value: slices[i].amountMinor.toDouble(),
                        color: _palette[i % _palette.length],
                        radius: chartType == _ChartType.donut ? 48 : 100,
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
        );
      case _ChartType.bar:
        return _BarView(
          slices: slices,
          totalMinor: totalMinor,
          currency: currency,
          palette: _palette,
        );
      case _ChartType.table:
        return _TableView(
          dimensionLabel: dimensionLabel,
          slices: slices,
          totalMinor: totalMinor,
          currency: currency,
        );
    }
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
          if (i > 0) const Divider(height: 1, color: CmsColors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: palette[i % palette.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    slices[i].label,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
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
                    fontSize: 12, fontFamily: 'monospace',
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
                      fontSize: 12, fontWeight: FontWeight.w700,
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

class _BarView extends StatelessWidget {
  const _BarView({
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
    // Horizontal bar list — much friendlier than vertical bars when labels
    // can be long (mission/trip/user names). Bars are proportional to the
    // top slice so the largest fills the row.
    final int maxAmount = slices.fold<int>(
      0, (int m, _Slice s) => math.max(m, s.amountMinor),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < slices.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 170,
                  child: Text(
                    slices[i].label,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CmsColors.textPrimary,
                      fontSize: 12.5, fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext _, BoxConstraints c) {
                      final double w = maxAmount == 0
                          ? 0
                          : c.maxWidth * (slices[i].amountMinor / maxAmount);
                      return Stack(
                        children: <Widget>[
                          Container(
                            height: 18,
                            decoration: BoxDecoration(
                              color: CmsColors.bgElev,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          Container(
                            height: 18,
                            width: w,
                            decoration: BoxDecoration(
                              color: palette[i % palette.length],
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 130,
                  child: Text(
                    '$currency ${fmt.format(slices[i].amountMinor / 100.0)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: CmsColors.textBody,
                      fontSize: 12, fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${((slices[i].amountMinor / totalMinor) * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: CmsColors.textSecondary,
                      fontSize: 12, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TableView extends StatelessWidget {
  const _TableView({
    required this.dimensionLabel,
    required this.slices,
    required this.totalMinor,
    required this.currency,
  });
  final String dimensionLabel;
  final List<_Slice> slices;
  final int totalMinor;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final NumberFormat fmt = NumberFormat.decimalPattern('en_US');
    TextStyle h() => const TextStyle(
          color: CmsColors.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        );
    return Container(
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CmsColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Container(
            color: CmsColors.bgElev,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: 5,
                  child: Text(dimensionLabel.toUpperCase(), style: h()),
                ),
                SizedBox(
                  width: 140,
                  child: Text(
                    'AMOUNT ($currency)',
                    textAlign: TextAlign.right,
                    style: h(),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '%',
                    textAlign: TextAlign.right,
                    style: h(),
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < slices.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1, color: CmsColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: Text(
                      slices[i].label,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CmsColors.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Text(
                      fmt.format(slices[i].amountMinor / 100.0),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: CmsColors.textBody,
                        fontSize: 13, fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${((slices[i].amountMinor / totalMinor) * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: CmsColors.textSecondary,
                        fontSize: 13, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Container(
            color: CmsColors.bgInset,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: <Widget>[
                const Expanded(
                  flex: 5,
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      color: CmsColors.textPrimary,
                      fontSize: 12, fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: Text(
                    fmt.format(totalMinor / 100.0),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: CmsColors.textPrimary,
                      fontSize: 13, fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(
                  width: 60,
                  child: Text(
                    '100%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: CmsColors.textPrimary,
                      fontSize: 13, fontWeight: FontWeight.w800,
                    ),
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

// =========================================================================
// Save dialog
// =========================================================================

class _SaveReportDialog extends StatefulWidget {
  const _SaveReportDialog({required this.defaultName});
  final String defaultName;
  @override
  State<_SaveReportDialog> createState() => _SaveReportDialogState();
}

class _SaveReportDialogState extends State<_SaveReportDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.defaultName);
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AlertDialog rather than a hand-rolled Dialog: the earlier custom
    // layout rendered with the scrim visible but an invisible body in at
    // least one user's session (Flutter Web caches + ConstrainedBox
    // without a maxHeight is fragile). AlertDialog handles sizing for us.
    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      title: const Text('Save report'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Saves the current builder configuration. Stored locally '
              'on this device — pinning to a server-side library lands '
              'in a follow-up.',
              style: TextStyle(
                color: CmsColors.textSecondary, fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              onSubmitted: (String _) =>
                  Navigator.of(context).pop(_ctrl.text.trim()),
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: CmsColors.brand,
            foregroundColor: CmsColors.surfaceCard,
          ),
          onPressed: () =>
              Navigator.of(context).pop(_ctrl.text.trim()),
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

// =========================================================================
// Saved reports tab
// =========================================================================

class _SavedReportsTab extends ConsumerWidget {
  const _SavedReportsTab({required this.onLoad});
  final ValueChanged<SavedReport> onLoad;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SavedReport>> async =
        ref.watch(savedReportsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load saved reports.\n$e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: CmsColors.outflow),
          ),
        ),
      ),
      data: (List<SavedReport> rows) {
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.bookmark_outline,
                    size: 36, color: CmsColors.textTertiary,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'No saved reports yet.',
                    style: TextStyle(
                      color: CmsColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Build a view in the Builder tab, then click '
                    '"Save view".',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CmsColors.textSecondary, fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
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
                for (int i = 0; i < rows.length; i++) ...<Widget>[
                  if (i > 0)
                    const Divider(height: 1, color: CmsColors.divider),
                  _SavedRow(
                    row: rows[i],
                    onLoad: () => onLoad(rows[i]),
                    onDelete: () async {
                      await ref
                          .read(savedReportRepositoryProvider)
                          .delete(rows[i].id);
                      ref.invalidate(savedReportsProvider);
                    },
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

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.row,
    required this.onLoad,
    required this.onDelete,
  });
  final SavedReport row;
  final VoidCallback onLoad;
  final Future<void> Function() onDelete;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onLoad,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: <Widget>[
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: CmsColors.brandTint,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                _ChartTypeExt.fromWire(row.chartType).icon,
                size: 16, color: CmsColors.brand,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    row.name,
                    style: const TextStyle(
                      color: CmsColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      _DimensionExt.fromWire(row.dimension).label,
                      _ChartTypeExt.fromWire(row.chartType).label,
                      _RangePresetExt.fromWire(row.range).label,
                      if (row.currency.isNotEmpty) row.currency,
                      if (row.tripFilter.isNotEmpty) 'trip-scoped',
                      if (row.missionFilter.isNotEmpty) 'mission-scoped',
                    ].join(' · '),
                    style: const TextStyle(
                      color: CmsColors.textSecondary, fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              DateFormat('d MMM, HH:mm').format(row.createdAt.toLocal()),
              style: const TextStyle(
                color: CmsColors.textTertiary, fontSize: 11,
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.play_arrow, size: 14),
              label: const Text('Load'),
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
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 16, color: CmsColors.outflow,
              ),
              tooltip: 'Delete saved report',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () async {
                final bool? ok = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext _) => AlertDialog(
                    title: const Text('Delete saved report?'),
                    content: Text(
                      'Remove "${row.name}" from your saved reports? '
                      'You can rebuild it from the Builder tab any time.',
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
                if (ok == true) await onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Schedules tab — rebuilt with bounded width
// =========================================================================

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
      error: (Object e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load schedules.\n$e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: CmsColors.outflow),
          ),
        ),
      ),
      data: (List<ReportScheduleRow> rows) {
        final Map<String, String> tripNames = <String, String>{
          for (final Trip t in tripsAsync.valueOrNull ?? const <Trip>[])
            t.id: t.name,
        };
        final Map<String, String> missionNames = <String, String>{
          for (final Mission m
              in missionsAsync.valueOrNull ?? const <Mission>[])
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
            child: LayoutBuilder(
              builder: (BuildContext _, BoxConstraints c) {
                // Fixed columns sum to ~720px + flex target — anything
                // narrower scrolls horizontally rather than crushing
                // Expanded children to zero (which is what made the
                // tab read as "blank").
                const double minTableWidth = 880;
                final double tableWidth =
                    c.maxWidth >= minTableWidth ? c.maxWidth : minTableWidth;
                final Widget table = SizedBox(
                  width: tableWidth,
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
                              style: TextStyle(
                                color: CmsColors.textSecondary,
                              ),
                            ),
                          ),
                        )
                      else
                        for (int i = 0; i < rows.length; i++) ...<Widget>[
                          if (i > 0)
                            const Divider(
                              height: 1, color: CmsColors.divider,
                            ),
                          _SchedRow(
                            row: rows[i],
                            tripNames: tripNames,
                            missionNames: missionNames,
                          ),
                        ],
                    ],
                  ),
                );
                if (tableWidth <= c.maxWidth) return table;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: table,
                );
              },
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
          fontWeight: FontWeight.w800,
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
          SizedBox(width: 100, child: Text('UTC HOUR', style: h())),
          SizedBox(width: 140, child: Text('NEXT RUN', style: h())),
          SizedBox(width: 80, child: Text('STATUS', style: h())),
          const SizedBox(width: 130),
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
                  fontSize: 10, fontWeight: FontWeight.w700,
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
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CmsColors.textPrimary,
                  fontSize: 13, fontWeight: FontWeight.w700,
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
            width: 100,
            child: Text(
              '${row.utcHour.toString().padLeft(2, '0')}:00 UTC',
              style: const TextStyle(
                color: CmsColors.textBody,
                fontSize: 12, fontFamily: 'monospace',
              ),
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              DateFormat('MMM d · HH:mm').format(row.nextRunAt.toLocal()),
              maxLines: 1, overflow: TextOverflow.ellipsis,
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
                color: row.active
                    ? CmsColors.accentSoft
                    : CmsColors.bgElev,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                row.active ? 'ACTIVE' : 'PAUSED',
                style: TextStyle(
                  color: row.active
                      ? CmsColors.accentDeep
                      : CmsColors.textSecondary,
                  fontSize: 10, fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 130,
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

// =========================================================================
// Create schedule dialog
// =========================================================================

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
    final String? safeScopeId =
        (_scopeId != null && optionsById.containsKey(_scopeId))
            ? _scopeId
            : null;
    if (safeScopeId != _scopeId) {
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
