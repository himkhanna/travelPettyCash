import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/auth/domain/user.dart';
import 'package:pdd_petty_cash/features/funds/domain/funding.dart';
import 'package:pdd_petty_cash/features/trips/domain/trip.dart';
import 'package:pdd_petty_cash/features/trips/presentation/trip_dashboard_screen.dart';
import 'package:pdd_petty_cash/l10n/generated/app_localizations.dart';

void main() {
  group('Trip Dashboard — closed state', () {
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
          email: 'a@example.com',
          role: UserRole.member,
          isActive: true,
        ),
      );
      store.sources.add(
        const Source(
          id: 'src-z',
          name: 'Zabeel',
          nameAr: 'زعبيل',
          isActive: true,
        ),
      );
      store.trips.add(
        Trip(
          id: 'trip-closed',
          name: 'Amman Visit',
          countryCode: 'JO',
          countryName: 'Jordan',
          currency: 'JOD',
          status: TripStatus.closed,
          createdBy: 'u-admin',
          leaderId: 'u-leader',
          memberIds: const <String>['u-ahmed'],
          totalBudget: const Money(1000000, 'JOD'),
          createdAt: DateTime(2026, 3, 1),
          closedAt: DateTime(2026, 3, 20),
        ),
      );
      FakeConfig.instance
        ..setRole(FakeRole.member)
        ..setLatency(Duration.zero);
    });

    testWidgets('hides Add FAB and shows CLOSED pill + banner', (
      WidgetTester tester,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: '/m/trips/trip-closed/dashboard',
        routes: <RouteBase>[
          GoRoute(
            path: '/m/trips/:id/dashboard',
            builder: (BuildContext c, GoRouterState s) =>
                TripDashboardScreen(tripId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/m/trips', builder: (_, __) => const Scaffold()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The disabled CLOSED pill replaces the Add (+) FAB on the bottom nav.
      expect(find.text('CLOSED'), findsWidgets);
      expect(find.byIcon(Icons.add), findsNothing);

      // The closed banner is shown at the top of the screen.
      expect(
        find.textContaining('Trip closed on'),
        findsOneWidget,
      );
    });
  });
}
