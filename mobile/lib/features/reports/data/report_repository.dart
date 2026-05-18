import '../domain/report.dart';

/// Slice 3D — reports download flow.
///
/// Real impl calls `GET /api/v1/reports/trip/{id}?type=...&format=...`
/// which returns `{ url, expiresAt, sha256 }`. The mobile/cms client opens
/// the URL via `url_launcher` (or copies it to the clipboard on
/// unsupported platforms). The `sign` endpoint is deferred — ADR-003 has
/// the details.
abstract class ReportRepository {
  Future<ReportRecord> generate({
    required String tripId,
    required ReportType type,
    required ReportFormat format,
  });

  /// Returns `null` if signing is deferred (the real backend returns 501
  /// SIGNING_DEFERRED for v1). UI surfaces a tooltip pointing at ADR-003.
  Future<ReportRecord?> sign(String reportId);
}

/// Sentinel used to wire the "Sign and send" button's disabled tooltip.
const String kSigningDeferredCode = 'SIGNING_DEFERRED';
