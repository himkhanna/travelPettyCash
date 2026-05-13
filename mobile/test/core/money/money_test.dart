import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/money/money.dart';

void main() {
  group('Money construction', () {
    test('stores integer minor units exactly', () {
      const Money m = Money(640000, 'SAR');
      expect(m.amountMinor, 640000);
      expect(m.currencyCode, 'SAR');
    });

    test('zero constructor', () {
      const Money m = Money.zero('AED');
      expect(m.amountMinor, 0);
      expect(m.isZero, true);
    });

    test('fromMajor converts SAR major to halalas', () {
      final Money m = Money.fromMajor(6400, 'SAR');
      expect(m.amountMinor, 640000);
    });

    test('fromMajor rounds half-up at the minor-unit boundary', () {
      final Money m = Money.fromMajor(10.005, 'AED');
      expect(m.amountMinor, 1001);
    });

    test('fromMajor handles 3-decimal currencies (BHD)', () {
      final Money m = Money.fromMajor(1.234, 'BHD');
      expect(m.amountMinor, 1234);
    });

    test('fromMajor handles 0-decimal currencies (JPY)', () {
      final Money m = Money.fromMajor(1500, 'JPY');
      expect(m.amountMinor, 1500);
    });
  });

  group('Money arithmetic', () {
    test('addition stays in minor units', () {
      const Money a = Money(100, 'SAR');
      const Money b = Money(250, 'SAR');
      expect((a + b).amountMinor, 350);
    });

    test('subtraction can go negative (balance may go minus per §6.4)', () {
      const Money a = Money(100, 'SAR');
      const Money b = Money(500, 'SAR');
      final Money r = a - b;
      expect(r.amountMinor, -400);
      expect(r.isNegative, true);
    });

    test('scalar multiplication', () {
      const Money a = Money(150, 'SAR');
      expect((a * 4).amountMinor, 600);
    });

    test('unary minus', () {
      const Money a = Money(100, 'SAR');
      expect((-a).amountMinor, -100);
    });

    test('mixing currencies throws', () {
      const Money sar = Money(100, 'SAR');
      const Money aed = Money(100, 'AED');
      expect(() => sar + aed, throwsArgumentError);
      expect(() => sar - aed, throwsArgumentError);
      expect(() => sar < aed, throwsArgumentError);
    });
  });

  group('Money comparison', () {
    test('ordering operators', () {
      const Money small = Money(100, 'SAR');
      const Money big = Money(500, 'SAR');
      expect(small < big, true);
      expect(big > small, true);
      expect(small <= small, true);
      expect(big >= small, true);
    });

    test('compareTo sorts ascending', () {
      final List<Money> list = <Money>[
        const Money(300, 'SAR'),
        const Money(100, 'SAR'),
        const Money(200, 'SAR'),
      ]..sort();
      expect(list.map((Money m) => m.amountMinor).toList(), <int>[100, 200, 300]);
    });

    test('equality is value-based', () {
      expect(const Money(100, 'SAR') == const Money(100, 'SAR'), true);
      expect(const Money(100, 'SAR') == const Money(100, 'AED'), false);
      expect(const Money(100, 'SAR').hashCode, const Money(100, 'SAR').hashCode);
    });
  });

  group('Money formatting', () {
    test('format puts currency code first (CLAUDE.md §8)', () {
      const Money m = Money(640000, 'SAR');
      expect(m.format(locale: 'en_US'), 'SAR 6,400');
    });

    test('format drops trailing zeros when whole', () {
      const Money m = Money(650000, 'AED');
      expect(m.format(locale: 'en_US'), 'AED 6,500');
    });

    test('format shows decimals when present', () {
      const Money m = Money(640050, 'AED');
      expect(m.format(locale: 'en_US'), 'AED 6,400.50');
    });

    test('format negative balance', () {
      const Money m = Money(-100000, 'SAR');
      expect(m.format(locale: 'en_US'), 'SAR -1,000');
    });
  });
}
