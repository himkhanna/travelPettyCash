import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';

/// The server-rendered report types. Original four per CLAUDE.md §10
/// (user / tripFull / financeLetter / dg) plus two newer scopes:
/// [tripDaily] (one UTC day) and [missionRollup] (every trip under a
/// mission).
enum ReportDownloadKind {
  user,
  tripFull,
  financeLetter,
  dg,
  tripDaily,
  missionRollup,
}

/// Wire format. PDF for letters / dashboards; XLSX for tabular reports.
enum ReportFormat { pdf, xlsx }

class DownloadedReport {
  const DownloadedReport({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });
  final Uint8List bytes;
  final String filename;
  final String contentType;
}

/// API-backed report downloads. Hits `/api/v1/reports/...` and returns the
/// raw bytes + filename (from Content-Disposition). The caller is responsible
/// for triggering a browser download / saving to disk.
class ReportDownloadRepository {
  ReportDownloadRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<DownloadedReport> download({
    required ReportDownloadKind kind,
    String? tripId,
    String? missionId,
    String? userId,
    DateTime? date,
    ReportFormat? format,
  }) async {
    final String path = _pathFor(
      kind, tripId: tripId, missionId: missionId, userId: userId,
    );
    final String fmt = (format ?? _defaultFormat(kind)).name;
    final Map<String, dynamic> query = <String, dynamic>{'format': fmt};
    if (date != null) {
      // ISO yyyy-MM-dd — server parses with LocalDate.parse.
      final String iso =
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      query['date'] = iso;
    }
    try {
      final Response<List<int>> resp = await _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      );
      final Uint8List bytes = Uint8List.fromList(resp.data ?? <int>[]);
      return DownloadedReport(
        bytes: bytes,
        filename: _filenameFrom(resp.headers, _fallbackName(kind, fmt)),
        contentType: resp.headers.value('content-type') ?? _mimeFor(fmt),
      );
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  String _pathFor(
    ReportDownloadKind kind, {
    String? tripId,
    String? missionId,
    String? userId,
  }) {
    switch (kind) {
      case ReportDownloadKind.user:
        if (tripId == null || userId == null) {
          throw ArgumentError('tripId and userId required for user reports');
        }
        return '/api/v1/reports/trip/$tripId/user/$userId';
      case ReportDownloadKind.tripFull:
        if (tripId == null) throw ArgumentError('tripId required');
        return '/api/v1/reports/trip/$tripId/full';
      case ReportDownloadKind.financeLetter:
        if (tripId == null) throw ArgumentError('tripId required');
        return '/api/v1/reports/trip/$tripId/finance';
      case ReportDownloadKind.dg:
        if (tripId == null) throw ArgumentError('tripId required');
        return '/api/v1/reports/trip/$tripId/dg';
      case ReportDownloadKind.tripDaily:
        if (tripId == null) throw ArgumentError('tripId required');
        return '/api/v1/reports/trip/$tripId/daily';
      case ReportDownloadKind.missionRollup:
        if (missionId == null) throw ArgumentError('missionId required');
        return '/api/v1/reports/mission/$missionId';
    }
  }

  ReportFormat _defaultFormat(ReportDownloadKind k) {
    switch (k) {
      case ReportDownloadKind.user:
        return ReportFormat.pdf;
      case ReportDownloadKind.tripFull:
      case ReportDownloadKind.tripDaily:
      case ReportDownloadKind.missionRollup:
        return ReportFormat.xlsx;
      case ReportDownloadKind.financeLetter:
      case ReportDownloadKind.dg:
        return ReportFormat.pdf;
    }
  }

  String _mimeFor(String format) {
    return format == 'xlsx'
        ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        : 'application/pdf';
  }

  String _fallbackName(ReportDownloadKind k, String format) =>
      '${k.name}-report.$format';

  String _filenameFrom(Headers headers, String fallback) {
    final String? cd = headers.value('content-disposition');
    if (cd == null) return fallback;
    // RFC 6266 — extract filename from `attachment; filename="x.pdf"`.
    final RegExpMatch? m =
        RegExp(r'filename="([^"]+)"').firstMatch(cd) ??
        RegExp(r'filename=([^;]+)').firstMatch(cd);
    return m?.group(1)?.trim() ?? fallback;
  }
}
