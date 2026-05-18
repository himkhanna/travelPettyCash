import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/auth/domain/user.dart';
import 'package:pdd_petty_cash/features/trips/domain/trip.dart';
import 'package:pdd_petty_cash/features/trips/presentation/all_trips_screen.dart';
import 'package:pdd_petty_cash/l10n/generated/app_localizations.dart';

void main() {
  group('AllTripsScreen', () {
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
      store.trips.addAll(<Trip>[
        Trip(
          id: 'trip-active',
          name: 'Active Trip',
          countryCode: 'SA',
          countryName: 'Saudi Arabia',
          currency: 'SAR',
          status: TripStatus.active,
          createdBy: 'u-admin',
          leaderId: 'u-leader',
          memberIds: const <String>['u-ahmed'],
          totalBudget: const Money(1000000, 'SAR'),
          createdAt: DateTime(2026, 5, 1),
        ),
        Trip(
          id: 'trip-closed',
          name: 'Closed Trip',
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
      ]);
      FakeConfig.instance
        ..setRole(FakeRole.member)
        ..setLatency(Duration.zero);
    });

    Widget buildApp() {
      final GoRouter r = GoRouter(
        initialLocation: '/m/all-trips',
        routes: <RouteBase>[
          GoRoute(
            path: '/m/all-trips',
            builder: (_, __) => const AllTripsScreen(),
          ),
          GoRoute(
            path: '/m/trips',
            builder: (_, __) => const Scaffold(),
          ),
          GoRoute(
            path: '/m/trips/:id/dashboard',
            builder: (_, __) => const Scaffold(),
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

    testWidgets('renders both ACTIVE and CLOSED trips with chips', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('ACTIVE TRIP'), findsOneWidget);
      expect(find.text('CLOSED TRIP'), findsOneWidget);

      // Status chips render the localized labels.
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('CLOSED'), findsOneWidget);
    });
  });
}
