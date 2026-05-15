import 'signed_report.dart';

/// Auth method the user chose in the signing modal.
enum SigningMethod { biometric, pin }

/// Credentials presented to [SignatureService.sign].
class SignerCredentials {
  const SignerCredentials.biometric() : method = SigningMethod.biometric, pin = null;
  const SignerCredentials.pin(String this.pin) : method = SigningMethod.pin;

  final SigningMethod method;
  final String? pin;
}

/// Result of a sign attempt. Sealed so callers must handle both branches.
sealed class SignatureResult {
  const SignatureResult();
}

class SignatureSuccess extends SignatureResult {
  const SignatureSuccess(this.report);
  final SignedReport report;
}

class SignatureFailure extends SignatureResult {
  const SignatureFailure(this.code, this.message);
  final SignatureFailureCode code;
  final String message;
}

enum SignatureFailureCode { invalidPin, cancelled, hardwareError }

/// Production: PAdES via PKCS#11 / HSM at Moro Hub. Demo: [FakeSignatureService].
abstract class SignatureService {
  Future<SignatureResult> sign({
    required String tripId,
    required String reportKind,
    required SignerCredentials credentials,
  });

  /// Latest signature for a given (trip, kind) tuple, or null if unsigned.
  SignedReport? latestFor({required String tripId, required String reportKind});
}
