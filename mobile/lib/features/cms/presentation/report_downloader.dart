import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/fake/fake_config.dart';
import 'report_web_save.dart'
    if (dart.library.io) 'report_web_save_stub.dart';

/// Triggers a real file download from /api/v1/reports/trip/{id}. Refuses
/// the call (with a guidance toast) when BackendMode is fake — there's
/// nothing to download against in that case.
class ReportDownloader {
  ReportDownloader(this._ref);
  final WidgetRef _ref;

  Future<void> download({
    required BuildContext context,
    required String tripId,
    required String format, // xlsx | pdf
    required String scope, // user | team | finance | dg
  }) async {
    final FakeConfig cfg = _ref.read(fakeConfigProvider);
    if (cfg.backendMode != BackendMode.http) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Switch BACKEND to HTTP on the landing screen and sign in '
          'before downloading a real report file.',
        ),
      ));
      return;
    }
    final ApiClient api = _ref.read(apiClientProvider);
    try {
      final ({List<int> bytes, String? filename, String? contentType}) r =
          await api.downloadBytes(
        '/api/v1/reports/trip/$tripId',
        query: <String, Object?>{'format': format, 'scope': scope},
      );
      final Uint8List bytes = Uint8List.fromList(r.bytes);
      final String name = r.filename ?? 'report-$tripId.$format';
      final String mime = r.contentType ?? 'application/octet-stream';
      if (kIsWeb) {
        triggerBrowserDownload(bytes, name, mime);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Downloaded $name (${bytes.length} bytes).'),
        ));
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Fetched ${bytes.length} bytes — native save-to-disk lands '
            'in the next slice. Use the web build for now.',
          ),
        ));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Download failed: $e'),
      ));
    }
  }
}
