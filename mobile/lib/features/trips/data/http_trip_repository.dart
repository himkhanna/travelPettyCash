import '../../../core/api/api_client.dart';
import '../../../core/money/money.dart';
import '../domain/trip.dart';
import 'trip_repository.dart';

/// HTTP repo for /api/v1/trips + /api/v1/trips/{id}/balances. Replaces
/// FakeTripRepository when BackendMode.http is selected.
class HttpTripRepository implements TripRepository {
  HttpTripRepository(this._api, {required String Function() currentUserId})
      : _currentUserId = currentUserId;

  final ApiClient _api;
  final String Function() _currentUserId;

  @override
  Future<List<Trip>> activeTrips() => _list(status: 'ACTIVE');

  @override
  Future<List<Trip>> allTrips({TripStatus? status}) =>
      _list(status: status?.name.toUpperCase());

  Future<List<Trip>> _list({String? status}) async {
    final List<dynamic> raw = await _api.get<List<dynamic>>(
      '/api/v1/trips',
      query: status == null ? null : <String, Object?>{'status': status},
    );
    return raw
        .cast<Map<String, dynamic>>()
        .map(_parseTrip)
        .toList(growable: false);
  }

  @override
  Future<Trip> tripById(String id) async {
    final Map<String, dynamic> json =
        await _api.get<Map<String, dynamic>>('/api/v1/trips/$id');
    return _parseTrip(json);
  }

  @override
  Future<TripBalances> balances(String tripId, BalanceScope scope) async {
    final Map<String, Object?> query = <String, Object?>{
      'scope': switch (scope) {
        BalanceScope.me => 'ME',
        BalanceScope.trip => 'TRIP',
        BalanceScope.leader => 'LEADER',
      },
    };
    if (scope == BalanceScope.me) query['userId'] = _currentUserId();
    final Map<String, dynamic> json = await _api.get<Map<String, dynamic>>(
      '/api/v1/trips/$tripId/balances',
      query: query,
    );
    return TripBalances(
      tripId: json['tripId'] as String,
      scope: scope,
      totalBudget: _money(json['totalBudget'] as Map<String, dynamic>),
      totalSpent: _money(json['totalSpent'] as Map<String, dynamic>),
      totalBalance: _money(json['totalBalance'] as Map<String, dynamic>),
      perSource: (json['perSource'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((Map<String, dynamic> p) => SourceBalance(
                sourceId: p['sourceId'] as String,
                // Names come from the source list endpoint — we don't have
                // them inline. The CMS / dashboard joins by id.
                sourceName: p['sourceId'] as String,
                sourceNameAr: p['sourceId'] as String,
                received: _money(p['received'] as Map<String, dynamic>),
                spent: _money(p['spent'] as Map<String, dynamic>),
                balance: _money(p['balance'] as Map<String, dynamic>),
              ))
          .toList(growable: false),
    );
  }

  @override
  Future<Trip> createTrip({
    required String name,
    required String countryCode,
    required String currency,
    required String leaderId,
    required List<String> memberIds,
  }) async {
    final Map<String, dynamic> json =
        await _api.post<Map<String, dynamic>>('/api/v1/trips', body: <String, Object?>{
      'name': name,
      'countryCode': countryCode,
      'countryName': _countryNameFor(countryCode),
      'currency': currency,
      'leaderId': leaderId,
      'memberIds': memberIds,
      'totalBudget': <String, Object?>{'amount': 0, 'currency': currency},
    });
    return _parseTrip(json);
  }

  @override
  Future<Trip> closeTrip(String tripId) async {
    final Map<String, dynamic> json = await _api.post<Map<String, dynamic>>(
      '/api/v1/trips/$tripId/close',
    );
    return _parseTrip(json);
  }

  Trip _parseTrip(Map<String, dynamic> j) {
    final Map<String, dynamic> bud = j['totalBudget'] as Map<String, dynamic>;
    return Trip(
      id: j['id'] as String,
      name: j['name'] as String,
      countryCode: j['countryCode'] as String,
      countryName: j['countryName'] as String,
      currency: j['currency'] as String,
      status: _statusFromApi(j['status'] as String),
      createdBy: j['createdBy'] as String,
      leaderId: j['leaderId'] as String,
      memberIds: ((j['memberIds'] as List<dynamic>?) ?? const <dynamic>[])
          .cast<String>()
          .toList(growable: false),
      totalBudget: _money(bud),
      createdAt: DateTime.parse(j['createdAt'] as String),
      closedAt: j['closedAt'] == null
          ? null
          : DateTime.parse(j['closedAt'] as String),
    );
  }

  Money _money(Map<String, dynamic> j) =>
      Money((j['amount'] as num).toInt(), j['currency'] as String);

  TripStatus _statusFromApi(String code) => switch (code) {
        'DRAFT' => TripStatus.draft,
        'ACTIVE' => TripStatus.active,
        'CLOSED' => TripStatus.closed,
        _ => TripStatus.draft,
      };

  String _countryNameFor(String code) => switch (code) {
        'SA' => 'Saudi Arabia',
        'AE' => 'United Arab Emirates',
        'EG' => 'Egypt',
        'JO' => 'Jordan',
        'KW' => 'Kuwait',
        'BH' => 'Bahrain',
        'OM' => 'Oman',
        'QA' => 'Qatar',
        'GB' => 'United Kingdom',
        'US' => 'United States',
        'FR' => 'France',
        'DE' => 'Germany',
        'IT' => 'Italy',
        'JP' => 'Japan',
        _ => code,
      };
}
