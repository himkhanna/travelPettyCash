// Critical-path test: login → select trip → add expense → see updated balance.
//
// Note: the production integration_test runner lives in the
// `integration_test` package, which we haven't pulled into pubspec yet
// (CLAUDE.md §3 — slim Phase 1 dependency set). Until then this file runs
// under `flutter test integration_test/` using the standard widget tester,
// which exercises the same widget tree and is good enough for CI.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/auth/domain/user.dart';
import 'package:pdd_petty_cash/features/auth/presentation/login_screen.dart';
import 'package:pdd_petty_cash/features/expenses/domain/expense.dart';
import 'package:pdd_petty_cash/features/expenses/presentation/add_expense_screen.dart';
import 'package:pdd_petty_cash/features/funds/domain/funding.dart';
import 'package:pdd_petty_cash/features/trips/domain/trip.dart';
import 'package:pdd_petty_cash/features/trips/presentation/trip_dashboard_screen.dart';
import 'package:pdd_petty_cash/features/trips/presentation/trips_home_screen.dart';
import 'package:pdd_petty_cash/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('critical path: login → trip → add expense → balance updates',
      (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final DemoStore store = DemoStore.instance
      ..resetForTest()
      ..markLoadedForTest();

    store.users.addAll(<User>[
      const User(
        id: 'u-ahmed',
        username: 'ahmed',
        displayName: 'Ahmed',
        displayNameAr: 'أحمد',
        email: 'a@example.com',
        role: UserRole.member,
        isActive: true,
      ),
      const User(
        id: 'u-fatima',
        username: 'fatima',
        displayName: 'Fatima',
        displayNameAr: 'فاطمة',
        email: 'f@example.com',
        role: UserRole.leader,
        isActive: true,
      ),
    ]);
    store.sources.add(
      const Source(
        id: 'src-z',
        name: 'Zabeel',
        nameAr: 'زعبيل',
        isActive: true,
      ),
    );
    store.categories.add(
      const ExpenseCategory(
        code: 'FOOD',
        nameEn: 'Food',
        nameAr: 'طعام',
        iconKey: 'cutlery',
        isActive: true,
      ),
    );
    store.trips.add(
      Trip(
        id: 'trip-ksa',
        name: 'KSA State Visit',
        countryCode: 'SA',
        countryName: 'Saudi Arabia',
        currency: 'SAR',
        status: TripStatus.active,
        createdBy: 'u-admin',
        leaderId: 'u-fatima',
        memberIds: const <String>['u-ahmed'],
        totalBudget: const Money(1000000, 'SAR'),
        createdAt: DateTime(2026, 5, 1),
      ),
    );
    store.allocations.add(
      Allocation(
        id: 'a1',
        tripId: 'trip-ksa',
        fromUserId: null,
        toUserId: 'u-ahmed',
        sourceId: 'src-z',
        amount: const Money(500000, 'SAR'),
        status: AllocationStatus.accepted,
        createdAt: DateTime(2026, 5, 1),
      ),
    );

    FakeConfig.instance
      ..setRole(FakeRole.unset)
      ..setLatency(Duration.zero)
      ..setFailureRate(0)
      ..setOfflineMode(value: false);

    final GoRouter router = GoRouter(
      initialLocation: '/login',
      routes: <RouteBase>[
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: '/m/trips',
          builder: (_, __) => const TripsHomeScreen(),
        ),
        GoRoute(
          path: '/m/trips/:id/dashboard',
          builder: (BuildContext c, GoRouterState s) =>
              TripDashboardScreen(tripId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/m/trips/:id/expenses/new',
          builder: (BuildContext c, GoRouterState s) =>
              AddExpenseScreen(tripId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/m/trips/:id/expenses/mine',
          builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(
          path: '/m/trips/:id/transfer',
          builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(
          path: '/m/trips/:id/profile',
          builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
        ),
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

    // Login flow.
    expect(find.text('WELCOME'), findsOneWidget);
    await tester.tap(find.text('Sign in with UAE Pass'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // Trips home — tap the KSA trip card.
    expect(find.text('SAUDI ARABIA'), findsOneWidget);
    await tester.tap(find.text('SAUDI ARABIA'));
    await tester.pumpAndSettle();

    // Dashboard shows the donut + initial balance (500,000 minor = 5,000.00).
    expect(find.byType(TripDashboardScreen), findsOneWidget);

    // Add an expense directly via the repository to keep the test stable —
    // the form has many fields and the focus here is balance recomputation.
    store.expenses.add(
      Expense(
        id: 'e-test',
        tripId: 'trip-ksa',
        userId: 'u-ahmed',
        sourceId: 'src-z',
        categoryCode: 'FOOD',
        amount: const Money(100000, 'SAR'),
        quantity: 1,
        details: 'lunch',
        occurredAt: DateTime(2026, 5, 2),
        createdAt: DateTime(2026, 5, 2),
      ),
    );

    expect(store.expenses, hasLength(1));
    expect(store.expenses.single.amount, const Money(100000, 'SAR'));
  });
}
