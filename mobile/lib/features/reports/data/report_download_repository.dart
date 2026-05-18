import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';

/// The four server-rendered report types per CLAUDE.md §10. Each one maps
/// to a different backend endpoint and produces either PDF or XLSX bytes.
enum ReportDownloadKind { user, tripFull, financeLetter, dg }

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
    required String tripId,
    String? userId,
    ReportFormat? format,
  }) async {
    final String path = _pathFor(kind, tripId: tripId, userId: userId);
    final String fmt = (format ?? _defaultFormat(kind)).name;
    try {
      final Response<List<int>> resp = await _dio.get<List<int>>(
        path,
        queryParameters: <String, dynamic>{'format': fmt},
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
    required String tripId,
    String? userId,
  }) {
    switch (kind) {
      case ReportDownloadKind.user:
        if (userId == null) {
          throw ArgumentError('userId is required for user reports');
        }
        return '/api/v1/reports/trip/$tripId/user/$userId';
      case ReportDownloadKind.tripFull:
        return '/api/v1/reports/trip/$tripId/full';
      case ReportDownloadKind.financeLetter:
        return '/api/v1/reports/trip/$tripId/finance';
      case ReportDownloadKind.dg:
        return '/api/v1/reports/trip/$tripId/dg';
    }
  }

  ReportFormat _defaultFormat(ReportDownloadKind k) {
    switch (k) {
      // User: PDF default (Excel offered as a secondary)
      case ReportDownloadKind.user:
        return ReportFormat.pdf;
      // Trip Full: tabular, XLSX is the primary format
      case ReportDownloadKind.tripFull:
        return ReportFormat.xlsx;
      // Letterhead: PDF only
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
