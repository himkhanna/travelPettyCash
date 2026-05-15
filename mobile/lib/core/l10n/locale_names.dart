import 'package:flutter/widgets.dart';

import '../../features/expenses/domain/expense.dart';
import '../../features/funds/domain/funding.dart';

/// Picks the Arabic variant when the active locale is `ar`; otherwise the
/// English variant. Centralises the rule so domain renderers (reports,
/// charts, table rows) don't each re-implement it.
String pickLocalized(BuildContext context, {required String en, required String ar}) {
  return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
}

extension LocalizedSourceName on Source {
  String localizedName(BuildContext context) =>
      pickLocalized(context, en: name, ar: nameAr);
}

extension LocalizedCategoryName on ExpenseCategory {
  String localizedName(BuildContext context) =>
      pickLocalized(context, en: nameEn, ar: nameAr);
}
