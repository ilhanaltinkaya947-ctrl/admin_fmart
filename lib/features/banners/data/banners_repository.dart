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

  /// Upload a zip of banner images in one call. Backend extracts the
  /// zip, validates each image, and creates a banner row per file in
  /// alphabetical filename order. Returns a per-file summary so the UI
  /// can show which ones landed and which got rejected (wrong ratio,
  /// corrupt file, etc).
  Future<BannerBulkResult> bulkUploadZip({
    required File zipFile,
    bool active = true,
  }) async {
    final formData = FormData.fromMap({
      'archive': await MultipartFile.fromFile(
        zipFile.path,
        filename: zipFile.uri.pathSegments.last,
      ),
      'active': active,
    });
    try {
      final resp = await api.dio.post(
        '$_adminPath/bulk-upload',
        data: formData,
      );
      return BannerBulkResult.fromJson(
        (resp.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw _mapValidationError(e);
    }
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

class BannerBulkResult {
  final int createdCount;
  final int skippedCount;
  final List<BannerBulkError> errors;

  BannerBulkResult({
    required this.createdCount,
    required this.skippedCount,
    required this.errors,
  });

  factory BannerBulkResult.fromJson(Map<String, dynamic> j) => BannerBulkResult(
        createdCount: j['created_count'] as int? ?? 0,
        skippedCount: j['skipped_count'] as int? ?? 0,
        errors: ((j['errors'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => BannerBulkError.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}

class BannerBulkError {
  final String filename;
  final String error;
  BannerBulkError({required this.filename, required this.error});
  factory BannerBulkError.fromJson(Map<String, dynamic> j) => BannerBulkError(
        filename: j['filename']?.toString() ?? '',
        error: j['error']?.toString() ?? '',
      );
}

class BannerValidationException implements Exception {
  final String message;
  BannerValidationException(this.message);

  @override
  String toString() => message;
}
