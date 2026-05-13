import '../domain/expense.dart';

abstract class CategoryRepository {
  Future<List<ExpenseCategory>> all();
  Future<ExpenseCategory> create({
    required String code,
    required String nameEn,
    required String nameAr,
    required String iconKey,
  });
}
