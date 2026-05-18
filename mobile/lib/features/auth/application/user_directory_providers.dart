import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../data/user_directory_repository.dart';
import '../domain/user.dart';

/// Admin-only directory CRUD. Always API-backed: the fake path can't model
/// password hashing meaningfully, and user management only makes sense
/// against the real backend.
final Provider<UserDirectoryRepository> userDirectoryRepositoryProvider =
    Provider<UserDirectoryRepository>(
      (Ref ref) => ApiUserDirectoryRepository(dio: ref.watch(dioProvider)),
    );

/// Live list of every user the caller can see. Invalidate after create/update
/// to refresh the CMS Users table.
final FutureProvider<List<User>> usersDirectoryProvider =
    FutureProvider<List<User>>(
      (Ref ref) async => ref.read(userDirectoryRepositoryProvider).all(),
    );
