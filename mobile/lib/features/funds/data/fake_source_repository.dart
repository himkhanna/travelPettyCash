import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../domain/funding.dart';
import 'funds_repository.dart';

class FakeSourceRepository implements SourceRepository {
  FakeSourceRepository(this._store, this._cfg);

  final DemoStore _store;
  final FakeConfig _cfg;

  @override
  Future<List<Source>> all() async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    return _store.sources.where((Source s) => s.isActive).toList(growable: false);
  }
}
