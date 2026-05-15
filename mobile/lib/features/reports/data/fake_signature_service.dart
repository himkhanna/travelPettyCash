import 'package:uuid/uuid.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../auth/domain/user.dart';
import '../domain/signature_service.dart';
import '../domain/signed_report.dart';

/// Demo signing service. Simulates an HSM sign with ~800ms latency, validates
/// a token PIN (any 4+ digits) or auto-accepts biometric, and stores the
/// resulting [SignedReport] in [DemoStore.signedReports].
///
/// In production this whole class is replaced by a PKCS#11 / PAdES backed
/// implementation; see CLAUDE.md §10.
class FakeSignatureService implements SignatureService {
  FakeSignatureService(this._store, this._cfg, this._signer);

  final DemoStore _store;
  final FakeConfig _cfg;

  /// Current user, resolved by the provider. Null means "not authenticated"
  /// which will surface as a cancelled signature result.
  final User? _signer;

  static const Duration _signingDelay = Duration(milliseconds: 800);
  static const Uuid _uuid = Uuid();

  @override
  Future<SignatureResult> sign({
    required String tripId,
    required String reportKind,
    required SignerCredentials credentials,
  }) async {
    final User? user = _signer;
    if (user == null) {
      return const SignatureFailure(
        SignatureFailureCode.cancelled,
        'No authenticated user.',
      );
    }

    // Up-front PIN check before we "talk to the HSM".
    if (credentials.method == SigningMethod.pin) {
      final String pin = credentials.pin ?? '';
      final bool ok = pin.length >= 4 && RegExp(r'^\d+$').hasMatch(pin);
      if (!ok) {
        return const SignatureFailure(
          SignatureFailureCode.invalidPin,
          'PIN must be at least 4 digits.',
        );
      }
    }

    await Future<void>.delayed(_signingDelay);
    _cfg.maybeFail(op: 'reports.sign');

    final DateTime now = _cfg.now();
    final String payload = '$tripId|$reportKind|${now.toIso8601String()}';
    final String payloadHash = _hexDigest(payload);
    final String thumbprint = _formatThumbprint(_hexDigest('cert|$payload'));

    final SignedReport signed = SignedReport(
      id: _uuid.v4(),
      tripId: tripId,
      reportKind: reportKind,
      signerUserId: user.id,
      signerDisplayName: user.displayName,
      signerRoleLabel: _roleLabel(user.role),
      signedAt: now,
      certThumbprint: thumbprint,
      payloadHash: payloadHash,
    );

    // Replace any prior signature for the same (trip, kind) — re-signing
    // is allowed and the latest one wins.
    _store.signedReports.removeWhere(
      (SignedReport r) => r.tripId == tripId && r.reportKind == reportKind,
    );
    _store.signedReports.add(signed);
    _store.emit(DemoStoreEvent.signedReportsChanged);

    return SignatureSuccess(signed);
  }

  @override
  SignedReport? latestFor({
    required String tripId,
    required String reportKind,
  }) {
    for (final SignedReport r in _store.signedReports.reversed) {
      if (r.tripId == tripId && r.reportKind == reportKind) return r;
    }
    return null;
  }

  // ---- helpers ----

  /// Deterministic 64-char uppercase hex string derived from [input].
  /// Web-safe (uses 32-bit ops only). Not cryptographic — purely a demo
  /// stand-in to give signatures stable, plausible-looking thumbprints.
  String _hexDigest(String input) {
    int h1 = 0x811c9dc5;
    int h2 = 0xdeadbeef;
    for (int i = 0; i < input.length; i++) {
      final int c = input.codeUnitAt(i);
      h1 = ((h1 ^ c) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 + c) * 0x85ebca77) & 0xFFFFFFFF;
    }
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 32; i++) {
      h1 = ((h1 * 0x01000193) ^ i) & 0xFFFFFFFF;
      h2 = ((h2 * 0xc2b2ae35) ^ (i * 31)) & 0xFFFFFFFF;
      final int byte = ((h1 ^ h2) & 0xFF);
      sb.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return sb.toString();
  }

  /// Renders the first 8 bytes of [hex] as a `AA:BB:CC:…` thumbprint —
  /// matches the visual format users see in OS certificate viewers.
  String _formatThumbprint(String hex) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 16; i += 2) {
      if (i > 0) sb.write(':');
      sb.write(hex.substring(i, i + 2));
    }
    return sb.toString();
  }

  String _roleLabel(UserRole r) {
    switch (r) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.leader:
        return 'Team Leader';
      case UserRole.member:
        return 'Team Member';
      case UserRole.superAdmin:
        return 'Director General';
    }
  }
}
