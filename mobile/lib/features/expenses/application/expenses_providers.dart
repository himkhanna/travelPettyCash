import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../data/category_repository.dart';
import '../data/expense_repository.dart';
import '../data/fake_category_repository.dart';
import '../data/fake_expense_repository.dart';
import '../data/fake_receipt_scan_repository.dart';
import '../data/receipt_scan_repository.dart';
import '../domain/expense.dart';
import '../presentation/widgets/expense_filter_sheet.dart';

final Provider<ExpenseRepository> expenseRepositoryProvider =
    Provider<ExpenseRepository>(
      (Ref ref) => FakeExpenseRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      ),
    );

final Provider<CategoryRepository> categoryRepositoryProvider =
    Provider<CategoryRepository>(
      (Ref ref) => FakeCategoryRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      ),
    );

/// Backed by [FakeReceiptScanRepository] in the demo. Override this
/// provider in widget tests to inject a stub scanner.
final Provider<ReceiptScanRepository> receiptScanRepositoryProvider =
    Provider<ReceiptScanRepository>(
      (Ref ref) => FakeReceiptScanRepository(ref.watch(fakeConfigProvider)),
    );

/// Seam for testing the Add Expense OCR flow without a real camera.
///
/// Production code resolves to `ImagePicker().pickImage(source: ...)`;
/// widget tests override this provider with a stub that returns a fake
/// XFile (or null). Keeping it here means the screen does not import
/// `image_picker_platform_interface`, and we avoid taking a dev-dep on
/// the mock implementation just to drive widget tests.
typedef ImagePickFn = Future<XFile?> Function(ImageSource source);

final Provider<ImagePickFn> imagePickerProvider = Provider<ImagePickFn>(
  (Ref ref) => (ImageSource source) => ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      ),
);

final FutureProvider<List<ExpenseCategory>> categoriesProvider =
    FutureProvider<List<ExpenseCategory>>(
      (Ref ref) => ref.read(categoryRepositoryProvider).all(),
    );

final FutureProviderFamily<List<Expense>, String> myExpensesProvider =
    FutureProvider.family<List<Expense>, String>((Ref ref, String tripId) async {
      final User? user = await ref.watch(currentUserProvider.future);
      if (user == null) return <Expense>[];
      ref.watch(syncStateProvider);
      final ExpenseFilterState filter = ref.watch(
        expenseFilterProvider(tripId),
      );
      return ref
          .read(expenseRepositoryProvider)
          .list(
            tripId: tripId,
            userId: user.id,
            filter: filter.toRepoFilter(),
          );
    });

/// Cross-member view (#26). Same filter as My Expenses but `userId: null`.
final FutureProviderFamily<List<Expense>, String> tripExpensesProvider =
    FutureProvider.family<List<Expense>, String>((Ref ref, String tripId) async {
      final User? user = await ref.watch(currentUserProvider.future);
      if (user == null) return <Expense>[];
      ref.watch(syncStateProvider);
      final ExpenseFilterState filter = ref.watch(
        expenseFilterProvider(tripId),
      );
      return ref
          .read(expenseRepositoryProvider)
          .list(tripId: tripId, filter: filter.toRepoFilter());
    });

/// Per-trip view of pending expenses (for "X pending" banners).
final ProviderFamily<int, String> pendingCountForTripProvider =
    Provider.family<int, String>((Ref ref, String tripId) {
      ref.watch(syncStateProvider);
      final DemoStore store = ref.read(demoStoreProvider);
      final String userId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
      return store.pendingExpenses
          .where((Expense e) => e.tripId == tripId && e.userId == userId)
          .length;
    });
