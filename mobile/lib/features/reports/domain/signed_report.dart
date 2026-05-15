/// Audit-grade record of a successful PAdES signing of a report.
///
/// Per CLAUDE.md §10 the real production signing happens server-side via
/// PKCS#11 / HSM. In the demo this record is produced by the fake service
/// and is purely illustrative — the [certThumbprint] is generated locally.
class SignedReport {
  const SignedReport({
    required this.id,
    required this.tripId,
    required this.reportKind,
    required this.signerUserId,
    required this.signerDisplayName,
    required this.signerRoleLabel,
    required this.signedAt,
    required this.certThumbprint,
    required this.payloadHash,
  });

  /// Stable id (UUID). Lets the fake idempotently de-dup if re-signed.
  final String id;
  final String tripId;

  /// Report kind code; matches [ReportKind.name] from reports_dialog.
  /// We use a string here so this domain layer doesn't depend on UI.
  final String reportKind;

  final String signerUserId;
  final String signerDisplayName;
  final String signerRoleLabel;

  final DateTime signedAt;

  /// Hex-encoded SHA-256 fingerprint of the (mock) signing certificate.
  /// Format: groups of two hex chars separated by `:`.
  final String certThumbprint;

  /// Hex SHA-256 of the report payload at signing time.
  /// In production this is the digest that PAdES embeds.
  final String payloadHash;
}
