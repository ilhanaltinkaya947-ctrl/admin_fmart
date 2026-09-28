import 'dart:io';

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

  /// A total order over the admin list: publish position, then id.
  ///
  /// This is the client-side mirror of the server's
  /// `ORDER BY sort_order ASC, id ASC` (BannerRepository.list_all). It exists
  /// because 35 rows in prod share duplicated `sort_order` values with
  /// inactive-placeholder rows (5 is at 3 alongside 31, 6 at 4 alongside 32,
  /// …), and the admin endpoint returns them in whatever order the planner
  /// chose. Without a total order the tiles would shuffle between loads, and
  /// the drag would be computed against an order the server does not use.
  static int compare(BannerItem a, BannerItem b) {
    final bySort = a.sortOrder.compareTo(b.sortOrder);
    return bySort != 0 ? bySort : a.id.compareTo(b.id);
  }

  /// The ids to send to `POST /admin/banners/reorder` for [ordered], or null
  /// when that order cannot be expressed without disturbing rows the caller
  /// does not control.
  ///
  /// The server numbers each id by its index in the list it receives
  /// (`for position, bid in enumerate(ordered_ids)`) and orders the table with
  /// a flat `ORDER BY sort_order ASC, id ASC`. Rows left out of the payload
  /// keep their existing numbers.
  ///
  /// That write is only faithful when the banners in [ordered] already occupy
  /// the first n positions of the table — i.e. their `sort_order` values are a
  /// PERMUTATION of 0..n-1. Then renumbering them 0..n-1 moves the same set of
  /// banners among the same set of slots and nothing outside is disturbed.
  /// [ordered] is the new visible sequence, so its values will generally be out
  /// of ascending order; that is expected and fine. What must not happen is a
  /// value ≥ n (a row from further down the table dragged up, which would
  /// displace rows not in the payload) or a duplicate (two rows claiming one
  /// slot, which the server would tiebreak by id and silently reorder).
  static List<int>? reorderPayload(List<BannerItem> ordered) {
    if (ordered.isEmpty) return null;

    final claimed = <int>{};
    for (final b in ordered) {
      final slot = b.sortOrder;
      if (slot < 0 || slot >= ordered.length) return null;
      if (!claimed.add(slot)) return null; // duplicate -> not a permutation
    }

    return ordered.map((b) => b.id).toList();
  }

  /// Move the tile at [oldIndex] to [newIndex] within [items] and return the
  /// reorder payload, or null when the move cannot be persisted safely.
  ///
  /// The payload is the ids in their new visible order. That is safe only when
  /// the set being reordered already occupies 0..n-1 — see [reorderPayload].
  /// A move that would place a banner in front of a row this screen is not
  /// showing is refused rather than persisted wrong.
  static List<int>? movedOrder(
    List<BannerItem> items,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= items.length) return null;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= items.length) return null;

    final ordered = [...items];
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);

    return reorderPayload(ordered);
  }

  Future<List<BannerItem>> listPublic() async {
    final resp = await api.dio.get(_publicPath);
    return asJsonList(resp.data).map(BannerItem.fromJson).toList();
  }

  Future<BannerItem> create({
    required File imageFile,
    String? title,
    String? linkUrl,
    int? sortOrder,
    bool active = true,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.uri.pathSegments.last,
      ),
      if (title != null && title.isNotEmpty) 'title': title,
      if (linkUrl != null && linkUrl.isNotEmpty) 'link_url': linkUrl,
      // Omitted entirely when null: the backend then appends at the end of
      // the carousel. Sending 0 here is what used to shove every new banner
      // to the front.
      if (sortOrder != null) 'sort_order': sortOrder,
      'active': active,
      'starts_at': _encodeDate(startsAt),
      'ends_at': _encodeDate(endsAt),
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
    DateTime? startsAt,
    bool? clearStartsAt,
    DateTime? endsAt,
    bool? clearEndsAt,
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
    // FastAPI coerces an empty form value to None, so "" is indistinguishable
    // from "field not sent" and cannot mean clear. The backend accepts the
    // literal token `null` as the clear signal instead.
    if (clearStartsAt == true) {
      form['starts_at'] = 'null';
    } else if (startsAt != null) {
      form['starts_at'] = _encodeDate(startsAt);
    }
    if (clearEndsAt == true) {
      form['ends_at'] = 'null';
    } else if (endsAt != null) {
      form['ends_at'] = _encodeDate(endsAt);
    }

    try {
      final resp = await api.dio.patch('$_adminPath/$id', data: FormData.fromMap(form));
      return BannerItem.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapValidationError(e);
    }
  }

  static String _encodeDate(DateTime? d) =>
      d == null ? '' : d.toUtc().toIso8601String();

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
