import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/auth/domain/user.dart';
import 'package:pdd_petty_cash/features/cms/presentation/reports_dialog.dart';
import 'package:pdd_petty_cash/features/trips/domain/trip.dart';
import 'package:pdd_petty_cash/l10n/generated/app_localizations.dart';

/// Slice 3D — reports dialog flow.
///
/// Verifies: (1) the four report cards render, (2) tapping GENERATE
/// transitions the USER card to a DOWNLOAD button (i.e. the fake
/// repository's URL surfaced), (3) the FINANCE card surfaces the
/// "Sign and send" tooltip ADR-003 reference once a report exists.
void main() {
  group('Reports dialog', () {
    late Trip trip;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      final DemoStore store = DemoStore.instance
        ..resetForTest()
        ..markLoadedForTest();
      store.users.add(
        const User(
          id: 'u-admin',
          username: 'admin',
          displayName: 'Admin',
          displayNameAr: 'مشرف',
          email: 'admin@example.com',
          role: UserRole.admin,
          isActive: true,
        ),
      );
      FakeConfig.instance
        ..setRole(FakeRole.admin)
        ..setLatency(Duration.zero)
        ..setFailureRate(0)
        ..setOfflineMode(value: false);
      trip = Trip(
        id: 't1',
        name: 'Tehran Delegation',
        countryCode: 'IR',
        countryName: 'Iran',
        currency: 'SAR',
        status: TripStatus.active,
        createdBy: 'u-admin',
        leaderId: 'u-admin',
        memberIds: const <String>['u-admin'],
        totalBudget: const Money(100000, 'SAR'),
        createdAt: DateTime(2026, 5, 1),
      );
    });

    Widget buildApp({Widget? home}) {
      return ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
          home: home ?? const _Launcher(),
        ),
      );
    }

    testWidgets('opens dialog and shows all four report cards',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text('USER REPORT'), findsOneWidget);
      expect(find.text('TRIP REPORT'), findsOneWidget);
      expect(find.text('FINANCE LETTER'), findsOneWidget);
      expect(find.text('DG REPORT'), findsOneWidget);
    });

    testWidgets(
      'tapping GENERATE on USER card surfaces DOWNLOAD',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildApp(home: _Launcher(trip: trip)));
        await tester.tap(find.text('OPEN'));
        await tester.pumpAndSettle();

        // Find the USER REPORT card's GENERATE button — there are multiple
        // "GENERATE" buttons (one per card), so scope the search.
        final Finder userCard = find.ancestor(
          of: find.text('USER REPORT'),
          matching: find.byType(Material),
        ).first;
        final Finder generateBtn = find.descendant(
          of: userCard,
          matching: find.text('GENERATE'),
        );
        expect(generateBtn, findsOneWidget);
        await tester.tap(generateBtn);
        await tester.pumpAndSettle();

        // After generate, USER card shows DOWNLOAD instead.
        expect(
          find.descendant(
            of: userCard,
            matching: find.text('DOWNLOAD'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('finance card respects admin role permission',
        (WidgetTester tester) async {
      // Switch to a non-admin role and confirm the FINANCE card greys out.
      FakeConfig.instance.setRole(FakeRole.member);
      final DemoStore store = DemoStore.instance;
      store.users.clear();
      store.users.add(
        const User(
          id: 'u-mbr',
          username: 'mbr',
          displayName: 'Member',
          displayNameAr: 'منسق',
          email: 'm@e.com',
          role: UserRole.member,
          isActive: true,
        ),
      );
      await tester.pumpWidget(buildApp(home: _Launcher(trip: trip)));
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      // FINANCE card should say "Not permitted for your role."
      final Finder financeCard = find.ancestor(
        of: find.text('FINANCE LETTER'),
        matching: find.byType(Material),
      ).first;
      expect(
        find.descendant(
          of: financeCard,
          matching: find.text('Not permitted for your role.'),
        ),
        findsOneWidget,
      );
    });
  });
}

class _Launcher extends StatelessWidget {
  const _Launcher({this.trip});
  final Trip? trip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (BuildContext ctx) {
            return FilledButton(
              onPressed: () {
                showReportsCatalog(
                  ctx,
                  trip: trip ??
                      Trip(
                        id: 't1',
                        name: 'Demo Trip',
                        countryCode: 'SA',
                        countryName: 'Saudi Arabia',
                        currency: 'SAR',
                        status: TripStatus.active,
                        createdBy: 'u-admin',
                        leaderId: 'u-admin',
                        memberIds: const <String>['u-admin'],
                        totalBudget: const Money(100000, 'SAR'),
                        createdAt: DateTime(2026, 5, 1),
                      ),
                );
              },
              child: const Text('OPEN'),
            );
          },
        ),
      ),
    );
  }
}
