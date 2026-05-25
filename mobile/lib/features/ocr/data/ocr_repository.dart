import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/dio_client.dart';
import '../domain/ocr_suggestion.dart';

/// Posts a receipt image to the backend's stateless OCR endpoint and
/// returns whatever fields Tesseract managed to extract. The backend
/// returns {@code engineAvailable: false} when Tesseract isn't installed
/// on the host — callers should respect that and show a "not configured"
/// hint rather than treating it as a hard error.
class OcrRepository {
  OcrRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<OcrSuggestion> ocrReceipt({
    required Uint8List bytes,
    required String filename,
    required String mime,
  }) async {
    try {
      final FormData form = FormData.fromMap(<String, dynamic>{
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType.parse(mime),
        ),
      });
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/ocr/receipt',
        data: form,
      );
      return OcrSuggestion.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }
}

final Provider<OcrRepository> ocrRepositoryProvider =
    Provider<OcrRepository>((Ref ref) {
  return OcrRepository(dio: ref.watch(dioProvider));
});
