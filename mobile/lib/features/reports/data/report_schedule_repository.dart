import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/dio_client.dart';

/// Either a trip or a mission. Mirrors `ReportSchedule.Scope` on the server.
enum ScheduleScope { trip, mission }

extension ScheduleScopeWire on ScheduleScope {
  String get wire => switch (this) {
        ScheduleScope.trip => 'TRIP',
        ScheduleScope.mission => 'MISSION',
      };
  static ScheduleScope fromWire(String s) => switch (s.toUpperCase()) {
        'TRIP' => ScheduleScope.trip,
        'MISSION' => ScheduleScope.mission,
        _ => throw ArgumentError('Unknown scope $s'),
      };
}

/// Cadence kind. Only DAILY ships in v1; weekly/monthly land later.
enum ScheduleKind { daily }

extension ScheduleKindWire on ScheduleKind {
  String get wire => 'DAILY';
  static ScheduleKind fromWire(String s) => ScheduleKind.daily;
}

class ReportScheduleRow {
  const ReportScheduleRow({
    required this.id,
    required this.scope,
    required this.scopeId,
    required this.kind,
    required this.utcHour,
    required this.active,
    required this.createdById,
    this.lastRunAt,
    required this.nextRunAt,
    required this.createdAt,
  });

  final String id;
  final ScheduleScope scope;
  final String scopeId;
  final ScheduleKind kind;
  final int utcHour;
  final bool active;
  final String createdById;
  final DateTime? lastRunAt;
  final DateTime nextRunAt;
  final DateTime createdAt;

  factory ReportScheduleRow.fromJson(Map<String, dynamic> j) =>
      ReportScheduleRow(
        id: j['id'] as String,
        scope: ScheduleScopeWire.fromWire(j['scope'] as String),
        scopeId: j['scopeId'] as String,
        kind: ScheduleKindWire.fromWire(j['kind'] as String),
        utcHour: (j['utcHour'] as num).toInt(),
        active: j['active'] as bool,
        createdById: j['createdById'] as String,
        lastRunAt: j['lastRunAt'] == null
            ? null
            : DateTime.parse(j['lastRunAt'] as String),
        nextRunAt: DateTime.parse(j['nextRunAt'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class ReportScheduleRepository {
  ReportScheduleRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<List<ReportScheduleRow>> list() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('/api/v1/report-schedules');
      return (resp.data as List<dynamic>)
          .map((dynamic e) =>
              ReportScheduleRow.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  Future<ReportScheduleRow> create({
    required ScheduleScope scope,
    required String scopeId,
    required int utcHour,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/report-schedules',
        data: <String, dynamic>{
          'scope': scope.wire,
          'scopeId': scopeId,
          'kind': 'DAILY',
          'utcHour': utcHour,
        },
      );
      return ReportScheduleRow.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  Future<ReportScheduleRow> update({
    required String id,
    bool? active,
    int? utcHour,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.patch<dynamic>(
        '/api/v1/report-schedules/$id',
        data: <String, dynamic>{
          if (active != null) 'active': active,
          if (utcHour != null) 'utcHour': utcHour,
        },
      );
      return ReportScheduleRow.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete<dynamic>('/api/v1/report-schedules/$id');
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }
}

final Provider<ReportScheduleRepository> reportScheduleRepositoryProvider =
    Provider<ReportScheduleRepository>((Ref ref) {
  return ReportScheduleRepository(dio: ref.watch(dioProvider));
});

final AutoDisposeFutureProvider<List<ReportScheduleRow>>
    reportSchedulesProvider =
    FutureProvider.autoDispose<List<ReportScheduleRow>>((Ref ref) async {
  return ref.read(reportScheduleRepositoryProvider).list();
});
