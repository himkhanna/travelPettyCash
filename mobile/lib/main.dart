import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const ProviderScope(
      // Repository overrides land in Milestone A — until then, screens use
      // placeholders and don't read the repository providers.
      child: PddApp(),
    ),
  );
}
