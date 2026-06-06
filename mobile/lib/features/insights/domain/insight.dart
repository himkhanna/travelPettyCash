/// A single computed observation about a trip's spending, returned by the
/// backend's deterministic insights engine. Pre-rendered: [title] and
/// [message] are ready to display.
class Insight {
  const Insight({
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
  });

  /// Stable machine code, e.g. OVER_BUDGET / CATEGORY_CONCENTRATION /
  /// POSSIBLE_DUPLICATE / TOP_SPENDER. Drives the icon.
  final String type;

  /// CRITICAL | WARNING | INFO. Drives the colour.
  final String severity;

  final String title;
  final String message;

  factory Insight.fromJson(Map<String, dynamic> j) => Insight(
        type: j['type'] as String? ?? 'INFO',
        severity: j['severity'] as String? ?? 'INFO',
        title: j['title'] as String? ?? '',
        message: j['message'] as String? ?? '',
      );
}

/// The full insights payload for a trip: a plain-language narrative plus the
/// list of individual flags.
class TripInsights {
  const TripInsights({required this.narrative, required this.insights});

  final String narrative;
  final List<Insight> insights;

  static const TripInsights empty =
      TripInsights(narrative: '', insights: <Insight>[]);

  bool get isEmpty => narrative.isEmpty && insights.isEmpty;

  factory TripInsights.fromJson(Map<String, dynamic> j) => TripInsights(
        narrative: j['narrative'] as String? ?? '',
        insights: (j['insights'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => Insight.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}
