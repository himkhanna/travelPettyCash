import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/locale_provider.dart';
import '../l10n/generated/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

/// Scroll behavior that makes scrolling feel native on Flutter Web:
/// (a) accepts mouse + trackpad drag (not just wheel), so users can drag-
/// scroll on the phone-frame chrome on desktop, and (b) keeps a visible
/// scrollbar on every scrollable so the affordance is never hidden.
///
/// Applied globally via `MaterialApp.scrollBehavior` so individual screens
/// don't need to remember to wrap their lists in `Scrollbar(...)`.
class _PddScrollBehavior extends MaterialScrollBehavior {
  const _PddScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      thickness: 6,
      radius: const Radius.circular(8),
      child: child,
    );
  }
}

class PddApp extends ConsumerWidget {
  const PddApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Locale? override = ref.watch(localePreferenceProvider);
    return MaterialApp.router(
      title: 'PDD Delegation Expenses',
      debugShowCheckedModeBanner: false,
      theme: buildPddTheme(),
      scrollBehavior: const _PddScrollBehavior(),
      routerConfig: buildAppRouter(),
      locale: override,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
