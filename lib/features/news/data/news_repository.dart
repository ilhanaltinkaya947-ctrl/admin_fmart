import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';
import 'news_models.dart';

/// catalog-service /admin/news (28.10). Image rules are the banners' rules
/// (ratio 1.5–1.7, at least 1200×700); a rejected image comes back as a 400
/// with a Russian message, surfaced as [NewsValidationException].
class NewsRepository {
  final ApiClient api;
  NewsRepository({required this.api});

  static const String _adminPath = '/gw/catalog/admin/news';

  Future<List<NewsPost>> listAll() async {
    final resp = await api.dio.get(_adminPath);
    return asJsonList(resp.data).map(NewsPost.fromJson).toList();
  }

  Future<NewsPost> create({
    required String title,
    String? body,
    String? titleKk,
    String? bodyKk,
    File? imageFile,
    List<int> storeIds = const [],
    bool active = true,
    bool pinned = false,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final form = <String, dynamic>{
      'title': title,
      if (body != null && body.isNotEmpty) 'body': body,
      if (titleKk != null && titleKk.isNotEmpty) 'title_kk': titleKk,
      if (bodyKk != null && bodyKk.isNotEmpty) 'body_kk': bodyKk,
      if (storeIds.isNotEmpty) 'store_ids': storeIds.join(','),
      'active': active,
      'pinned': pinned,
      if (startsAt != null) 'starts_at': startsAt.toUtc().toIso8601String(),
      if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
    };
    if (imageFile != null) {
      form['image'] = await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.uri.pathSegments.last,
      );
    }
    try {
      final resp = await api.dio.post(_adminPath, data: FormData.fromMap(form));
      return NewsPost.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapValidationError(e);
    }
  }

  /// Every text field is sent: an empty optional text goes as the token
  /// `null` (FastAPI reads an empty form value as "not sent").
  Future<NewsPost> update({
    required int id,
    required String title,
    required String body,
    required String titleKk,
    required String bodyKk,
    required List<int> storeIds,
    required bool active,
    required bool pinned,
    File? imageFile,
    bool removeImage = false,
    DateTime? startsAt,
    bool clearStartsAt = false,
    DateTime? endsAt,
    bool clearEndsAt = false,
  }) async {
    String orNull(String s) => s.isEmpty ? 'null' : s;
    final form = <String, dynamic>{
      'title': title,
      'body': orNull(body),
      'title_kk': orNull(titleKk),
      'body_kk': orNull(bodyKk),
      'store_ids': storeIds.isEmpty ? 'null' : storeIds.join(','),
      'active': active,
      'pinned': pinned,
      if (removeImage && imageFile == null) 'remove_image': true,
    };
    if (clearStartsAt) {
      form['starts_at'] = 'null';
    } else if (startsAt != null) {
      form['starts_at'] = startsAt.toUtc().toIso8601String();
    }
    if (clearEndsAt) {
      form['ends_at'] = 'null';
    } else if (endsAt != null) {
      form['ends_at'] = endsAt.toUtc().toIso8601String();
    }
    if (imageFile != null) {
      form['image'] = await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.uri.pathSegments.last,
      );
    }
    try {
      final resp = await api.dio.patch('$_adminPath/$id', data: FormData.fromMap(form));
      return NewsPost.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapValidationError(e);
    }
  }

  Future<void> delete(int id) async {
    await api.dio.delete('$_adminPath/$id');
  }

  Exception _mapValidationError(DioException e) {
    final detail = e.response?.data;
    if (detail is Map && detail['detail'] is String) {
      return NewsValidationException(detail['detail'] as String);
    }
    return e;
  }
}

class NewsValidationException implements Exception {
  final String message;
  NewsValidationException(this.message);

  @override
  String toString() => message;
}
