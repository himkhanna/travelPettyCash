import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/features/auth/domain/user.dart';
import 'package:pdd_petty_cash/features/auth/presentation/login_screen.dart';
import 'package:pdd_petty_cash/l10n/generated/app_localizations.dart';

void main() {
  group('LoginScreen', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      final DemoStore store = DemoStore.instance
        ..resetForTest()
        ..markLoadedForTest();
      store.users.add(
        const User(
          id: 'u-ahmed',
          username: 'ahmed',
          displayName: 'Ahmed',
          displayNameAr: 'أحمد',
          email: 'ahmed@example.com',
          role: UserRole.member,
          isActive: true,
        ),
      );
      store.users.add(
        const User(
          id: 'u-fatima',
          username: 'fatima',
          displayName: 'Fatima',
          displayNameAr: 'فاطمة',
          email: 'fatima@example.com',
          role: UserRole.leader,
          isActive: true,
        ),
      );
      FakeConfig.instance
        ..setRole(FakeRole.unset)
        ..setLatency(Duration.zero);
    });

    Widget buildApp({GoRouter? router}) {
      final GoRouter r = router ??
          GoRouter(
            initialLocation: '/login',
            routes: <RouteBase>[
              GoRoute(
                path: '/login',
                builder: (_, __) => const LoginScreen(),
              ),
              GoRoute(
                path: '/m/trips',
                builder: (_, __) => const Scaffold(
                  body: Center(child: Text('TRIPS_HOME_SENTINEL')),
                ),
              ),
              GoRoute(
                path: '/forgot-password',
                builder: (_, __) => const Scaffold(
                  body: Center(child: Text('FORGOT_SENTINEL')),
                ),
              ),
            ],
          );
      return ProviderScope(
        child: MaterialApp.router(
          routerConfig: r,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      );
    }

    testWidgets('renders WELCOME and both SSO buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('WELCOME'), findsOneWidget);
      expect(find.text('Sign in with UAE Pass'), findsOneWidget);
      expect(find.text('Sign in with PDD SSO'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
    });

    testWidgets('UAE Pass button routes to /m/trips after delay', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign in with UAE Pass'));
      // Mock delay is 600ms inside the screen.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('TRIPS_HOME_SENTINEL'), findsOneWidget);
      expect(FakeConfig.instance.role, FakeRole.member);
    });

    testWidgets('Forgot password link routes to /forgot-password', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.text('FORGOT_SENTINEL'), findsOneWidget);
    });
  });
}
