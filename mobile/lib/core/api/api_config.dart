import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selects which `Repository` implementation Riverpod wires up. Until every
/// feature has a real backend slice, the demo defaults to [BackendMode.fake];
/// flip via the DevMenu to [BackendMode.api] to exercise the real endpoints.
enum BackendMode { fake, api }

/// Compile-time + runtime knobs for the Dio client. Defaults target the
/// local Spring Boot backend started by `ops/docker-compose.yml` +
/// `gradle bootRun --args='--spring.profiles.active=local'`.
class ApiConfig extends ChangeNotifier {
  ApiConfig._();

  static final ApiConfig instance = ApiConfig._();

  /// Compile-time override: `--dart-define=PDD_API_BASE=https://...`.
  static const String _baseFromEnv = String.fromEnvironment(
    'PDD_API_BASE',
    defaultValue: 'http://localhost:8080',
  );

  /// Compile-time mode override: `--dart-define=PDD_BACKEND=api|fake`.
  /// Default is API — the backend is the source of truth from Milestone D
  /// onwards. The fake/demo path is retained only for offline UI work and
  /// must be opted into explicitly.
  static const String _modeFromEnv = String.fromEnvironment(
    'PDD_BACKEND',
    defaultValue: 'api',
  );

  String _baseUrl = _baseFromEnv;
  BackendMode _mode = _modeFromEnv == 'fake' ? BackendMode.fake : BackendMode.api;

  String get baseUrl => _baseUrl;
  BackendMode get mode => _mode;
  bool get useApi => _mode == BackendMode.api;

  void setBaseUrl(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == _baseUrl) return;
    _baseUrl = trimmed;
    notifyListeners();
  }

  void setMode(BackendMode value) {
    if (value == _mode) return;
    _mode = value;
    notifyListeners();
  }
}

final Provider<ApiConfig> apiConfigProvider = Provider<ApiConfig>(
  (Ref ref) => ApiConfig.instance,
);

/// Subscribe to this for rebuilds whenever the user flips the backend toggle
/// in the DevMenu. Returns the current [BackendMode].
final Provider<BackendMode> backendModeProvider = Provider<BackendMode>(
  (Ref ref) {
    final ApiConfig cfg = ref.watch(apiConfigProvider);
    void invalidate() => ref.invalidateSelf();
    cfg.addListener(invalidate);
    ref.onDispose(() => cfg.removeListener(invalidate));
    return cfg.mode;
  },
);
