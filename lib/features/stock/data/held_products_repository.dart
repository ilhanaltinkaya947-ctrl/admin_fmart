import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

/// A product hidden from every customer because a human could not find it.
///
/// Placed automatically when a picker reports a line missing, and lifted
/// automatically when 1C reports a delivery. Nobody has to work this list for
/// the system to function — it exists so that a product being invisible is
/// visible to staff, and so a wrong hold has a way out.
class HeldProduct {
  final int productId;
  final String name;

  /// What 1C last claimed while the hold was in force. Usually the whole story:
  /// the feed insisting on 54 units of something nobody could find.
  final int? quantityReportedBy1c;
  final DateTime heldAt;

  HeldProduct({
    required this.productId,
    required this.name,
    required this.quantityReportedBy1c,
    required this.heldAt,
  });

  /// Tolerant on purpose. A single unparseable row must not blank the whole
  /// screen — the screen exists to make hidden products visible, and failing
  /// closed here would hide them twice over.
  static HeldProduct? tryFromJson(Map<String, dynamic> j) {
    final pid = j['product_id'];
    final id = pid is int ? pid : int.tryParse(pid?.toString() ?? '');
    if (id == null) return null;
    final heldRaw = j['held_at']?.toString();
    final held = heldRaw == null ? null : DateTime.tryParse(heldRaw);
    if (held == null) return null;
    final q = j['quantity_reported_by_1c'];
    return HeldProduct(
      productId: id,
      name: (j['name'] ?? '').toString(),
      quantityReportedBy1c: q is int ? q : int.tryParse(q?.toString() ?? ''),
      heldAt: held.toLocal(),
    );
  }
}

class HeldProductsRepository {
  final ApiClient api;
  HeldProductsRepository({required this.api});

  // NOT /internal/* — the gateway blocks that prefix and 404s it so those
  // routes cannot leak externally. Catalog exposes these on a normal admin
  // path with its own role check.
  static const _path = '/gw/catalog/admin/oos-holds';

  Future<List<HeldProduct>> list({required int storeId}) async {
    final resp = await api.dio.get(_path, queryParameters: {'store_id': storeId});
    return _parse(resp.data);
  }

  /// Lift the holds and return what is still held.
  ///
  /// The server answers with the fresh list, so the screen cannot show a row it
  /// has just released without a second round-trip.
  Future<List<HeldProduct>> release({
    required int storeId,
    required List<int> productIds,
  }) async {
    final resp = await api.dio.post(
      '$_path/release',
      data: {'store_id': storeId, 'product_ids': productIds},
    );
    return _parse(resp.data);
  }

  List<HeldProduct> _parse(dynamic data) {
    final map = (data as Map?)?.cast<String, dynamic>() ?? const {};
    final items = (map['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => HeldProduct.tryFromJson(e.cast<String, dynamic>()))
        .whereType<HeldProduct>()
        .toList();
  }
}

/// Thrown so the page can show the server's own message rather than a generic
/// failure — a 403 here means the role check refused, which is worth saying.
class HeldProductsException implements Exception {
  final String message;
  final int? statusCode;
  HeldProductsException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

String describeHeldProductsError(DioException e) {
  final code = e.response?.statusCode;
  if (code == 403) return 'Нужны права сотрудника';
  if (code == 401) return 'Войдите заново';
  final d = e.response?.data;
  if (d is Map && d['detail'] is String) return d['detail'] as String;
  return 'Не удалось загрузить список';
}
