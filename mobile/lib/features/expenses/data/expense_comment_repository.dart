import '../domain/expense_comment.dart';

abstract class ExpenseCommentRepository {
  Future<List<ExpenseComment>> list(String expenseId);

  /// Post a comment on the given expense. {@code mentionedUserIds} are
  /// canonical: the server uses them to fan out notifications (the body
  /// may also contain `@name` for display, but mention notifications come
  /// from this list, not from parsing).
  Future<ExpenseComment> post({
    required String expenseId,
    required String body,
    List<String> mentionedUserIds = const <String>[],
  });
}
