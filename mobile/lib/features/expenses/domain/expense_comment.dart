/// Domain ExpenseComment — comments attached to an expense, optionally
/// @mentioning trip participants. Each mention fans out a notification
/// (`EXPENSE_QUERY`) so the mentioned user sees it in their inbox.
class ExpenseComment {
  const ExpenseComment({
    required this.id,
    required this.expenseId,
    required this.authorId,
    required this.body,
    required this.mentionedUserIds,
    required this.createdAt,
  });

  final String id;
  final String expenseId;
  final String authorId;
  final String body;
  final List<String> mentionedUserIds;
  final DateTime createdAt;
}
