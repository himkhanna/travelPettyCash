import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../../../core/money/money.dart';
import '../domain/trip.dart';
import 'trip_repository.dart';

/// Real backend implementation of [TripRepository] — talks to /api/v1/trips/*.
///
/// Until the funds/expense backend slices ship, /trips/{id}/balances returns
/// the trip's totalBudget against zero spent. Mobile renderers don't need to
/// know: the shape matches what FakeTripRepository produces, and the per-source
/// rows arrive empty-but-valid so the donut chart renders an "all balance" arc.
class ApiTripRepository implements TripRepository {
  ApiTripRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<List<Trip>> activeTrips() => _list(status: TripStatus.active);

  @override
  Future<List<Trip>> allTrips({TripStatus? status}) => _list(status: status);

  Future<List<Trip>> _list({TripStatus? status}) async {
    final Map<String, dynamic> query = <String, dynamic>{};
    if (status != null) query['status'] = _statusToApi(status);
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/trips',
        queryParameters: query,
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _tripFromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Trip> tripById(String id) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('/api/v1/trips/$id');
      return _tripFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<TripBalances> balances(String tripId, BalanceScope scope) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/trips/$tripId/balances',
        queryParameters: <String, dynamic>{'scope': _scopeToApi(scope)},
      );
      return _balancesFromJson(resp.data as Map<String, dynamic>, scope);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Trip> createTrip({
    required String name,
    required String countryCode,
    required String countryName,
    required String currency,
    required String leaderId,
    required List<String> memberIds,
    required Money totalBudget,
    String? missionId,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/trips',
        data: <String, dynamic>{
          'name': name,
          'countryCode': countryCode,
          'countryName': countryName,
          'currency': currency,
          'leaderId': leaderId,
          'memberIds': memberIds,
          'totalBudget': <String, dynamic>{
            'amount': totalBudget.amountMinor,
            'currency': totalBudget.currencyCode,
          },
          if (missionId != null) 'missionId': missionId,
        },
      );
      return _tripFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Trip> closeTrip(String tripId) async {
    try {
      final Response<dynamic> resp = await _dio.patch<dynamic>(
        '/api/v1/trips/$tripId/close',
      );
      return _tripFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<void> deleteTrip(String tripId) async {
    try {
      await _dio.delete<dynamic>('/api/v1/trips/$tripId');
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Trip> updateTrip({
    required String tripId,
    String? name,
    String? leaderId,
    List<String>? memberIds,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (leaderId != null) body['leaderId'] = leaderId;
    if (memberIds != null) body['memberIds'] = memberIds;
    try {
      final Response<dynamic> resp = await _dio.patch<dynamic>(
        '/api/v1/trips/$tripId',
        data: body,
      );
      return _tripFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  // ---- parsing ------------------------------------------------------

  Trip _tripFromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> budget = j['totalBudget'] as Map<String, dynamic>;
    return Trip(
      id: j['id'] as String,
      name: j['name'] as String,
      countryCode: j['countryCode'] as String,
      countryName: j['countryName'] as String,
      currency: j['currency'] as String,
      status: _statusFromApi(j['status'] as String),
      createdBy: j['createdBy'] as String,
      leaderId: j['leaderId'] as String,
      memberIds: (j['memberIds'] as List<dynamic>).cast<String>(),
      totalBudget: _moneyFromJson(budget),
      createdAt: DateTime.parse(j['createdAt'] as String),
      closedAt: j['closedAt'] == null
          ? null
          : DateTime.parse(j['closedAt'] as String),
      missionId: j['missionId'] as String?,
    );
  }

  TripBalances _balancesFromJson(Map<String, dynamic> j, BalanceScope scope) {
    final List<dynamic> per = j['perSource'] as List<dynamic>;
    return TripBalances(
      tripId: j['tripId'] as String,
      scope: scope,
      totalBudget: _moneyFromJson(j['totalBudget'] as Map<String, dynamic>),
      totalSpent: _moneyFromJson(j['totalSpent'] as Map<String, dynamic>),
      totalBalance: _moneyFromJson(j['totalBalance'] as Map<String, dynamic>),
      perSource: per
          .map((dynamic e) => _sourceBalanceFromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  SourceBalance _sourceBalanceFromJson(Map<String, dynamic> j) => SourceBalance(
        sourceId: j['sourceId'] as String,
        sourceName: j['sourceName'] as String,
        sourceNameAr: j['sourceNameAr'] as String,
        received: _moneyFromJson(j['received'] as Map<String, dynamic>),
        spent: _moneyFromJson(j['spent'] as Map<String, dynamic>),
        balance: _moneyFromJson(j['balance'] as Map<String, dynamic>),
      );

  Money _moneyFromJson(Map<String, dynamic> j) =>
      Money(j['amount'] as int, j['currency'] as String);

  TripStatus _statusFromApi(String s) {
    switch (s) {
      case 'DRAFT':
        return TripStatus.draft;
      case 'ACTIVE':
        return TripStatus.active;
      case 'CLOSED':
        return TripStatus.closed;
      default:
        throw ArgumentError('Unknown trip status: $s');
    }
  }

  String _statusToApi(TripStatus s) {
    switch (s) {
      case TripStatus.draft:
        return 'DRAFT';
      case TripStatus.active:
        return 'ACTIVE';
      case TripStatus.closed:
        return 'CLOSED';
    }
  }

  String _scopeToApi(BalanceScope s) {
    switch (s) {
      case BalanceScope.me:
        return 'me';
      case BalanceScope.leader:
        return 'leader';
      case BalanceScope.trip:
        return 'trip';
    }
  }
}
