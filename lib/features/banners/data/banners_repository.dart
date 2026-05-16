import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';
import 'banner_models.dart';

/// Wraps catalog-service /admin/banners endpoints.
///
/// Image upload is multipart; the backend validates dimensions + ratio and
/// returns 400 with a user-friendly Russian message on rejection. The repo
/// surfaces that as a thrown [BannerValidationException] so the UI can show
/// the message in a snackbar.
class BannersRepository {
  final ApiClient api;
  BannersRepository({required this.api});

  static const String _adminPath = '/gw/catalog/admin/banners';
  static const String _publicPath = '/gw/catalog/banners';

  Future<List<BannerItem>> listAll() async {
    final resp = await api.dio.get(_adminPath);
    // asJsonList tolerates an error envelope / null body; a raw
    // `resp.data as List` threw a CastError that bypassed the
    // DioException handling and broke the whole banners screen.
    return asJsonList(resp.data).map(BannerItem.fromJson).toList();
  }

  Future<List<BannerItem>> listPublic() async {
    final resp = await api.dio.get(_publicPath);
    return asJsonList(resp.data).map(BannerItem.fromJson).toList();
  }

  Future<BannerItem> create({
    required File imageFile,
    String? title,
    String? linkUrl,
    int sortOrder = 0,
    bool active = true,
  }) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.uri.pathSegments.last,
      ),
      if (title != null && title.isNotEmpty) 'title': title,
      if (linkUrl != null && linkUrl.isNotEmpty) 'link_url': linkUrl,
      'sort_order': sortOrder,
      'active': active,
    });

    try {
      final resp = await api.dio.post(_adminPath, data: formData);
      return BannerItem.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapValidationError(e);
    }
  }

  Future<BannerItem> update({
    required int id,
    File? imageFile,
    String? title,
    String? linkUrl,
    int? sortOrder,
    bool? active,
  }) async {
    final form = <String, dynamic>{};
    if (imageFile != null) {
      form['image'] = await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.uri.pathSegments.last,
      );
    }
    if (title != null) form['title'] = title;
    if (linkUrl != null) form['link_url'] = linkUrl;
    if (sortOrder != null) form['sort_order'] = sortOrder;
    if (active != null) form['active'] = active;

    try {
      final resp = await api.dio.patch('$_adminPath/$id', data: FormData.fromMap(form));
      return BannerItem.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapValidationError(e);
    }
  }

  Future<void> delete(int id) async {
    await api.dio.delete('$_adminPath/$id');
  }

  Future<void> reorder(List<int> orderedIds) async {
    await api.dio.post(
      '$_adminPath/reorder',
      data: {'ids': orderedIds},
    );
  }

  Exception _mapValidationError(DioException e) {
    final detail = e.response?.data;
    if (detail is Map && detail['detail'] is String) {
      return BannerValidationException(detail['detail'] as String);
    }
    return e;
  }
}

class BannerValidationException implements Exception {
  final String message;
  BannerValidationException(this.message);

  @override
  String toString() => message;
}
