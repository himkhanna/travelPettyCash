import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../domain/expense.dart';
import 'category_repository.dart';

class FakeCategoryRepository implements CategoryRepository {
  FakeCategoryRepository(this._store, this._cfg);

  final DemoStore _store;
  final FakeConfig _cfg;

  @override
  Future<List<ExpenseCategory>> all() async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    return _store.categories
        .where((ExpenseCategory c) => c.isActive)
        .toList(growable: false);
  }

  @override
  Future<ExpenseCategory> create({
    required String code,
    required String nameEn,
    required String nameAr,
    required String iconKey,
  }) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    _cfg.maybeFail(op: 'categories.create');
    final ExpenseCategory c = ExpenseCategory(
      code: code,
      nameEn: nameEn,
      nameAr: nameAr,
      iconKey: iconKey,
      isActive: true,
    );
    _store.categories.add(c);
    return c;
  }
}
