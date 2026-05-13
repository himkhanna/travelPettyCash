import 'package:intl/intl.dart';

/// Monetary value stored as integer minor units (e.g. fils for AED, halalas for SAR).
///
/// CLAUDE.md §6 — non-negotiable rules:
/// - All monetary amounts are stored as integer minor units. Never doubles.
/// - All arithmetic on money goes through this type.
/// - A trip is single-currency; mixing currencies in an operation throws.
/// - Negative balances are permitted (caller decides to warn).
class Money implements Comparable<Money> {
  const Money(this.amountMinor, this.currencyCode);

  /// Zero in the given currency.
  const Money.zero(this.currencyCode) : amountMinor = 0;

  /// Construct from a major-unit decimal value (e.g. 6400.50 SAR). Rounds half-up.
  factory Money.fromMajor(num majorAmount, String currencyCode) {
    final int decimals = _decimalsFor(currencyCode);
    final num scaled = majorAmount * _pow10(decimals);
    final int rounded = scaled.round();
    return Money(rounded, currencyCode);
  }

  final int amountMinor;
  final String currencyCode;

  /// Number of decimal places this currency uses in major-unit display.
  int get decimals => _decimalsFor(currencyCode);

  /// Major-unit value as double — for **display only**, never for arithmetic.
  double get majorValue => amountMinor / _pow10(decimals);

  bool get isZero => amountMinor == 0;
  bool get isNegative => amountMinor < 0;
  bool get isPositive => amountMinor > 0;

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(amountMinor + other.amountMinor, currencyCode);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(amountMinor - other.amountMinor, currencyCode);
  }

  Money operator *(int factor) => Money(amountMinor * factor, currencyCode);

  Money operator -() => Money(-amountMinor, currencyCode);

  bool operator <(Money other) {
    _assertSameCurrency(other);
    return amountMinor < other.amountMinor;
  }

  bool operator <=(Money other) {
    _assertSameCurrency(other);
    return amountMinor <= other.amountMinor;
  }

  bool operator >(Money other) {
    _assertSameCurrency(other);
    return amountMinor > other.amountMinor;
  }

  bool operator >=(Money other) {
    _assertSameCurrency(other);
    return amountMinor >= other.amountMinor;
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return amountMinor.compareTo(other.amountMinor);
  }

  /// Formats per CLAUDE.md §8: currency code first (e.g. "SAR 6,400").
  String format({String? locale}) {
    final NumberFormat formatter = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: amountMinor % _pow10(decimals) == 0 ? 0 : decimals,
    );
    final String number = formatter.format(majorValue);
    return '$currencyCode $number';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          runtimeType == other.runtimeType &&
          amountMinor == other.amountMinor &&
          currencyCode == other.currencyCode;

  @override
  int get hashCode => Object.hash(amountMinor, currencyCode);

  @override
  String toString() => 'Money($amountMinor $currencyCode)';

  void _assertSameCurrency(Money other) {
    if (currencyCode != other.currencyCode) {
      throw ArgumentError(
        'Currency mismatch: $currencyCode vs ${other.currencyCode}. '
        'A trip is single-currency (CLAUDE.md §6.3).',
      );
    }
  }

  static int _decimalsFor(String code) {
    switch (code.toUpperCase()) {
      case 'JPY':
      case 'KRW':
      case 'VND':
        return 0;
      case 'BHD':
      case 'KWD':
      case 'OMR':
      case 'JOD':
        return 3;
      default:
        return 2; // SAR, AED, USD, EUR, EGP, ...
    }
  }

  static int _pow10(int exp) {
    int result = 1;
    for (int i = 0; i < exp; i++) {
      result *= 10;
    }
    return result;
  }
}
