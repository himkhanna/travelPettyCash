import '../../../core/money/money.dart';

/// Domain Trip — matches CLAUDE.md §5 Trip entity.
class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.countryName,
    required this.currency,
    required this.status,
    required this.createdBy,
    required this.leaderId,
    required this.memberIds,
    required this.totalBudget,
    required this.createdAt,
    this.closedAt,
  });

  final String id;
  final String name;
  final String countryCode;
  final String countryName;
  final String currency;
  final TripStatus status;
  final String createdBy;
  final String leaderId;
  final List<String> memberIds;
  final Money totalBudget;
  final DateTime createdAt;
  final DateTime? closedAt;
}

enum TripStatus { draft, active, closed }

enum BalanceScope { me, trip, leader }

class TripBalances {
  const TripBalances({
    required this.tripId,
    required this.scope,
    required this.totalBudget,
    required this.totalSpent,
    required this.totalBalance,
    required this.perSource,
  });

  final String tripId;
  final BalanceScope scope;
  final Money totalBudget;
  final Money totalSpent;
  final Money totalBalance;
  final List<SourceBalance> perSource;
}

class SourceBalance {
  const SourceBalance({
    required this.sourceId,
    required this.sourceName,
    required this.sourceNameAr,
    required this.received,
    required this.spent,
    required this.balance,
  });

  final String sourceId;
  final String sourceName;
  final String sourceNameAr;
  final Money received;
  final Money spent;
  final Money balance;
}
