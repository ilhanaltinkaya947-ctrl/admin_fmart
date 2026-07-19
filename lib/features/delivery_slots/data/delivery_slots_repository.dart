import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';
import 'template_models.dart';

/// Wraps order-service /admin/delivery-slots/* endpoints behind the
/// /gw/order/ gateway prefix.
class DeliverySlotsRepository {
  final ApiClient api;
  DeliverySlotsRepository({required this.api});

  static const String _base = '/gw/order/admin/delivery-slots';

  Future<List<DeliverySlotTemplate>> listTemplates({required int storeId}) async {
    final resp = await api.dio.get(
      '$_base/templates',
      queryParameters: {'store_id': storeId},
    );
    final items = asJsonList((resp.data as Map?)?['items']);
    return items.map(DeliverySlotTemplate.fromJson).toList();
  }

  Future<DeliverySlotTemplate> create(TemplateDraft draft) async {
    try {
      final resp = await api.dio.post('$_base/templates', data: draft.toJson());
      return DeliverySlotTemplate.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapValidationError(e);
    }
  }

  Future<DeliverySlotTemplate> update(int id, TemplatePatch patch) async {
    try {
      final resp = await api.dio.put(
        '$_base/templates/$id',
        data: patch.toJson(),
      );
      return DeliverySlotTemplate.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapValidationError(e);
    }
  }

  Future<void> delete(int id) async {
    await api.dio.delete('$_base/templates/$id');
  }

  Exception _mapValidationError(DioException e) {
    final detail = e.response?.data;
    if (detail is Map && detail['detail'] is String) {
      return SlotTemplateValidationException(detail['detail'] as String);
    }
    if (detail is Map && detail['detail'] is List) {
      // pydantic 422 — pick the first message for the toast.
      final first = (detail['detail'] as List).firstWhere(
        (e) => e is Map && e['msg'] is String,
        orElse: () => null,
      );
      if (first is Map) {
        return SlotTemplateValidationException(first['msg'] as String);
      }
    }
    return e;
  }
}

class SlotTemplateValidationException implements Exception {
  final String message;
  SlotTemplateValidationException(this.message);

  @override
  String toString() => message;
}
