import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/dio_client.dart';

/// One result returned from the admin global-search endpoint. Maps 1:1 to
/// the server's `SearchController.SearchHit` record.
class SearchHit {
  const SearchHit({
    required this.type,
    required this.id,
    required this.label,
    required this.subtitle,
    required this.link,
  });

  /// One of 'trip', 'user', 'mission'.
  final String type;
  final String id;
  final String label;
  final String subtitle;
  /// Front-end route to navigate to when the user picks this hit.
  final String link;

  factory SearchHit.fromJson(Map<String, dynamic> j) => SearchHit(
        type: j['type'] as String,
        id: j['id'] as String,
        label: j['label'] as String,
        subtitle: j['subtitle'] as String,
        link: j['link'] as String,
      );
}

class SearchRepository {
  SearchRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<List<SearchHit>> search(String query) async {
    final String q = query.trim();
    if (q.length < 2) return const <SearchHit>[];
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/search',
        queryParameters: <String, dynamic>{'q': q},
      );
      final Map<String, dynamic> body = resp.data as Map<String, dynamic>;
      return (body['hits'] as List<dynamic>)
          .map((dynamic e) => SearchHit.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }
}

final Provider<SearchRepository> searchRepositoryProvider =
    Provider<SearchRepository>((Ref ref) {
  return SearchRepository(dio: ref.watch(dioProvider));
});

/// Family keyed on the trimmed query string. autoDispose so closed
/// overlays don't keep stale entries alive in the cache.
final AutoDisposeFutureProviderFamily<List<SearchHit>, String>
    globalSearchProvider =
    FutureProvider.family.autoDispose<List<SearchHit>, String>((
  Ref ref,
  String q,
) async {
  return ref.read(searchRepositoryProvider).search(q);
});
