import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Knobs that drive the FakeXxxRepository implementations.
///
/// All UI-first work runs against fakes (see CLAUDE.md project memory:
/// build order is UI-first with mocks). The knobs let demos exercise
/// loading, error, and offline states without a real backend.
class FakeConfig extends ChangeNotifier {
  FakeConfig._();

  static final FakeConfig instance = FakeConfig._();

  /// Artificial latency injected into every fake repository call.
  /// Default 250ms so demos feel like a real network without being slow.
  Duration latency = const Duration(milliseconds: 250);

  /// Probability (0.0 – 1.0) that a write call returns a synthetic 500.
  /// Used to demo error states; default 0 so demos are happy-path.
  double failureRate = 0.0;

  /// When true, the SyncCoordinator behaves as if the device is offline:
  /// writes go to the Drift queue, reads return last-known cached values.
  bool offlineMode = false;

  /// The role the demo is "logged in" as. Changed via the landing-page
  /// role switcher or the in-app dev menu.
  FakeRole role = FakeRole.unset;

  /// Optional clock override for fast-forwarding demos. null means real time.
  DateTime? clockOverride;

  DateTime now() => clockOverride ?? DateTime.now();

  Future<void> waitLatency() => Future<void>.delayed(latency);

  /// Throws a synthetic FakeFailure with probability [failureRate]. Call this
  /// at the top of fake-repo *write* methods only.
  void maybeFail({String op = 'operation'}) {
    if (failureRate <= 0) return;
    if (_rng.nextDouble() < failureRate) {
      throw FakeFailure(op);
    }
  }

  void setLatency(Duration value) {
    latency = value;
    notifyListeners();
  }

  void setFailureRate(double value) {
    failureRate = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setOfflineMode({required bool value}) {
    offlineMode = value;
    notifyListeners();
  }

  void setRole(FakeRole value) {
    role = value;
    notifyListeners();
  }

  void setClockOverride(DateTime? value) {
    clockOverride = value;
    notifyListeners();
  }

  static final Random _rng = Random();
}

class FakeFailure implements Exception {
  FakeFailure(this.op);
  final String op;

  @override
  String toString() => 'FakeFailure(op=$op): synthetic failure from FakeConfig';
}

enum FakeRole { unset, member, leader, admin, superAdmin }

final Provider<FakeConfig> fakeConfigProvider = Provider<FakeConfig>(
  (Ref ref) => FakeConfig.instance,
);
