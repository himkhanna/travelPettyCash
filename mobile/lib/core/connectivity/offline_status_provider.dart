import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fake/fake_config.dart';

/// True when the device has no usable network — either the OS-level
/// connectivity stream reports "no connection" OR the Demo Controls
/// "Offline mode" toggle is on. The latter lets demos exercise the
/// offline flow without unplugging the laptop.
///
/// On Flutter Web we deliberately skip `connectivity_plus` and rely
/// solely on the FakeConfig toggle: the package's Safari/iOS-Safari
/// implementation throws during init on some iOS Safari versions and
/// crashes the entire bundle before the landing renders. Native iOS
/// (TestFlight build) would use the proper plugin and work fine.
///
/// Consumers (the GoRouter redirect, the Add Expense submit handler,
/// the sync banner) all read this single provider so the source of
/// truth never drifts.
final StreamProvider<bool> offlineStatusProvider =
    StreamProvider<bool>((Ref ref) async* {
  final FakeConfig cfg = ref.watch(fakeConfigProvider);

  if (kIsWeb) {
    // Demo-toggle only on web. Yield once; FakeConfig is a
    // ChangeNotifier that re-runs this provider on every flip via
    // ref.watch above.
    yield cfg.offlineMode;
    return;
  }

  final Connectivity connectivity = Connectivity();
  final bool demoOffline = cfg.offlineMode;

  List<ConnectivityResult> initial;
  try {
    initial = await connectivity.checkConnectivity();
  } catch (_) {
    initial = const <ConnectivityResult>[ConnectivityResult.wifi];
  }
  yield demoOffline || _isOffline(initial);

  await for (final List<ConnectivityResult> results
      in connectivity.onConnectivityChanged) {
    yield demoOffline || _isOffline(results);
  }
});

bool _isOffline(List<ConnectivityResult> results) {
  if (results.isEmpty) return true;
  return results.every(
    (ConnectivityResult r) => r == ConnectivityResult.none,
  );
}

/// Synchronous snapshot of [offlineStatusProvider]. Used by the
/// GoRouter redirect (which can't await an async stream).
final Provider<bool> isOfflineProvider = Provider<bool>((Ref ref) {
  final AsyncValue<bool> async = ref.watch(offlineStatusProvider);
  return async.maybeWhen(
    data: (bool offline) => offline,
    // While the stream is loading we treat the device as online so the
    // user can keep using the app — the redirect will catch the next
    // emission once the stream lands.
    orElse: () => false,
  );
});
