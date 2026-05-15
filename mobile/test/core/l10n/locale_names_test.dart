import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/l10n/locale_names.dart';
import 'package:pdd_petty_cash/features/expenses/domain/expense.dart';
import 'package:pdd_petty_cash/features/funds/domain/funding.dart';

void main() {
  group('LocalizedSourceName', () {
    const Source source = Source(
      id: 'src_zabeel',
      name: 'Zabeel Office',
      nameAr: 'مكتب زعبيل',
      isActive: true,
    );

    testWidgets('returns English name under en locale', (WidgetTester tester) async {
      await _pumpWith(tester, const Locale('en'), (BuildContext context) {
        expect(source.localizedName(context), 'Zabeel Office');
      });
    });

    testWidgets('returns Arabic name under ar locale', (WidgetTester tester) async {
      await _pumpWith(tester, const Locale('ar'), (BuildContext context) {
        expect(source.localizedName(context), 'مكتب زعبيل');
      });
    });
  });

  group('LocalizedCategoryName', () {
    const ExpenseCategory category = ExpenseCategory(
      code: 'FOOD',
      nameEn: 'Food',
      nameAr: 'طعام',
      iconKey: 'cutlery',
      isActive: true,
    );

    testWidgets('returns English name under en locale', (WidgetTester tester) async {
      await _pumpWith(tester, const Locale('en'), (BuildContext context) {
        expect(category.localizedName(context), 'Food');
      });
    });

    testWidgets('returns Arabic name under ar locale', (WidgetTester tester) async {
      await _pumpWith(tester, const Locale('ar'), (BuildContext context) {
        expect(category.localizedName(context), 'طعام');
      });
    });
  });
}

/// Mounts a Localizations widget at the chosen locale so extension methods that
/// read `Localizations.localeOf(context)` resolve correctly under widget tests.
Future<void> _pumpWith(
  WidgetTester tester,
  Locale locale,
  void Function(BuildContext context) probe,
) async {
  await tester.pumpWidget(
    Localizations(
      locale: locale,
      delegates: const <LocalizationsDelegate<dynamic>>[
        DefaultWidgetsLocalizations.delegate,
      ],
      child: Builder(
        builder: (BuildContext context) {
          probe(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
}
