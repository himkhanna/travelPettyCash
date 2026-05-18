import '../../../core/money/money.dart';

/// One row in the unified activity feed. Mirrors the server's `AuditEntry`
/// record (`/api/v1/audit`).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.action,
    this.actorId,
    required this.actorName,
    required this.actorRole,
    this.targetUserId,
    this.targetUserName,
    this.tripId,
    this.tripName,
    this.amount,
    required this.summary,
  });

  final String id;
  final DateTime at;
  final AuditAction action;
  final String? actorId;
  final String actorName;
  final String actorRole;
  final String? targetUserId;
  final String? targetUserName;
  final String? tripId;
  final String? tripName;
  final Money? amount;
  final String summary;
}

/// Closed set of audit actions emitted by the server. Renderer maps each to
/// an icon + accent color.
enum AuditAction {
  tripCreated,
  tripClosed,
  allocationFromAdmin,
  allocationFromLeader,
  allocationAccepted,
  allocationDeclined,
  transferSent,
  transferAccepted,
  transferDeclined,
  expenseLogged,
  userSignedIn,
  userCreated,
  userUpdated;

  static AuditAction fromWire(String s) {
    switch (s) {
      case 'TRIP_CREATED':
        return AuditAction.tripCreated;
      case 'TRIP_CLOSED':
        return AuditAction.tripClosed;
      case 'ALLOCATION_FROM_ADMIN':
        return AuditAction.allocationFromAdmin;
      case 'ALLOCATION_FROM_LEADER':
        return AuditAction.allocationFromLeader;
      case 'ALLOCATION_ACCEPTED':
        return AuditAction.allocationAccepted;
      case 'ALLOCATION_DECLINED':
        return AuditAction.allocationDeclined;
      case 'TRANSFER_SENT':
        return AuditAction.transferSent;
      case 'TRANSFER_ACCEPTED':
        return AuditAction.transferAccepted;
      case 'TRANSFER_DECLINED':
        return AuditAction.transferDeclined;
      case 'EXPENSE_LOGGED':
        return AuditAction.expenseLogged;
      case 'USER_SIGNED_IN':
        return AuditAction.userSignedIn;
      case 'USER_CREATED':
        return AuditAction.userCreated;
      case 'USER_UPDATED':
        return AuditAction.userUpdated;
      default:
        throw ArgumentError('Unknown audit action: $s');
    }
  }
}
