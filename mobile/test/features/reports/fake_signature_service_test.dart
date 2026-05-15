import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/features/auth/domain/user.dart';
import 'package:pdd_petty_cash/features/reports/data/fake_signature_service.dart';
import 'package:pdd_petty_cash/features/reports/domain/signature_service.dart';
import 'package:pdd_petty_cash/features/reports/domain/signed_report.dart';

void main() {
  group('FakeSignatureService.sign', () {
    late DemoStore store;
    late FakeConfig cfg;
    late User admin;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      store = DemoStore.instance;
      store.resetForTest();
      store.markLoadedForTest();
      cfg = FakeConfig.instance
        ..setLatency(Duration.zero)
        ..setFailureRate(0)
        ..setOfflineMode(value: false);
      admin = const User(
        id: 'u-admin',
        username: 'admin',
        displayName: 'Ahmed Al-Mansouri',
        displayNameAr: 'أحمد المنصوري',
        email: 'admin@pdd.gov.ae',
        role: UserRole.admin,
        isActive: true,
      );
    });

    test('biometric returns SignatureSuccess with a stored SignedReport',
        () async {
      final FakeSignatureService svc =
          FakeSignatureService(store, cfg, admin);

      final SignatureResult result = await svc.sign(
        tripId: 'trip-1',
        reportKind: 'financeLetter',
        credentials: const SignerCredentials.biometric(),
      );

      expect(result, isA<SignatureSuccess>());
      final SignedReport signed = (result as SignatureSuccess).report;
      expect(signed.signerUserId, 'u-admin');
      expect(signed.signerDisplayName, 'Ahmed Al-Mansouri');
      expect(signed.tripId, 'trip-1');
      expect(signed.reportKind, 'financeLetter');
      expect(signed.certThumbprint, matches(RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){7}$')));
      expect(store.signedReports.single.id, signed.id);
    });

    test('PIN of 4+ digits succeeds', () async {
      final FakeSignatureService svc =
          FakeSignatureService(store, cfg, admin);

      final SignatureResult result = await svc.sign(
        tripId: 'trip-1',
        reportKind: 'financeLetter',
        credentials: const SignerCredentials.pin('1234'),
      );

      expect(result, isA<SignatureSuccess>());
    });

    test('PIN shorter than 4 digits fails with invalidPin', () async {
      final FakeSignatureService svc =
          FakeSignatureService(store, cfg, admin);

      final SignatureResult result = await svc.sign(
        tripId: 'trip-1',
        reportKind: 'financeLetter',
        credentials: const SignerCredentials.pin('12'),
      );

      expect(result, isA<SignatureFailure>());
      expect(
        (result as SignatureFailure).code,
        SignatureFailureCode.invalidPin,
      );
      expect(store.signedReports, isEmpty);
    });

    test('PIN containing non-digits fails with invalidPin', () async {
      final FakeSignatureService svc =
          FakeSignatureService(store, cfg, admin);

      final SignatureResult result = await svc.sign(
        tripId: 'trip-1',
        reportKind: 'financeLetter',
        credentials: const SignerCredentials.pin('12ab'),
      );

      expect(result, isA<SignatureFailure>());
      expect(
        (result as SignatureFailure).code,
        SignatureFailureCode.invalidPin,
      );
    });

    test('re-signing the same (trip, kind) replaces the prior signature',
        () async {
      final FakeSignatureService svc =
          FakeSignatureService(store, cfg, admin);

      final SignatureResult first = await svc.sign(
        tripId: 'trip-1',
        reportKind: 'financeLetter',
        credentials: const SignerCredentials.biometric(),
      );
      final SignatureResult second = await svc.sign(
        tripId: 'trip-1',
        reportKind: 'financeLetter',
        credentials: const SignerCredentials.biometric(),
      );

      expect(store.signedReports.length, 1);
      final String firstId = (first as SignatureSuccess).report.id;
      final String secondId = (second as SignatureSuccess).report.id;
      expect(secondId, isNot(firstId));
      expect(store.signedReports.single.id, secondId);
    });

    test('signatures for different (trip, kind) tuples coexist', () async {
      final FakeSignatureService svc =
          FakeSignatureService(store, cfg, admin);

      await svc.sign(
        tripId: 'trip-1',
        reportKind: 'financeLetter',
        credentials: const SignerCredentials.biometric(),
      );
      await svc.sign(
        tripId: 'trip-2',
        reportKind: 'financeLetter',
        credentials: const SignerCredentials.biometric(),
      );

      expect(store.signedReports.length, 2);
    });

    test('latestFor returns null when nothing is signed', () {
      final FakeSignatureService svc =
          FakeSignatureService(store, cfg, admin);

      expect(
        svc.latestFor(tripId: 'trip-1', reportKind: 'financeLetter'),
        isNull,
      );
    });

    test('signing without an authenticated user fails as cancelled',
        () async {
      final FakeSignatureService svc =
          FakeSignatureService(store, cfg, null);

      final SignatureResult result = await svc.sign(
        tripId: 'trip-1',
        reportKind: 'financeLetter',
        credentials: const SignerCredentials.biometric(),
      );

      expect(result, isA<SignatureFailure>());
      expect(
        (result as SignatureFailure).code,
        SignatureFailureCode.cancelled,
      );
    });
  });
}
