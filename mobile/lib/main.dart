import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Path-based URLs on web (no `#`). Required so the Dubai-Gov OIDC
  // callbacks — configured path-style as /app/auth/callback and
  // /portal/auth/callback (ADR-001) — match a route instead of falling
  // back to `/` and dropping the one-time exchange code.
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  await initializeDateFormatting();

  runApp(
    const ProviderScope(
      // Repository overrides land in Milestone A — until then, screens use
      // placeholders and don't read the repository providers.
      child: PddApp(),
    ),
  );
}
