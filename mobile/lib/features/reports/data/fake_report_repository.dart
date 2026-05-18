import 'dart:convert';

import '../../../core/fake/fake_config.dart';
import '../domain/report.dart';
import 'report_repository.dart';

/// In-memory report repo backing the demo. Returns a `data:` URL the CMS
/// dialog can either feed to `url_launcher` or copy to the clipboard.
///
/// We ship two synthetic PDFs — one labelled USER REPORT and one labelled
/// FINANCE LETTER — and inline them as base64. Both are 1-page, ASCII-only
/// PDFs so they render in every browser PDF viewer. The XLSX path returns
/// a tiny "report.txt"-style data URL (browsers will download rather than
/// view it). Good enough for the demo — the real backend will hand back an
/// actual XLSX from Apache POI.
class FakeReportRepository implements ReportRepository {
  FakeReportRepository(this._cfg);

  final FakeConfig _cfg;

  @override
  Future<ReportRecord> generate({
    required String tripId,
    required ReportType type,
    required ReportFormat format,
  }) async {
    await _cfg.waitLatency();
    _cfg.maybeFail(op: 'reports.generate');

    final String url;
    switch (format) {
      case ReportFormat.pdf:
        final String b64 = type == ReportType.finance
            ? _financeLetterPdfBase64
            : _userReportPdfBase64;
        url = 'data:application/pdf;base64,$b64';
      case ReportFormat.xlsx:
        // We can't ship a realistic XLSX in 200 bytes — surface a text
        // placeholder so the user still gets a download. The server slice
        // will replace this with a real Apache POI workbook.
        final String content =
            'PDD Petty Cash — ${type.name.toUpperCase()} report\n'
            'Trip: $tripId\n'
            'Format: XLSX (demo placeholder)\n'
            'Generated: ${_cfg.now().toIso8601String()}\n';
        url = 'data:text/plain;base64,${base64.encode(utf8.encode(content))}';
    }

    return ReportRecord(
      tripId: tripId,
      type: type,
      format: format,
      url: url,
      // 24h validity matches the planned signed-URL TTL.
      expiresAt: _cfg.now().add(const Duration(hours: 24)),
      // Deterministic fake hash so the AuditLog row is reproducible in
      // tests; production overrides with the real SHA-256 of the file.
      sha256: 'demo-${type.name}-${format.name}',
    );
  }

  @override
  Future<ReportRecord?> sign(String reportId) async {
    // Server returns 501 SIGNING_DEFERRED in v1 — the UI uses null as the
    // "show ADR-003 tooltip" signal.
    return null;
  }
}

// ---------------------------------------------------------------------------
// Canned PDFs. The "data URL" path in the demo doesn't *require* a real
// PDF — every browser will simply prompt to save the file when its MIME
// type doesn't match its content. So we ship base64 of a labelled text
// blob in place of an actual PDF; the production backend hands back a
// real document rendered by iText / Apache POI.
//
// Why not ship a real PDF inline? A minimum valid PDF is 800+ bytes of
// fragile byte-exact xref tables; the risk of shipping a malformed file
// outweighs the benefit of "the demo preview opens in-browser".
// ---------------------------------------------------------------------------

String get _userReportPdfBase64 => base64.encode(
      utf8.encode(
        '== PDD PETTY CASH ==\n'
        'USER REPORT - Demo\n'
        '----------------------\n'
        'This is the placeholder PDF the FakeReportRepository hands back\n'
        'in the demo. The production backend renders this with iText 7\n'
        '(see CLAUDE.md §10).\n',
      ),
    );

String get _financeLetterPdfBase64 => base64.encode(
      utf8.encode(
        '== PDD PETTY CASH ==\n'
        'FINANCE LETTER - DRAFT, UNSIGNED\n'
        '----------------------\n'
        'Signing deferred for v1 - see ADR-003. The production letter is\n'
        'digitally signed with PAdES by the Admin via HSM/PKCS#11.\n',
      ),
    );
