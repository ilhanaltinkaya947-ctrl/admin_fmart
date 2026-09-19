import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

/// A shop as the pickup screen needs to see it.
///
/// Separate from [StoreDto] because that one is the customer-facing
/// `GET /stores`, which returns only ACTIVE shops. An admin screen that
/// silently omitted a deactivated shop would make its toggle state
/// unknowable — Shymkent Mall is exactly that case today.
class AdminStore {
  final int storeId;
  final String storeName;
  final String storeAddress;

  /// Whether the shop appears in the customer app at all. A deactivated shop
  /// can still carry the pickup flag; it just has nobody to show it to. Shown
  /// so switching collection on at a hidden shop does not look like the toggle
  /// did nothing.
  final bool isActive;

  /// Whether this shop hands orders over at a counter.
  final bool pickupAvailable;

  AdminStore({
    required this.storeId,
    required this.storeName,
    required this.storeAddress,
    required this.isActive,
    required this.pickupAvailable,
  });

  /// Tolerant on purpose, like [HeldProduct.tryFromJson]: one unparseable row
  /// must not blank the whole screen.
  static AdminStore? tryFromJson(Map<String, dynamic> j) {
    final raw = j['store_id'];
    final id = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (id == null) return null;
    return AdminStore(
      storeId: id,
      storeName: (j['store_name'] ?? '').toString(),
      storeAddress: (j['store_address'] ?? '').toString(),
      // Defaults chosen so an unknown shop reads as "visible, no collection"
      // rather than the reverse. A missing pickup flag must never render as
      // switched on: the switch is what an admin then trusts.
      isActive: j['is_active'] != false,
      pickupAvailable: j['pickup_available'] == true,
    );
  }

  AdminStore copyWith({bool? pickupAvailable}) => AdminStore(
        storeId: storeId,
        storeName: storeName,
        storeAddress: storeAddress,
        isActive: isActive,
        pickupAvailable: pickupAvailable ?? this.pickupAvailable,
      );
}

class PickupStoresRepository {
  final ApiClient api;
  PickupStoresRepository({required this.api});

  // NOT /internal/* — the gateway blocks that prefix and 404s it. Catalog
  // exposes these on a normal admin path with its own role check, which is
  // admin-only here rather than admin-or-manager.
  static const _path = '/gw/catalog/admin/stores';

  Future<List<AdminStore>> list() async {
    final resp = await api.dio.get(_path);
    final rows = (resp.data as List?) ?? const [];
    return rows
        .whereType<Map>()
        .map((e) => AdminStore.tryFromJson(e.cast<String, dynamic>()))
        .whereType<AdminStore>()
        .toList();
  }

  /// Switch collection on or off at one shop.
  ///
  /// Returns the shop as the SERVER now has it, and the screen renders that
  /// rather than what it optimistically assumed. A switch that flips before
  /// the write lands is a screen that can disagree with the shop floor, and
  /// this particular disagreement ends with a customer at a counter nobody is
  /// staffing.
  Future<AdminStore> setPickup({
    required int storeId,
    required bool enabled,
  }) async {
    final resp = await api.dio.patch(
      '$_path/$storeId/pickup',
      data: {'pickup_available': enabled},
    );
    final parsed = AdminStore.tryFromJson(
      (resp.data as Map).cast<String, dynamic>(),
    );
    if (parsed == null) {
      throw PickupStoresException('Сервер вернул непонятный ответ');
    }
    return parsed;
  }
}

class PickupStoresException implements Exception {
  final String message;
  final int? statusCode;
  PickupStoresException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

String describePickupStoresError(DioException e) {
  final code = e.response?.statusCode;
  // 403 is the interesting one: this endpoint is admin-only, and a manager
  // reaching it is not a bug on their side. Say which right is missing rather
  // than the generic staff wording the hold screen uses.
  if (code == 403) return 'Нужны права администратора';
  if (code == 401) return 'Войдите заново';
  if (code == 404) return 'Магазин не найден';
  final d = e.response?.data;
  if (d is Map && d['detail'] is String) return d['detail'] as String;
  return 'Не удалось загрузить магазины';
}
