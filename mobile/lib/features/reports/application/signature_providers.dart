import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../data/fake_signature_service.dart';
import '../domain/signature_service.dart';
import '../domain/signed_report.dart';

/// Service binding. Today wired to the in-memory fake; a real PAdES / PKCS#11
/// implementation drops in at the same provider when the backend lands.
final Provider<SignatureService> signatureServiceProvider =
    Provider<SignatureService>((Ref ref) {
      final User? signer = ref.watch(currentUserProvider).valueOrNull;
      return FakeSignatureService(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
        signer,
      );
    });

/// Latest [SignedReport] for a given (tripId, reportKind) tuple, or null.
/// Subscribes to [DemoStore.events] and self-invalidates whenever a
/// `signedReportsChanged` arrives, so the Finance Letter preview flips
/// from "unsigned" to "signed" immediately after a signature lands.
final FutureProviderFamily<SignedReport?, ({String tripId, String reportKind})>
latestSignatureProvider =
    FutureProvider.family<SignedReport?, ({String tripId, String reportKind})>(
      (Ref ref, ({String tripId, String reportKind}) args) async {
        final DemoStore store = ref.watch(demoStoreProvider);
        await store.ensureLoaded();

        final StreamSubscription<DemoStoreEvent> sub = store.events.listen(
          (DemoStoreEvent e) {
            if (e == DemoStoreEvent.signedReportsChanged) {
              ref.invalidateSelf();
            }
          },
        );
        ref.onDispose(sub.cancel);

        return ref
            .read(signatureServiceProvider)
            .latestFor(tripId: args.tripId, reportKind: args.reportKind);
      },
    );
