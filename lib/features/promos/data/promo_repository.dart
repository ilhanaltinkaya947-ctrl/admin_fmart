import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';
import 'promo_models.dart';

/// Wraps promo-service's admin surface (`/gw/promo/admin/promos`).
///
/// The customer-facing promo routes (`/apply`, `/calculate`, `/release`) are a
/// different contract owned by the same service and are NOT called from here —
/// the admin app only reads and toggles codes.
class PromoRepository {
  final ApiClient api;
  PromoRepository({required this.api});

  static const String _adminPath = '/gw/promo/admin/promos';

  Future<List<AdminPromo>> list() async {
    final resp = await api.dio.get(_adminPath);
    // asJsonMap tolerates an error envelope / null body. A raw cast threw a
    // CastError that bypassed the DioException handling and blanked the whole
    // Баннеры screen once; do not repeat it here.
    final body = asJsonMap(resp.data);
    final items = (body['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((m) => AdminPromo.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// The promo types the ENGINE can honour.
  ///
  /// Fetched rather than hardcoded: the server owns the allowlist, and a type
  /// added there must appear in the picker without an app release. A hardcoded
  /// list would silently drift and let an operator pick a type that 400s at the
  /// customer's checkout.
  Future<List<String>> types() async {
    final resp = await api.dio.get('$_adminPath/types');
    final data = resp.data;
    if (data is! List) return const [];
    return data.map((e) => e.toString()).toList();
  }

  Future<AdminPromo> create({
    required String code,
    required String promoType,
    bool enabled = true,
    DateTime? expiresAt,
  }) async {
    final body = <String, dynamic>{
      'code': code,
      'promo_type': promoType,
      'enabled': enabled,
      if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
    };
    try {
      final resp = await api.dio.post(_adminPath, data: body);
      return AdminPromo.fromJson(asJsonMap(resp.data));
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Update a code.
  ///
  /// `expiresAt` has three states and they must stay distinguishable, which is
  /// why the "clear" instruction is its own flag rather than a null date:
  /// sending `null` would be indistinguishable from "absent" over JSON, exactly
  /// the trap the banner scheduler hit with FastAPI form fields. So:
  ///   - `clearExpiry: true`      -> clear it
  ///   - `expiresAt: <date>`      -> set it
  ///   - neither                  -> leave it alone
  Future<AdminPromo> update(
    String code, {
    bool? enabled,
    DateTime? expiresAt,
    bool clearExpiry = false,
  }) async {
    final body = <String, dynamic>{
      if (enabled != null) 'enabled': enabled,
      if (clearExpiry) 'clear_expires_at': true,
      if (!clearExpiry && expiresAt != null)
        'expires_at': expiresAt.toUtc().toIso8601String(),
    };
    try {
      final resp = await api.dio.patch('$_adminPath/$code', data: body);
      return AdminPromo.fromJson(asJsonMap(resp.data));
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<PromoRedemption>> redemptions(String code) async {
    final resp = await api.dio.get('$_adminPath/$code/redemptions');
    final data = resp.data;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((m) => PromoRedemption.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  Exception _mapError(DioException e) {
    final detail = e.response?.data;
    if (detail is Map && detail['detail'] is String) {
      return PromoValidationException(detail['detail'] as String);
    }
    return e;
  }
}

/// A deliberate, operator-readable rejection from the service (400/409).
class PromoValidationException implements Exception {
  final String message;
  PromoValidationException(this.message);

  @override
  String toString() => message;
}
