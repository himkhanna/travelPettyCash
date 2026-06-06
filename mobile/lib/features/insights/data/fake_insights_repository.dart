import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../expenses/domain/expense.dart';
import '../domain/insight.dart';
import 'insights_repository.dart';

/// Demo/offline insights. Computes a lightweight version of the backend
/// engine from the in-memory [DemoStore] so the card is populated without a
/// backend. The real (API) path carries the full rule set; this mirrors the
/// most visible ones (totals narrative + category concentration).
class FakeInsightsRepository implements InsightsRepository {
  FakeInsightsRepository(this._store, this._cfg);

  final DemoStore _store;
  final FakeConfig _cfg;

  @override
  Future<TripInsights> forTrip(String tripId) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();

    final List<Expense> exp = _store.expenses
        .where((Expense e) => e.tripId == tripId && e.deletedAt == null)
        .toList(growable: false);

    if (exp.isEmpty) {
      return const TripInsights(
        narrative: 'No expenses recorded yet.',
        insights: <Insight>[],
      );
    }

    final String ccy = exp.first.amount.currencyCode;
    int total = 0;
    final Map<String, int> byCategory = <String, int>{};
    for (final Expense e in exp) {
      total += e.amount.amountMinor;
      byCategory.update(
        e.categoryCode,
        (int v) => v + e.amount.amountMinor,
        ifAbsent: () => e.amount.amountMinor,
      );
    }

    final List<Insight> insights = <Insight>[];
    if (byCategory.length >= 2 && total > 0) {
      final MapEntry<String, int> top = byCategory.entries
          .reduce((MapEntry<String, int> a, MapEntry<String, int> b) =>
              b.value > a.value ? b : a);
      final int share = ((top.value * 100) / total).round();
      if (share >= 40) {
        insights.add(Insight(
          type: 'CATEGORY_CONCENTRATION',
          severity: share >= 60 ? 'WARNING' : 'INFO',
          title: 'Spending concentrated in ${top.key}',
          message: '${top.key} accounts for $share% of spend '
              '(${_fmt(top.value, ccy)}).',
        ));
      }
    }

    final String narrative =
        '${exp.length} ${exp.length == 1 ? 'expense' : 'expenses'} '
        'totalling ${_fmt(total, ccy)} recorded.';
    return TripInsights(narrative: narrative, insights: insights);
  }

  String _fmt(int minor, String ccy) =>
      '$ccy ${(minor / 100.0).toStringAsFixed(2)}';
}
