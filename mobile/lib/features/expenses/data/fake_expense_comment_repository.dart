import '../domain/expense_comment.dart';
import 'expense_comment_repository.dart';

/// In-memory fake — keeps comments per expense for the lifetime of the
/// running app. Used in demo mode when the backend isn't reachable.
class FakeExpenseCommentRepository implements ExpenseCommentRepository {
  final Map<String, List<ExpenseComment>> _byExpense =
      <String, List<ExpenseComment>>{};

  String _currentUserId = 'demo-user';
  String Function() _idGen = () =>
      DateTime.now().microsecondsSinceEpoch.toString();

  // Allow auth wiring to set the author when posting in fake mode.
  // ignore: use_setters_to_change_properties
  void bindUser(String userId) {
    _currentUserId = userId;
  }

  @override
  Future<List<ExpenseComment>> list(String expenseId) async {
    return List<ExpenseComment>.unmodifiable(
      _byExpense[expenseId] ?? const <ExpenseComment>[],
    );
  }

  @override
  Future<ExpenseComment> post({
    required String expenseId,
    required String body,
    List<String> mentionedUserIds = const <String>[],
  }) async {
    final ExpenseComment row = ExpenseComment(
      id: _idGen(),
      expenseId: expenseId,
      authorId: _currentUserId,
      body: body.trim(),
      mentionedUserIds: List<String>.unmodifiable(mentionedUserIds),
      createdAt: DateTime.now(),
    );
    _byExpense.putIfAbsent(expenseId, () => <ExpenseComment>[]).add(row);
    return row;
  }
}
