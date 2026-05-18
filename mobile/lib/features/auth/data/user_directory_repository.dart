import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../domain/user.dart';

/// Directory of every user the caller can see + admin-only create/update.
abstract class UserDirectoryRepository {
  Future<List<User>> all();

  /// Admin only.
  Future<User> create({
    required String username,
    required String displayName,
    required String displayNameAr,
    required String email,
    required UserRole role,
    required String password,
  });

  /// Admin only — partial update. Any null field is left unchanged.
  Future<User> update({
    required String id,
    String? displayName,
    String? displayNameAr,
    String? email,
    UserRole? role,
    bool? active,
    String? password,
  });
}

class ApiUserDirectoryRepository implements UserDirectoryRepository {
  ApiUserDirectoryRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<List<User>> all() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('/api/v1/users');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<User> create({
    required String username,
    required String displayName,
    required String displayNameAr,
    required String email,
    required UserRole role,
    required String password,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/users',
        data: <String, dynamic>{
          'username': username,
          'displayName': displayName,
          'displayNameAr': displayNameAr,
          'email': email,
          'role': role.apiCode,
          'password': password,
        },
      );
      return _fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<User> update({
    required String id,
    String? displayName,
    String? displayNameAr,
    String? email,
    UserRole? role,
    bool? active,
    String? password,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (displayName != null) body['displayName'] = displayName;
    if (displayNameAr != null) body['displayNameAr'] = displayNameAr;
    if (email != null) body['email'] = email;
    if (role != null) body['role'] = role.apiCode;
    if (active != null) body['active'] = active;
    if (password != null && password.isNotEmpty) body['password'] = password;
    try {
      final Response<dynamic> resp = await _dio.patch<dynamic>(
        '/api/v1/users/$id',
        data: body,
      );
      return _fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  User _fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['displayName'] as String,
        displayNameAr: j['displayNameAr'] as String,
        email: j['email'] as String,
        role: UserRole.fromApiCode(j['role'] as String),
        isActive: j['active'] as bool? ?? true,
      );
}
