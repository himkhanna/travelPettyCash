import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fake/fake_config.dart';

/// True when the device has no usable network — either the OS-level
/// connectivity stream reports "no connection" OR the Demo Controls
/// "Offline mode" toggle is on. The latter lets demos exercise the
/// offline flow without unplugging the laptop.
///
/// Consumers (the GoRouter redirect, the Add Expense submit handler,
/// the sync banner) all read this single provider so the source of
/// truth never drifts.
final StreamProvider<bool> offlineStatusProvider =
    StreamProvider<bool>((Ref ref) async* {
  final Connectivity connectivity = Connectivity();
  // Listen to FakeConfig (ChangeNotifier) by piggy-backing on Riverpod's
  // rebuild loop: this provider rebuilds whenever the toggle flips.
  final FakeConfig cfg = ref.watch(fakeConfigProvider);
  bool demoOffline = cfg.offlineMode;

  // Seed with the current state so the redirect doesn't briefly think
  // we're online while the first stream event is in flight.
  List<ConnectivityResult> initial;
  try {
    initial = await connectivity.checkConnectivity();
  } catch (_) {
    // checkConnectivity throws on some web targets the first time —
    // assume online so we don't lock the user out.
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
  // `none` is the only marker that genuinely means no network. Wi-Fi,
  // mobile, ethernet, vpn, bluetooth all count as "online enough" for
  // an API call to at least attempt.
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
