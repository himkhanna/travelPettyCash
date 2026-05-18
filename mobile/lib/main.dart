import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');

  runApp(
    const ProviderScope(
      // Repository overrides land in Milestone A — until then, screens use
      // placeholders and don't read the repository providers.
      child: PddApp(),
    ),
  );
}
