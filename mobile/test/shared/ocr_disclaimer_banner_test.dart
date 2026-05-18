import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/l10n/generated/app_localizations.dart';
import 'package:pdd_petty_cash/shared/widgets/ocr_disclaimer_banner.dart';

void main() {
  group('OcrDisclaimerBanner', () {
    Widget host({
      required Locale locale,
      required VoidCallback onDismiss,
      String? body,
    }) {
      return MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Center(
            child: OcrDisclaimerBanner(
              body: body ??
                  'OCR result — verify all fields before submitting.',
              onDismiss: onDismiss,
            ),
          ),
        ),
      );
    }

    testWidgets('renders EN strings under en locale', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(locale: const Locale('en'), onDismiss: () {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Please verify'), findsOneWidget);
      expect(
        find.text('OCR result — verify all fields before submitting.'),
        findsOneWidget,
      );
    });

    testWidgets('renders AR strings under ar locale', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          locale: const Locale('ar'),
          onDismiss: () {},
          body: 'نتيجة المسح الضوئي — تأكّد من جميع الحقول قبل الإرسال.',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('يرجى التحقق'), findsOneWidget);
      expect(
        find.text('نتيجة المسح الضوئي — تأكّد من جميع الحقول قبل الإرسال.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping × invokes onDismiss', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(
        host(locale: const Locale('en'), onDismiss: () => calls++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ocrDisclaimerDismiss')));
      await tester.pump();

      expect(calls, 1);
    });
  });
}
