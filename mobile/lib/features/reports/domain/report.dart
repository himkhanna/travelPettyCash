import 'package:flutter/foundation.dart';

import '../../auth/domain/user.dart';

/// The four report types from CLAUDE.md §10.
///
/// Permissions per §7 — enforced both client-side (the dialog only shows
/// generate buttons for permitted types) and server-side (the real
/// `GET /api/v1/reports/trip/{id}?type=...` endpoint returns 403 if the
/// caller's role isn't on the allow-list).
enum ReportType {
  /// Single user's expenses for finance, grouped by source then category.
  user,

  /// Every expense by every member, with receipt thumbnails.
  trip,

  /// Letterhead PDF, digitally signed by Admin (PAdES). Signing is
  /// deferred for v1 — see ADR-003.
  finance,

  /// Per-user / per-category roll-up for the Director General.
  dg;

  Set<UserRole> get allowedRoles {
    switch (this) {
      case ReportType.user:
        return <UserRole>{
          UserRole.member,
          UserRole.leader,
          UserRole.admin,
          UserRole.superAdmin,
        };
      case ReportType.trip:
        return <UserRole>{UserRole.leader, UserRole.admin, UserRole.superAdmin};
      case ReportType.finance:
        return <UserRole>{UserRole.admin};
      case ReportType.dg:
        return <UserRole>{UserRole.superAdmin};
    }
  }

  /// Which output formats this report can be generated in, per CLAUDE.md
  /// §10 (User → XLSX+PDF, Trip → XLSX, Finance → signed PDF, DG → PDF).
  Set<ReportFormat> get supportedFormats {
    switch (this) {
      case ReportType.user:
        return <ReportFormat>{ReportFormat.xlsx, ReportFormat.pdf};
      case ReportType.trip:
        return <ReportFormat>{ReportFormat.xlsx};
      case ReportType.finance:
        return <ReportFormat>{ReportFormat.pdf};
      case ReportType.dg:
        return <ReportFormat>{ReportFormat.pdf};
    }
  }
}

enum ReportFormat { xlsx, pdf }

/// Server response for `GET /api/v1/reports/trip/{id}?type=...&format=...`.
/// `url` is a presigned download URL good until [expiresAt]; [sha256] is
/// recorded in the [AuditLog] (CLAUDE.md §10) so the client can verify
/// integrity of the file it actually fetched.
@immutable
class ReportRecord {
  const ReportRecord({
    required this.tripId,
    required this.type,
    required this.format,
    required this.url,
    required this.expiresAt,
    required this.sha256,
    this.signed = false,
  });

  final String tripId;
  final ReportType type;
  final ReportFormat format;
  final String url;
  final DateTime expiresAt;
  final String sha256;
  final bool signed;
}
