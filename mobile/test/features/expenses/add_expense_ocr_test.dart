import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/auth/domain/user.dart';
import 'package:pdd_petty_cash/features/expenses/application/expenses_providers.dart';
import 'package:pdd_petty_cash/features/expenses/data/receipt_scan_repository.dart';
import 'package:pdd_petty_cash/features/expenses/domain/expense.dart';
import 'package:pdd_petty_cash/features/expenses/domain/receipt_scan_result.dart';
import 'package:pdd_petty_cash/features/expenses/presentation/add_expense_screen.dart';
import 'package:pdd_petty_cash/features/funds/domain/funding.dart';
import 'package:pdd_petty_cash/features/trips/domain/trip.dart';
import 'package:pdd_petty_cash/l10n/generated/app_localizations.dart';

class _StubScanRepo implements ReceiptScanRepository {
  _StubScanRepo(this.result);
  final ReceiptScanResult result;
  int calls = 0;

  @override
  Future<ReceiptScanResult> scan({
    required String tripId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    calls++;
    return result;
  }
}

void main() {
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
    store.sources.addAll(<Source>[
      const Source(
        id: 'src-zabeel',
        name: 'Zabeel Office',
        nameAr: 'قصر زعبيل',
        isActive: true,
      ),
      const Source(
        id: 'src-protocol',
        name: 'Protocol Dept',
        nameAr: 'دائرة التشريفات',
        isActive: true,
      ),
    ]);
    store.categories.addAll(const <ExpenseCategory>[
      ExpenseCategory(
        code: 'FOOD',
        nameEn: 'Food',
        nameAr: 'طعام',
        iconKey: 'cutlery',
        isActive: true,
      ),
      ExpenseCategory(
        code: 'HOTEL',
        nameEn: 'Hotel',
        nameAr: 'فندق',
        iconKey: 'bed',
        isActive: true,
      ),
    ]);
    store.trips.add(
      Trip(
        id: 'trip-ksa',
        name: 'KSA Visit',
        countryCode: 'SA',
        countryName: 'Saudi Arabia',
        currency: 'SAR',
        status: TripStatus.active,
        createdBy: 'u-admin',
        leaderId: 'u-leader',
        memberIds: const <String>['u-ahmed'],
        totalBudget: const Money(10000000, 'SAR'),
        createdAt: DateTime(2026, 5, 1),
      ),
    );
    FakeConfig.instance
      ..setRole(FakeRole.member)
      ..setLatency(Duration.zero)
      ..setFailureRate(0)
      ..setOfflineMode(value: false);
  });

  Widget buildApp({
    required ReceiptScanRepository scanRepo,
    required ImagePickFn picker,
  }) {
    final GoRouter router = GoRouter(
      initialLocation: '/m/trips/trip-ksa/expenses/new',
      routes: <RouteBase>[
        GoRoute(
          path: '/m/trips/:id/expenses/new',
          builder: (BuildContext c, GoRouterState s) =>
              AddExpenseScreen(tripId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/m/trips/:id/dashboard',
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('DASHBOARD_SENTINEL')),
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: <Override>[
        receiptScanRepositoryProvider.overrideWithValue(scanRepo),
        imagePickerProvider.overrideWithValue(picker),
      ],
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
    );
  }

  testWidgets('renders SCAN RECEIPT button at the top', (
    WidgetTester tester,
  ) async {
    final _StubScanRepo scan = _StubScanRepo(
      const ReceiptScanResult(
        confidence: 0.9,
        warning: 'verify',
      ),
    );
    await tester.pumpWidget(
      buildApp(
        scanRepo: scan,
        picker: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    // SCAN RECEIPT must be present.
    expect(find.text('SCAN RECEIPT'), findsOneWidget);
    expect(find.text('UPLOAD FROM GALLERY'), findsOneWidget);
    expect(find.text('or fill manually'), findsOneWidget);

    // It must render before the amount field (i.e. higher on the screen).
    // Use the SOURCE label as a proxy for "form area" since the amount
    // field's hint behaviour varies by host but the SOURCE label always
    // renders below the scan section.
    final Offset scanPos = tester.getTopLeft(find.text('SCAN RECEIPT'));
    final Offset sourcePos = tester.getTopLeft(find.text('SOURCE'));
    expect(
      scanPos.dy < sourcePos.dy,
      isTrue,
      reason: 'SCAN RECEIPT should sit above the SOURCE field label',
    );
  });

  testWidgets('tapping SCAN pre-fills fields and shows disclaimer banner', (
    WidgetTester tester,
  ) async {
    final _StubScanRepo scan = _StubScanRepo(
      ReceiptScanResult(
        vendor: 'Carrefour Riyadh',
        amount: const Money(150000, 'SAR'),
        quantity: 1,
        categoryHint: 'FOOD',
        occurredAt: DateTime(2026, 5, 4),
        confidence: 0.72,
        warning: 'OCR result — please verify before submitting.',
      ),
    );
    final XFile fake = XFile.fromData(
      Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      name: 'r.jpg',
      mimeType: 'image/jpeg',
    );
    await tester.pumpWidget(
      buildApp(
        scanRepo: scan,
        picker: (ImageSource src) async => fake,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('SCAN RECEIPT'));
    await tester.pumpAndSettle();

    expect(scan.calls, 1, reason: 'scanner was invoked');
    // Vendor field populated.
    expect(find.text('Carrefour Riyadh'), findsOneWidget);
    // Amount field populated (display value, before grouping).
    expect(find.text('1500.00'), findsOneWidget);
    // Disclaimer banner present.
    expect(find.text('Please verify'), findsOneWidget);
    expect(
      find.text('OCR result — please verify before submitting.'),
      findsOneWidget,
    );
  });

  testWidgets('dismissing the banner hides it', (WidgetTester tester) async {
    final _StubScanRepo scan = _StubScanRepo(
      ReceiptScanResult(
        vendor: 'Carrefour Riyadh',
        amount: const Money(150000, 'SAR'),
        quantity: 1,
        categoryHint: 'FOOD',
        occurredAt: DateTime(2026, 5, 4),
        confidence: 0.72,
        warning: 'OCR result — please verify before submitting.',
      ),
    );
    final XFile fake = XFile.fromData(
      Uint8List.fromList(<int>[1, 2, 3]),
      name: 'r.jpg',
      mimeType: 'image/jpeg',
    );
    await tester.pumpWidget(
      buildApp(scanRepo: scan, picker: (_) async => fake),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('SCAN RECEIPT'));
    await tester.pumpAndSettle();

    expect(find.text('Please verify'), findsOneWidget);

    // Tap the banner's dedicated dismiss button (keyed to avoid colliding
    // with the AppBar close button and other Icons.close affordances).
    await tester.tap(find.byKey(const Key('ocrDisclaimerDismiss')));
    await tester.pumpAndSettle();

    expect(find.text('Please verify'), findsNothing);
  });

  testWidgets('submit persists vendor through the create call', (
    WidgetTester tester,
  ) async {
    final _StubScanRepo scan = _StubScanRepo(
      ReceiptScanResult(
        vendor: 'Carrefour Riyadh',
        amount: const Money(150000, 'SAR'),
        quantity: 1,
        categoryHint: 'FOOD',
        occurredAt: DateTime(2026, 5, 4),
        confidence: 0.72,
        warning: 'verify',
      ),
    );
    final XFile fake = XFile.fromData(
      Uint8List.fromList(<int>[7, 7, 7]),
      name: 'r.jpg',
      mimeType: 'image/jpeg',
    );
    await tester.pumpWidget(
      buildApp(scanRepo: scan, picker: (_) async => fake),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('SCAN RECEIPT'));
    await tester.pumpAndSettle();

    // Pick a source — required for submit.
    await tester.tap(find.text('Zabeel Office'));
    await tester.pump();

    // Scroll the form so the submit button is on screen.
    final Finder submit = find.widgetWithText(FilledButton, 'ADD EXPENSE');
    expect(submit, findsOneWidget);
    await tester.scrollUntilVisible(submit, 200);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final Expense persisted =
        DemoStore.instance.expenses.singleWhere((Expense e) => e.tripId == 'trip-ksa');
    expect(persisted.vendor, 'Carrefour Riyadh');
    expect(persisted.amount.amountMinor, 150000);
    expect(persisted.categoryCode, 'FOOD');
    expect(persisted.sourceId, 'src-zabeel');
  });
}
