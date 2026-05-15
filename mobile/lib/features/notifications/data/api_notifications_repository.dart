import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../../funds/data/api_allocation_repository.dart';
import '../../funds/data/api_transfer_repository.dart';
import '../../funds/domain/funding.dart';
import '../domain/notification.dart';
import 'notifications_repository.dart';

/// Real backend implementation. Polls {@code /notifications} every 5 seconds
/// for the {@link watch} stream — push notifications are out of scope for
/// this slice (CLAUDE.md §16 sovereignty review pending on FCM/APNs).
class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository({
    required Dio dio,
    Duration pollInterval = const Duration(seconds: 5),
  })  : _dio = dio,
        _pollInterval = pollInterval,
        _alloc = ApiAllocationRepository(dio: dio),
        _xfer = ApiTransferRepository(dio: dio);

  final Dio _dio;
  final Duration _pollInterval;
  final ApiAllocationRepository _alloc;
  final ApiTransferRepository _xfer;

  @override
  Stream<List<AppNotification>> watch({required String userId}) {
    // The backend already scopes /notifications to the caller's userId —
    // the {@code userId} argument is ignored here. Polling is a stop-gap
    // until a websocket / SSE channel is wired in.
    final StreamController<List<AppNotification>> controller =
        StreamController<List<AppNotification>>.broadcast();
    Timer? timer;

    Future<void> tick() async {
      if (controller.isClosed) return;
      try {
        controller.add(await list());
      } catch (e) {
        controller.addError(e);
      }
    }

    controller.onListen = () {
      tick(); // emit immediately, don't wait one interval
      timer = Timer.periodic(_pollInterval, (_) => tick());
    };
    controller.onCancel = () {
      timer?.cancel();
      controller.close();
    };
    return controller.stream;
  }

  @override
  Future<List<AppNotification>> list({String? cursor, int limit = 30}) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('/api/v1/notifications');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<AppNotification> markRead(String notificationId) async {
    try {
      final Response<dynamic> resp = await _dio.patch<dynamic>(
        '/api/v1/notifications/$notificationId/read',
      );
      return _fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  /// Accept / decline routes through the underlying entity's respond endpoint.
  /// The backend flips the matching notification to ACTED inside the same
  /// transaction, so we only need to refetch one row afterwards.
  @override
  Future<AppNotification> act({
    required String notificationId,
    required NotificationAction action,
  }) async {
    // Pull the row so we know which entity to dispatch to.
    final AppNotification current = await _findById(notificationId);
    final AllocationStatus response = action == NotificationAction.accept
        ? AllocationStatus.accepted
        : AllocationStatus.declined;

    switch (current.type) {
      case NotificationType.allocationReceived:
        final String? allocId = current.payload['allocationId'] as String?;
        if (allocId == null) {
          throw StateError('Notification payload missing allocationId');
        }
        await _alloc.respond(allocationId: allocId, response: response);
        break;
      case NotificationType.transferReceived:
        final String? xferId = current.payload['transferId'] as String?;
        if (xferId == null) {
          throw StateError('Notification payload missing transferId');
        }
        await _xfer.respond(transferId: xferId, response: response);
        break;
      case NotificationType.transferAccepted:
      case NotificationType.tripAssigned:
      case NotificationType.tripClosed:
      case NotificationType.expenseQuery:
        // Not actionable on the backend — just mark read and return.
        return markRead(notificationId);
    }
    // Backend auto-acted; refetch the list and pluck the updated row.
    return _findById(notificationId);
  }

  Future<AppNotification> _findById(String id) async {
    final List<AppNotification> all = await list();
    return all.firstWhere(
      (AppNotification n) => n.id == id,
      orElse: () => throw StateError('Notification not found: $id'),
    );
  }

  @override
  Future<void> delete(String notificationId) {
    // Backend has no delete endpoint yet — the inbox is append-only and
    // state-transitioned. Deletion would be a soft-delete + audit row, a
    // future slice.
    throw UnsupportedError('Deleting notifications is not supported by the API yet.');
  }

  @override
  Future<void> deleteAll() {
    throw UnsupportedError('Deleting notifications is not supported by the API yet.');
  }

  AppNotification _fromJson(Map<String, dynamic> j) {
    return AppNotification(
      id: j['id'] as String,
      userId: j['userId'] as String,
      type: _typeFromApi(j['type'] as String),
      actionable: j['actionable'] as bool? ?? false,
      state: _stateFromApi(j['state'] as String),
      payload: (j['payload'] as Map<String, dynamic>?)?.cast<String, Object?>()
          ?? const <String, Object?>{},
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }

  NotificationType _typeFromApi(String s) {
    switch (s) {
      case 'ALLOCATION_RECEIVED':
        return NotificationType.allocationReceived;
      case 'TRANSFER_RECEIVED':
        return NotificationType.transferReceived;
      case 'TRANSFER_ACCEPTED':
        return NotificationType.transferAccepted;
      case 'TRIP_ASSIGNED':
        return NotificationType.tripAssigned;
      case 'TRIP_CLOSED':
        return NotificationType.tripClosed;
      case 'EXPENSE_QUERY':
        return NotificationType.expenseQuery;
      default:
        throw ArgumentError('Unknown notification type: $s');
    }
  }

  NotificationState _stateFromApi(String s) {
    switch (s) {
      case 'UNREAD':
        return NotificationState.unread;
      case 'READ':
        return NotificationState.read;
      case 'ACTED':
        return NotificationState.acted;
      default:
        throw ArgumentError('Unknown notification state: $s');
    }
  }
}
