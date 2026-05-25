import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot of a user-built report configuration on the CMS Reports
/// dashboard. Persisted to `shared_preferences` so an admin can come
/// back tomorrow and pick up where they left off — no backend table
/// yet. Promotion to a server-side `saved_report` table is a follow-up.
class SavedReport {
  const SavedReport({
    required this.id,
    required this.name,
    required this.dimension,
    required this.chartType,
    required this.range,
    required this.currency,
    required this.tripFilter,
    required this.missionFilter,
    required this.createdAt,
  });

  /// Random id minted client-side. UUID would be nicer; mathematically
  /// `${DateTime.now().microsecondsSinceEpoch}` is unique enough for
  /// per-admin local storage.
  final String id;
  final String name;
  /// One of: `category`, `source`, `mission`, `trip`, `user`.
  final String dimension;
  /// One of: `pie`, `donut`, `bar`, `table`.
  final String chartType;
  /// One of: `last30`, `last90`, `thisYear`, `all`.
  final String range;
  final String currency;
  /// Empty string means "no filter".
  final String tripFilter;
  final String missionFilter;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'dimension': dimension,
        'chartType': chartType,
        'range': range,
        'currency': currency,
        'tripFilter': tripFilter,
        'missionFilter': missionFilter,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedReport.fromJson(Map<String, dynamic> j) => SavedReport(
        id: j['id'] as String,
        name: j['name'] as String,
        dimension: j['dimension'] as String,
        chartType: (j['chartType'] as String?) ?? 'pie',
        range: j['range'] as String,
        currency: j['currency'] as String,
        tripFilter: (j['tripFilter'] as String?) ?? '',
        missionFilter: (j['missionFilter'] as String?) ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

/// Single source of truth for saved-report rows. Backed by
/// shared_preferences under one key so the entire collection rewrites
/// on every mutation — fine for a list that maxes out at a couple
/// dozen entries per user.
class SavedReportRepository {
  SavedReportRepository();

  static const String _key = 'cms.saved_reports.v1';

  Future<List<SavedReport>> list() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const <SavedReport>[];
    final List<dynamic> arr = jsonDecode(raw) as List<dynamic>;
    return arr
        .map((dynamic e) => SavedReport.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> save(SavedReport row) async {
    final List<SavedReport> existing = await list();
    final List<SavedReport> next = <SavedReport>[
      // Drop any previous entry with the same id (this is also our
      // "update an existing report" path — the dialog reuses the id).
      ...existing.where((SavedReport r) => r.id != row.id),
      row,
    ]..sort((SavedReport a, SavedReport b) =>
        b.createdAt.compareTo(a.createdAt));
    await _write(next);
  }

  Future<void> delete(String id) async {
    final List<SavedReport> existing = await list();
    final List<SavedReport> next =
        existing.where((SavedReport r) => r.id != id).toList(growable: false);
    await _write(next);
  }

  Future<void> _write(List<SavedReport> rows) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw =
        jsonEncode(rows.map((SavedReport r) => r.toJson()).toList());
    await prefs.setString(_key, raw);
  }
}

final Provider<SavedReportRepository> savedReportRepositoryProvider =
    Provider<SavedReportRepository>((Ref ref) {
  return SavedReportRepository();
});

final AutoDisposeFutureProvider<List<SavedReport>> savedReportsProvider =
    FutureProvider.autoDispose<List<SavedReport>>((Ref ref) {
  return ref.read(savedReportRepositoryProvider).list();
});
