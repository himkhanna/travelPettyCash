import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../domain/expense_comment.dart';
import 'expense_comment_repository.dart';

class ApiExpenseCommentRepository implements ExpenseCommentRepository {
  ApiExpenseCommentRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<List<ExpenseComment>> list(String expenseId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/expenses/$expenseId/comments',
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<ExpenseComment> post({
    required String expenseId,
    required String body,
    List<String> mentionedUserIds = const <String>[],
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/expenses/$expenseId/comments',
        data: <String, dynamic>{
          'body': body,
          if (mentionedUserIds.isNotEmpty)
            'mentionedUserIds': mentionedUserIds,
        },
      );
      return _fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  ExpenseComment _fromJson(Map<String, dynamic> j) {
    return ExpenseComment(
      id: j['id'] as String,
      expenseId: j['expenseId'] as String,
      authorId: j['authorId'] as String,
      body: j['body'] as String,
      mentionedUserIds:
          (j['mentionedUserIds'] as List<dynamic>?)?.cast<String>() ??
              const <String>[],
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }
}
